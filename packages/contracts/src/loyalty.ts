import { initContract } from "@ts-rest/core";
import { z } from "zod";
import { LocalizedSchema, SlugSchema } from "./schemas.js";

/**
 * Darb loyalty. A partner offers a reward after a number of stamps ("the 6th coffee is free"). A visitor
 * carries an anonymous card: its code is printed and in its QR, and a secret only their phone keeps reads it.
 * The partner's staff stamp the card by scanning it at the counter; every stamp belongs to a person at a place.
 */

const c = initContract();

/** Card codes: ten letters and digits from an alphabet with nothing to misread (no 0/O, 1/I/L, U). */
export const CARD_ALPHABET = "23456789ABCDEFGHJKMNPQRSTVWXYZ";
export const CardCodeSchema = z
  .string()
  .trim()
  .toUpperCase()
  .regex(new RegExp(`^[${CARD_ALPHABET}]{10}$`), "Not a Darb card");

const id = z.string().uuid();
const error = z.object({ message: z.string(), code: z.string().optional() });

/** The header that carries a card's secret, from the visitor's own phone. */
export const CARD_SECRET_HEADER = "x-darb-card";

export const LoyaltyBusinessSchema = z.object({
  id,
  slug: SlugSchema,
  placeSlug: SlugSchema,
  name: LocalizedSchema,
});

export const LoyaltyOfferSchema = z.object({
  id,
  business: LoyaltyBusinessSchema,
  title: LocalizedSchema,
  reward: LocalizedSchema,
  goal: z.number().int(),
  cooldownMinutes: z.number().int(),
  active: z.boolean(),
});
export type LoyaltyOfferDto = z.infer<typeof LoyaltyOfferSchema>;

/** Where a card stands on one offer: stamps since the last reward, and whether the reward is ready. */
export const LoyaltyStandingSchema = z.object({
  offer: LoyaltyOfferSchema,
  stamps: z.number().int(),
  ready: z.boolean(),
  lastStampAt: z.string().nullable(),
  /** When the card can be stamped again for this offer; null when it can now. */
  nextStampAt: z.string().nullable(),
  rewards: z.number().int(),
});
export type LoyaltyStandingDto = z.infer<typeof LoyaltyStandingSchema>;

export const LoyaltyCardSchema = z.object({
  code: z.string(),
  standings: z.array(LoyaltyStandingSchema),
});
export type LoyaltyCardDto = z.infer<typeof LoyaltyCardSchema>;

export const NewCardSchema = z.object({ code: z.string(), secret: z.string() });

export const LoyaltyOfferInputSchema = z.object({
  businessId: id,
  title: LocalizedSchema,
  reward: LocalizedSchema,
  goal: z.number().int().min(2).max(20),
  cooldownMinutes: z
    .number()
    .int()
    .min(0)
    .max(24 * 60)
    .default(180),
  active: z.boolean().default(true),
});
export const LoyaltyOfferPatchSchema = LoyaltyOfferInputSchema.omit({ businessId: true }).partial();

export const LoyaltyInviteSchema = z.object({ token: z.string(), expiresAt: z.string() });

const scan = z.object({ code: CardCodeSchema, offerId: id });
const staffErrors = { 401: error, 403: error, 404: error } as const;

export const loyaltyContract = c.router({
  /** The visitor's side: no account, only the card's secret. */
  cards: {
    create: {
      method: "POST",
      path: "/loyalty/cards",
      body: z.object({}).strict(),
      responses: { 201: NewCardSchema, 429: error },
    },
    me: {
      method: "GET",
      path: "/loyalty/cards/me",
      headers: z.object({ [CARD_SECRET_HEADER]: z.string().min(20).max(100) }),
      responses: { 200: LoyaltyCardSchema, 404: error },
    },
  },
  /** The counter's side: signed in, staff of the business (or a Darb admin). */
  staff: {
    offers: {
      method: "GET",
      path: "/loyalty/staff/offers",
      responses: { 200: z.array(LoyaltyOfferSchema), 401: error, 403: error },
    },
    card: {
      method: "GET",
      path: "/loyalty/staff/cards/:code",
      pathParams: z.object({ code: CardCodeSchema }),
      responses: { 200: LoyaltyCardSchema, ...staffErrors },
    },
    stamp: {
      method: "POST",
      path: "/loyalty/staff/stamp",
      body: scan,
      responses: {
        200: LoyaltyStandingSchema,
        409: error.extend({ nextStampAt: z.string() }),
        ...staffErrors,
      },
    },
    redeem: {
      method: "POST",
      path: "/loyalty/staff/redeem",
      body: scan,
      responses: { 200: LoyaltyStandingSchema, 409: error, ...staffErrors },
    },
    join: {
      method: "POST",
      path: "/loyalty/staff/join",
      body: z.object({ token: z.string().min(20).max(100) }),
      responses: { 200: LoyaltyBusinessSchema, 401: error, 404: error, 410: error },
    },
  },
  /** Darb's admin: the offers, and the links that make someone a partner's staff. */
  admin: {
    offers: {
      method: "GET",
      path: "/admin/loyalty/offers",
      responses: { 200: z.array(LoyaltyOfferSchema), 401: error, 403: error },
    },
    create: {
      method: "POST",
      path: "/admin/loyalty/offers",
      body: LoyaltyOfferInputSchema,
      responses: { 201: LoyaltyOfferSchema, 400: error, 401: error, 403: error, 404: error },
    },
    update: {
      method: "PATCH",
      path: "/admin/loyalty/offers/:id",
      pathParams: z.object({ id }),
      body: LoyaltyOfferPatchSchema,
      responses: { 200: LoyaltyOfferSchema, 401: error, 403: error, 404: error },
    },
    invite: {
      method: "POST",
      path: "/admin/loyalty/businesses/:id/invite",
      pathParams: z.object({ id }),
      body: z.object({}).strict(),
      responses: { 201: LoyaltyInviteSchema, 401: error, 403: error, 404: error },
    },
  },
});
