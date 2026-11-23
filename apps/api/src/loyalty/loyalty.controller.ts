import { Controller, Req, UseGuards } from "@nestjs/common";
import { CARD_SECRET_HEADER, contract } from "@darb/contracts";
import { TsRestHandler, tsRestHandler } from "@ts-rest/nest";
import { Inject } from "@nestjs/common";
import { AdminGuard } from "../auth/admin.guard.js";
import { SignedInGuard, type HelperRequest } from "../auth/helper.guard.js";
import { APP_CONFIG, type AppConfig } from "../config.js";
import { clientIp, type ClientRequest } from "../search/client-ip.js";
import { RateLimiter } from "../search/rate-limiter.js";
import { LoyaltyService, type Outcome, type StaffActor } from "./loyalty.service.js";

type Res = { res?: { setHeader(k: string, v: string): void } };
/** A card and the stamps on it: personal, never cached anywhere. */
const noStore = (req: Res) => req.res?.setHeader("cache-control", "no-store");

/** New cards a visitor's phone may ask for, per hour and address. */
const CARDS_PER_HOUR = 20;

function answer<T>(o: Outcome<T>) {
  if (o.ok) return { status: 200 as const, body: o.value };
  const body = { message: o.message, ...(o.code ? { code: o.code } : {}) };
  return { status: o.status, body: o.nextStampAt ? { ...body, nextStampAt: o.nextStampAt } : body };
}

/** The visitor's side: making a card, and reading it with its secret. */
@Controller()
export class LoyaltyCardsController {
  constructor(
    private readonly loyalty: LoyaltyService,
    private readonly limiter: RateLimiter,
    @Inject(APP_CONFIG) private readonly config: AppConfig,
  ) {}

  @TsRestHandler(contract.loyalty.cards)
  handler(@Req() req: ClientRequest & Res) {
    noStore(req);
    return tsRestHandler(contract.loyalty.cards, {
      create: async () => {
        const ip = clientIp(req, this.config.search.proxyKey);
        const gate = await this.limiter.hit("card", ip, CARDS_PER_HOUR, 3600);
        if (!gate.ok)
          return {
            status: 429,
            body: { message: "Too many new cards from here, try again later" },
          };
        return { status: 201, body: await this.loyalty.createCard() };
      },
      me: async ({ headers }) => {
        const card = await this.loyalty.cardBySecret(headers[CARD_SECRET_HEADER], new Date());
        return card
          ? { status: 200, body: card }
          : { status: 404, body: { message: "No such card" } };
      },
    });
  }
}

/** The counter's side: anyone signed in; what they may stamp is decided per business. */
@Controller()
@UseGuards(SignedInGuard)
export class LoyaltyStaffController {
  constructor(private readonly loyalty: LoyaltyService) {}

  @TsRestHandler(contract.loyalty.staff)
  handler(@Req() req: HelperRequest & Res) {
    noStore(req);
    const actor: StaffActor = { userId: req.helper!.userId, isAdmin: req.helper!.isAdmin };
    return tsRestHandler(contract.loyalty.staff, {
      offers: async () => ({ status: 200, body: await this.loyalty.staffOffers(actor) }),
      card: async ({ params }) =>
        answer(await this.loyalty.cardForStaff(actor, params.code, new Date())) as never,
      stamp: async ({ body }) =>
        answer(await this.loyalty.stamp(actor, body.code, body.offerId, new Date())) as never,
      redeem: async ({ body }) =>
        answer(await this.loyalty.redeem(actor, body.code, body.offerId, new Date())) as never,
      join: async ({ body }) =>
        answer(await this.loyalty.join(actor.userId, body.token, new Date())) as never,
    });
  }
}

/** Darb's admin: offers, and invite links for a partner's staff. */
@Controller()
@UseGuards(AdminGuard)
export class LoyaltyAdminController {
  constructor(private readonly loyalty: LoyaltyService) {}

  @TsRestHandler(contract.loyalty.admin)
  handler(@Req() req: Res) {
    noStore(req);
    return tsRestHandler(contract.loyalty.admin, {
      offers: async () => ({ status: 200, body: await this.loyalty.allOffers() }),
      create: async ({ body }) => {
        const offer = await this.loyalty.createOffer(body);
        return offer
          ? { status: 201, body: offer }
          : { status: 404, body: { message: "No such business" } };
      },
      update: async ({ params, body }) => {
        const offer = await this.loyalty.updateOffer(params.id, body);
        return offer
          ? { status: 200, body: offer }
          : { status: 404, body: { message: "No such offer" } };
      },
      invite: async ({ params }) => {
        const invite = await this.loyalty.invite(params.id, new Date());
        return invite
          ? { status: 201, body: invite }
          : { status: 404, body: { message: "No such business" } };
      },
    });
  }
}
