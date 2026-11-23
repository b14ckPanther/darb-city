import { createHash, randomBytes, randomInt } from "node:crypto";
import { Injectable } from "@nestjs/common";
import {
  CARD_ALPHABET,
  type LoyaltyCardDto,
  type LoyaltyOfferDto,
  type LoyaltyStandingDto,
} from "@darb/contracts";
import { Prisma } from "../generated/prisma/client.js";
import { PrismaService } from "../prisma/prisma.service.js";

/** Who is at the counter: a signed-in person, and whether they are a Darb admin (who may stamp anywhere). */
export interface StaffActor {
  userId: string;
  isAdmin: boolean;
}

const INVITE_DAYS = 14;
const hash = (s: string) => createHash("sha256").update(s).digest("hex");
const newCode = () =>
  Array.from({ length: 10 }, () => CARD_ALPHABET[randomInt(CARD_ALPHABET.length)]).join("");

const offerSelect = {
  id: true,
  title: true,
  reward: true,
  goal: true,
  cooldownMinutes: true,
  active: true,
  business: { select: { id: true, slug: true, name: true, place: { select: { slug: true } } } },
} satisfies Prisma.LoyaltyOfferSelect;
type OfferRow = Prisma.LoyaltyOfferGetPayload<{ select: typeof offerSelect }>;

const toOffer = (o: OfferRow): LoyaltyOfferDto => ({
  id: o.id,
  business: {
    id: o.business.id,
    slug: o.business.slug,
    placeSlug: o.business.place.slug,
    name: o.business.name as LoyaltyOfferDto["business"]["name"],
  },
  title: o.title as LoyaltyOfferDto["title"],
  reward: o.reward as LoyaltyOfferDto["reward"],
  goal: o.goal,
  cooldownMinutes: o.cooldownMinutes,
  active: o.active,
});

export type Outcome<T> =
  | { ok: true; value: T }
  | {
      ok: false;
      status: 403 | 404 | 409 | 410;
      message: string;
      code?: string;
      nextStampAt?: string;
    };
const fail = <T>(
  status: 403 | 404 | 409 | 410,
  message: string,
  extra: { code?: string; nextStampAt?: string } = {},
): Outcome<T> => ({ ok: false, status, message, ...extra });

@Injectable()
export class LoyaltyService {
  constructor(private readonly prisma: PrismaService) {}

  /** A new anonymous card. The secret is returned once and only its hash is kept. */
  async createCard(): Promise<{ code: string; secret: string }> {
    const secret = randomBytes(24).toString("base64url");
    for (let attempt = 0; ; attempt++) {
      try {
        const card = await this.prisma.loyaltyCard.create({
          data: { code: newCode(), secretHash: hash(secret) },
        });
        return { code: card.code, secret };
      } catch (err) {
        // a code already taken (about one in 590 trillion per card): draw another
        if (
          attempt < 4 &&
          err instanceof Prisma.PrismaClientKnownRequestError &&
          err.code === "P2002"
        )
          continue;
        throw err;
      }
    }
  }

  /** The card its owner's phone reads: every active offer, and where the card stands on each. */
  async cardBySecret(secret: string, now: Date): Promise<LoyaltyCardDto | null> {
    const card = await this.prisma.loyaltyCard.findUnique({ where: { secretHash: hash(secret) } });
    if (!card) return null;
    const offers = await this.prisma.loyaltyOffer.findMany({
      where: { active: true },
      select: offerSelect,
      orderBy: { createdAt: "asc" },
    });
    return { code: card.code, standings: await this.standings(card.id, offers, now) };
  }

  /** The offers this person may stamp for: their businesses' active offers, or every active one for an admin. */
  async staffOffers(actor: StaffActor): Promise<LoyaltyOfferDto[]> {
    const rows = await this.prisma.loyaltyOffer.findMany({
      where: {
        active: true,
        ...(actor.isAdmin
          ? {}
          : { business: { loyaltyStaff: { some: { userId: actor.userId } } } }),
      },
      select: offerSelect,
      orderBy: { createdAt: "asc" },
    });
    return rows.map(toOffer);
  }

  /** A scanned card, as the counter sees it: only the offers this person may stamp for. */
  async cardForStaff(actor: StaffActor, code: string, now: Date): Promise<Outcome<LoyaltyCardDto>> {
    const card = await this.prisma.loyaltyCard.findUnique({ where: { code } });
    if (!card) return fail(404, "This card is not a Darb card");
    const offers = await this.prisma.loyaltyOffer.findMany({
      where: {
        active: true,
        ...(actor.isAdmin
          ? {}
          : { business: { loyaltyStaff: { some: { userId: actor.userId } } } }),
      },
      select: offerSelect,
      orderBy: { createdAt: "asc" },
    });
    if (offers.length === 0) return fail(403, "You do not stamp cards for any business yet");
    return {
      ok: true,
      value: { code: card.code, standings: await this.standings(card.id, offers, now) },
    };
  }

  async stamp(
    actor: StaffActor,
    code: string,
    offerId: string,
    now: Date,
  ): Promise<Outcome<LoyaltyStandingDto>> {
    const found = await this.target(actor, code, offerId);
    if (!found.ok) return found;
    const { card, offer } = found.value;
    // one stamp at a time per card and offer, so two quick taps cannot both pass the cooldown
    return this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${`${card.id}:${offer.id}`}))`;
      const last = await tx.loyaltyEvent.findFirst({
        where: { cardId: card.id, offerId: offer.id, kind: "stamp" },
        orderBy: { at: "desc" },
      });
      const nextAt = last ? new Date(last.at.getTime() + offer.cooldownMinutes * 60_000) : null;
      if (nextAt && nextAt > now)
        return fail<LoyaltyStandingDto>(409, "This card was stamped here a short while ago", {
          code: "too_soon",
          nextStampAt: nextAt.toISOString(),
        });
      const standing = (await this.standings(card.id, [offer], now, tx))[0]!;
      if (standing.ready)
        return fail<LoyaltyStandingDto>(409, "The reward is ready: hand it over first", {
          code: "reward_ready",
        });
      await tx.loyaltyEvent.create({
        data: { cardId: card.id, offerId: offer.id, kind: "stamp", staffId: actor.userId, at: now },
      });
      return { ok: true as const, value: (await this.standings(card.id, [offer], now, tx))[0]! };
    });
  }

  async redeem(
    actor: StaffActor,
    code: string,
    offerId: string,
    now: Date,
  ): Promise<Outcome<LoyaltyStandingDto>> {
    const found = await this.target(actor, code, offerId);
    if (!found.ok) return found;
    const { card, offer } = found.value;
    return this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${`${card.id}:${offer.id}`}))`;
      const standing = (await this.standings(card.id, [offer], now, tx))[0]!;
      if (!standing.ready)
        return fail<LoyaltyStandingDto>(409, "The reward is not ready yet", { code: "not_ready" });
      await tx.loyaltyEvent.create({
        data: {
          cardId: card.id,
          offerId: offer.id,
          kind: "redeem",
          staffId: actor.userId,
          at: now,
        },
      });
      return { ok: true as const, value: (await this.standings(card.id, [offer], now, tx))[0]! };
    });
  }

  /** Opening an invite link signed in makes this person staff of its business. */
  async join(
    userId: string,
    token: string,
    now: Date,
  ): Promise<Outcome<LoyaltyOfferDto["business"]>> {
    const invite = await this.prisma.loyaltyInvite.findUnique({
      where: { tokenHash: hash(token) },
      include: {
        business: {
          select: { id: true, slug: true, name: true, place: { select: { slug: true } } },
        },
      },
    });
    if (!invite) return fail(404, "This invite link is not valid");
    if (invite.expiresAt <= now)
      return fail(410, "This invite link has expired; ask Darb for a new one");
    await this.prisma.$transaction([
      this.prisma.loyaltyStaff.upsert({
        where: { businessId_userId: { businessId: invite.businessId, userId } },
        create: { businessId: invite.businessId, userId },
        update: {},
      }),
      this.prisma.loyaltyInvite.update({
        where: { id: invite.id },
        data: { uses: { increment: 1 } },
      }),
    ]);
    const b = invite.business;
    return {
      ok: true,
      value: {
        id: b.id,
        slug: b.slug,
        placeSlug: b.place.slug,
        name: b.name as LoyaltyOfferDto["business"]["name"],
      },
    };
  }

  // admin

  async allOffers(): Promise<LoyaltyOfferDto[]> {
    const rows = await this.prisma.loyaltyOffer.findMany({
      select: offerSelect,
      orderBy: { createdAt: "desc" },
    });
    return rows.map(toOffer);
  }

  async createOffer(input: {
    businessId: string;
    title: object;
    reward: object;
    goal: number;
    cooldownMinutes: number;
    active: boolean;
  }): Promise<LoyaltyOfferDto | null> {
    const business = await this.prisma.business.findUnique({ where: { id: input.businessId } });
    if (!business) return null;
    const row = await this.prisma.loyaltyOffer.create({
      data: {
        ...input,
        title: input.title as Prisma.InputJsonValue,
        reward: input.reward as Prisma.InputJsonValue,
      },
      select: offerSelect,
    });
    return toOffer(row);
  }

  async updateOffer(
    id: string,
    patch: {
      title?: object;
      reward?: object;
      goal?: number;
      cooldownMinutes?: number;
      active?: boolean;
    },
  ): Promise<LoyaltyOfferDto | null> {
    const exists = await this.prisma.loyaltyOffer.findUnique({ where: { id } });
    if (!exists) return null;
    const row = await this.prisma.loyaltyOffer.update({
      where: { id },
      data: {
        ...patch,
        title: patch.title as Prisma.InputJsonValue | undefined,
        reward: patch.reward as Prisma.InputJsonValue | undefined,
      },
      select: offerSelect,
    });
    return toOffer(row);
  }

  /** A new invite link's token for a business's staff, good for two weeks. Only its hash is kept. */
  async invite(
    businessId: string,
    now: Date,
  ): Promise<{ token: string; expiresAt: string } | null> {
    const business = await this.prisma.business.findUnique({ where: { id: businessId } });
    if (!business) return null;
    const token = randomBytes(24).toString("base64url");
    const expiresAt = new Date(now.getTime() + INVITE_DAYS * 86_400_000);
    await this.prisma.loyaltyInvite.create({
      data: { tokenHash: hash(token), businessId, expiresAt },
    });
    return { token, expiresAt: expiresAt.toISOString() };
  }

  // shared

  /** The card and the offer a scan is about, when this person may stamp for that offer's business. */
  private async target(actor: StaffActor, code: string, offerId: string) {
    const [card, offer] = await Promise.all([
      this.prisma.loyaltyCard.findUnique({ where: { code } }),
      this.prisma.loyaltyOffer.findUnique({ where: { id: offerId }, select: offerSelect }),
    ]);
    if (!card) return fail<never>(404, "This card is not a Darb card");
    if (!offer || !offer.active) return fail<never>(404, "This offer is not running");
    if (!actor.isAdmin) {
      const staff = await this.prisma.loyaltyStaff.findUnique({
        where: { businessId_userId: { businessId: offer.business.id, userId: actor.userId } },
      });
      if (!staff) return fail<never>(403, "You do not stamp cards for this business");
    }
    return { ok: true as const, value: { card, offer } };
  }

  /** Stamps since the last reward, per offer, read in one query. */
  private async standings(
    cardId: string,
    offers: OfferRow[],
    now: Date,
    db: Prisma.TransactionClient = this.prisma,
  ): Promise<LoyaltyStandingDto[]> {
    if (offers.length === 0) return [];
    const events = await db.loyaltyEvent.findMany({
      where: { cardId, offerId: { in: offers.map((o) => o.id) } },
      orderBy: { at: "asc" },
      select: { offerId: true, kind: true, at: true },
    });
    return offers.map((o) => {
      let stamps = 0;
      let rewards = 0;
      let last: Date | null = null;
      for (const e of events) {
        if (e.offerId !== o.id) continue;
        if (e.kind === "redeem") {
          stamps = 0;
          rewards++;
        } else {
          stamps++;
          last = e.at;
        }
      }
      const next = last ? new Date(last.getTime() + o.cooldownMinutes * 60_000) : null;
      return {
        offer: toOffer(o),
        stamps,
        ready: stamps >= o.goal,
        lastStampAt: last?.toISOString() ?? null,
        nextStampAt: next && next > now ? next.toISOString() : null,
        rewards,
      };
    });
  }
}
