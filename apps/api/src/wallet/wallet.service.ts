import { createHmac, timingSafeEqual } from "node:crypto";
import { readFileSync } from "node:fs";
import { Inject, Injectable, Logger } from "@nestjs/common";
import { APP_CONFIG, type AppConfig } from "../config.js";
import { LoyaltyService } from "../loyalty/loyalty.service.js";
import { PrismaService } from "../prisma/prisma.service.js";
import type { PassPusher } from "./apns.js";
import { passContent, strip } from "./pass.js";
import { pem, signedPass, type PassCredentials } from "./sign.js";

export const PASS_PUSHER = Symbol("PASS_PUSHER");

const ASSETS = new URL("../../assets/wallet/", import.meta.url);
const asset = (name: string) => readFileSync(new URL(name, ASSETS));

/** What a phone's camera opens from the card's QR: the counter's page for this card. */
export const scanUrl = (code: string) => `https://darb.co.il/helpers/stamp/${code}`;

/** The card in Apple Wallet: the signed pass, the phones holding it, and waking them when it changes. */
@Injectable()
export class WalletService {
  private readonly logger = new Logger(WalletService.name);
  readonly creds: PassCredentials | null;
  private readonly images: Map<string, Buffer>;

  constructor(
    @Inject(APP_CONFIG) private readonly config: AppConfig,
    private readonly prisma: PrismaService,
    private readonly loyalty: LoyaltyService,
    @Inject(PASS_PUSHER) private readonly pusher: PassPusher | null,
  ) {
    const w = config.wallet;
    this.creds =
      w.cert && w.key
        ? { cert: pem(w.cert), key: pem(w.key), wwdr: asset("apple-wwdr-g4.pem").toString("utf8") }
        : null;
    if (!this.creds)
      this.logger.log("Apple Wallet is off: WALLET_PASS_CERT and WALLET_PASS_KEY are not set");
    this.images = new Map(
      ["icon.png", "icon@2x.png", "icon@3x.png", "logo.png", "logo@2x.png", "logo@3x.png"].map(
        (n) => [n, asset(n)] as const,
      ),
    );
  }

  get passType(): string {
    return this.config.wallet.passType;
  }

  get enabled(): boolean {
    return this.creds !== null;
  }

  /** The token Wallet sends back on every call for this card: derived from the pass key, so nothing is stored. */
  authToken(code: string): string {
    return createHmac("sha256", this.creds?.key ?? "off")
      .update(`wallet:${code}`)
      .digest("base64url");
  }

  /** Whether an "ApplePass <token>" header is this card's. */
  authorized(code: string, header: string | undefined): boolean {
    if (!this.creds) return false;
    const given = /^ApplePass\s+(\S+)$/.exec(header ?? "")?.[1];
    if (!given) return false;
    const a = Buffer.from(given);
    const b = Buffer.from(this.authToken(code));
    return a.length === b.length && timingSafeEqual(a, b);
  }

  /** The signed .pkpass for a card, and when what it shows last changed; null when Wallet is off or no such card. */
  async pass(code: string): Promise<{ data: Buffer; updatedAt: Date } | null> {
    if (!this.creds) return null;
    const card = await this.loyalty.cardByCode(code, new Date());
    if (!card) return null;
    const w = this.config.wallet;
    const { files, front } = passContent(card, {
      passType: w.passType,
      teamId: w.teamId,
      serviceUrl: w.serviceUrl,
      authToken: this.authToken(card.code),
      scanUrl: scanUrl(card.code),
    });
    for (const [n, b] of this.images) files.set(n, b);
    for (const [n, b] of await strip(front)) files.set(n, b);
    return { data: signedPass(files, this.creds), updatedAt: card.updatedAt };
  }

  /** A phone adding the card (201), or adding it again (200). */
  async register(deviceId: string, code: string, pushToken: string): Promise<200 | 201 | 404> {
    const card = await this.prisma.loyaltyCard.findUnique({
      where: { code },
      select: { id: true },
    });
    if (!card) return 404;
    const existing = await this.prisma.walletRegistration.findUnique({
      where: { deviceId_cardId: { deviceId, cardId: card.id } },
    });
    if (existing) {
      if (existing.pushToken !== pushToken)
        await this.prisma.walletRegistration.update({
          where: { id: existing.id },
          data: { pushToken },
        });
      return 200;
    }
    await this.prisma.walletRegistration.create({ data: { deviceId, pushToken, cardId: card.id } });
    return 201;
  }

  async unregister(deviceId: string, code: string): Promise<void> {
    await this.prisma.walletRegistration.deleteMany({ where: { deviceId, card: { code } } });
  }

  /** The cards on a phone that changed after `since` (Wallet's own tag: milliseconds since 1970). */
  async updatedSince(
    deviceId: string,
    since: string | undefined,
  ): Promise<{ serialNumbers: string[]; lastUpdated: string } | null> {
    const after = since && /^\d+$/.test(since) ? new Date(Number(since)) : null;
    const cards = await this.prisma.loyaltyCard.findMany({
      where: {
        registrations: { some: { deviceId } },
        ...(after ? { updatedAt: { gt: after } } : {}),
      },
      select: { code: true, updatedAt: true },
    });
    if (cards.length === 0) return null;
    const last = Math.max(...cards.map((c) => c.updatedAt.getTime()));
    return { serialNumbers: cards.map((c) => c.code), lastUpdated: String(last) };
  }

  /**
   * A card's stamps changed: mark it newer and wake the phones holding it. Never fails the stamp it follows, and
   * does not hold it up.
   */
  cardChanged(code: string): void {
    void this.touch({ code }).catch((err: unknown) =>
      this.logger.warn(`Wallet update failed: ${String(err)}`),
    );
  }

  /** An offer started, stopped or changed: every card in a Wallet shows it, so all of them are newer. */
  offersChanged(): void {
    void this.touch({ registrations: { some: {} } }).catch((err: unknown) =>
      this.logger.warn(`Wallet update failed: ${String(err)}`),
    );
  }

  private async touch(
    where: { code: string } | { registrations: { some: object } },
  ): Promise<void> {
    await this.prisma.loyaltyCard.updateMany({ where, data: { updatedAt: new Date() } });
    if (!this.pusher) return;
    const regs = await this.prisma.walletRegistration.findMany({
      where: { card: where },
      select: { pushToken: true },
    });
    const gone = await this.pusher.push([...new Set(regs.map((r) => r.pushToken))]);
    if (gone.length)
      await this.prisma.walletRegistration.deleteMany({ where: { pushToken: { in: gone } } });
  }
}
