import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  HttpCode,
  Logger,
  Param,
  Post,
  Query,
  Res,
} from "@nestjs/common";
import { CARD_SECRET_HEADER } from "@darb/contracts";
import { LoyaltyService } from "../loyalty/loyalty.service.js";
import { WalletService } from "./wallet.service.js";

/** What the HTTP layer needs from the response; Express's response has all of it. */
interface Reply {
  status(code: number): Reply;
  setHeader(name: string, value: string): void;
  json(body: unknown): void;
  end(body?: Buffer): void;
}

const PKPASS = "application/vnd.apple.pkpass";

/**
 * The card in Apple Wallet. The visitor's app downloads the pass with the card's secret; after that Wallet itself
 * calls the /wallet/v1 routes (Apple's PassKit web service), proving itself with the pass's own token.
 */
@Controller()
export class WalletController {
  private readonly logger = new Logger("Wallet");

  constructor(
    private readonly wallet: WalletService,
    private readonly loyalty: LoyaltyService,
  ) {}

  /** The visitor's own card as a .pkpass, read with the secret only their phone holds. */
  @Get("loyalty/cards/me/pass")
  async mine(@Headers(CARD_SECRET_HEADER) secret: string | undefined, @Res() res: Reply) {
    res.setHeader("cache-control", "no-store");
    if (!this.wallet.enabled)
      return res.status(503).json({ message: "Apple Wallet is not set up yet" });
    const card = secret ? await this.loyalty.cardBySecret(secret, new Date()) : null;
    const pass = card ? await this.wallet.pass(card.code) : null;
    if (!pass) return res.status(404).json({ message: "No such card" });
    res.setHeader("content-type", PKPASS);
    res.setHeader("content-disposition", 'attachment; filename="darb.pkpass"');
    res.status(200).end(pass.data);
  }

  @Post("wallet/v1/devices/:device/registrations/:type/:serial")
  async register(
    @Param("device") device: string,
    @Param("type") type: string,
    @Param("serial") serial: string,
    @Headers("authorization") auth: string | undefined,
    @Body() body: { pushToken?: unknown },
    @Res() res: Reply,
  ) {
    if (!this.ours(type) || !this.wallet.authorized(serial, auth)) return res.status(401).end();
    const token = typeof body?.pushToken === "string" ? body.pushToken : "";
    if (!/^[0-9a-fA-F]{16,200}$/.test(token) || device.length > 200) return res.status(400).end();
    const status = await this.wallet.register(device, serial, token);
    res.status(status === 404 ? 401 : status).end();
  }

  @Get("wallet/v1/devices/:device/registrations/:type")
  async updated(
    @Param("device") device: string,
    @Param("type") type: string,
    @Query("passesUpdatedSince") since: string | undefined,
    @Res() res: Reply,
  ) {
    if (!this.ours(type)) return res.status(404).end();
    const found = await this.wallet.updatedSince(device, since);
    if (!found) return res.status(204).end();
    res.status(200).json(found);
  }

  @Delete("wallet/v1/devices/:device/registrations/:type/:serial")
  async unregister(
    @Param("device") device: string,
    @Param("type") type: string,
    @Param("serial") serial: string,
    @Headers("authorization") auth: string | undefined,
    @Res() res: Reply,
  ) {
    if (!this.ours(type) || !this.wallet.authorized(serial, auth)) return res.status(401).end();
    await this.wallet.unregister(device, serial);
    res.status(200).end();
  }

  @Get("wallet/v1/passes/:type/:serial")
  async latest(
    @Param("type") type: string,
    @Param("serial") serial: string,
    @Headers("authorization") auth: string | undefined,
    @Headers("if-modified-since") since: string | undefined,
    @Res() res: Reply,
  ) {
    if (!this.ours(type) || !this.wallet.authorized(serial, auth)) return res.status(401).end();
    const pass = await this.wallet.pass(serial);
    if (!pass) return res.status(404).end();
    // HTTP dates have whole seconds
    const modified = Math.floor(pass.updatedAt.getTime() / 1000) * 1000;
    if (since && Date.parse(since) >= modified) return res.status(304).end();
    res.setHeader("content-type", PKPASS);
    res.setHeader("last-modified", new Date(modified).toUTCString());
    res.setHeader("cache-control", "no-store");
    res.status(200).end(pass.data);
  }

  /** Wallet reports its own errors here; kept in the logs to see why a phone refused a pass. */
  @Post("wallet/v1/log")
  @HttpCode(200)
  log(@Body() body: { logs?: unknown }) {
    const logs = Array.isArray(body?.logs) ? body.logs.slice(0, 20) : [];
    for (const line of logs) this.logger.warn(String(line).slice(0, 500));
  }

  private ours(type: string): boolean {
    return this.wallet.enabled && type === this.wallet.passType;
  }
}
