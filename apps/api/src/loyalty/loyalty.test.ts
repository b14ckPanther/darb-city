import type { INestApplication } from "@nestjs/common";
import request from "supertest";
import { afterAll, beforeAll, beforeEach, expect, it } from "vitest";
import { ADMIN, STRANGER, createAdminTestApp } from "../../test/admin.js";
import { resetDatabase } from "../../test/db.js";
import { seedFixtures, type Fixtures } from "../../test/fixtures.js";
import type { PrismaService } from "../prisma/prisma.service.js";

const BARISTA = "Bearer fake.user_barista.barista@cafe.test";

let app: INestApplication;
let prisma: PrismaService;
let f: Fixtures;
beforeAll(async () => {
  ({ app, prisma } = await createAdminTestApp());
});
beforeEach(async () => {
  await resetDatabase(prisma);
  f = await seedFixtures(prisma);
});
afterAll(() => app.close());
const http = () => request(app.getHttpServer());

const offerBody = (businessId: string, goal = 3) => ({
  businessId,
  title: { en: "Coffee" },
  reward: { en: "A free coffee" },
  goal,
  cooldownMinutes: 180,
});

/** An offer at Abu Salim, a card, and the barista made staff there through an invite link. */
async function setUp(goal = 3) {
  const offer = await http()
    .post("/admin/loyalty/offers")
    .set("authorization", ADMIN)
    .send(offerBody(f.abuSalim.id, goal));
  expect(offer.status, JSON.stringify(offer.body)).toBe(201);
  const card = await http().post("/loyalty/cards").send({});
  expect(card.status).toBe(201);
  const invite = await http()
    .post(`/admin/loyalty/businesses/${f.abuSalim.id}/invite`)
    .set("authorization", ADMIN)
    .send({});
  expect(invite.status).toBe(201);
  const joined = await http()
    .post("/loyalty/staff/join")
    .set("authorization", BARISTA)
    .send({ token: invite.body.token });
  expect(joined.status, JSON.stringify(joined.body)).toBe(200);
  expect(joined.body.slug).toBe("abu-salim");
  return {
    offerId: offer.body.id as string,
    code: card.body.code as string,
    secret: card.body.secret as string,
  };
}

/** Moves every stamp on the card back in time, as if the cooldown had passed. */
const later = (minutes: number) =>
  prisma.$executeRaw`UPDATE "LoyaltyEvent" SET "at" = "at" - make_interval(mins => ${minutes})`;

it("makes an anonymous card that only its secret reads", async () => {
  const { code, secret } = await setUp();
  expect(code).toMatch(/^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{10}$/);
  const me = await http().get("/loyalty/cards/me").set("x-darb-card", secret);
  expect(me.status).toBe(200);
  expect(me.headers["cache-control"]).toBe("no-store");
  expect(me.body.code).toBe(code);
  expect(me.body.standings).toHaveLength(1);
  expect(me.body.standings[0]).toMatchObject({ stamps: 0, ready: false, rewards: 0 });
  const wrong = await http().get("/loyalty/cards/me").set("x-darb-card", "x".repeat(32));
  expect(wrong.status).toBe(404);
  // only the secret's hash is kept
  const row = await prisma.loyaltyCard.findUniqueOrThrow({ where: { code } });
  expect(row.secretHash).not.toContain(secret);
});

it("stamps once per cooldown, refuses a stamp past the goal, and redeems the reward", async () => {
  const { offerId, code, secret } = await setUp(2);
  const stamp = () =>
    http().post("/loyalty/staff/stamp").set("authorization", BARISTA).send({ code, offerId });

  const first = await stamp();
  expect(first.status).toBe(200);
  expect(first.body).toMatchObject({ stamps: 1, ready: false });

  const again = await stamp();
  expect(again.status).toBe(409);
  expect(again.body.code).toBe("too_soon");
  expect(new Date(again.body.nextStampAt).getTime()).toBeGreaterThan(Date.now());

  await later(181);
  const second = await stamp();
  expect(second.body).toMatchObject({ stamps: 2, ready: true });

  await later(181);
  const third = await stamp();
  expect(third.status).toBe(409);
  expect(third.body.code).toBe("reward_ready");

  const redeemed = await http()
    .post("/loyalty/staff/redeem")
    .set("authorization", BARISTA)
    .send({ code, offerId });
  expect(redeemed.status).toBe(200);
  expect(redeemed.body).toMatchObject({ stamps: 0, ready: false, rewards: 1 });
  const notReady = await http()
    .post("/loyalty/staff/redeem")
    .set("authorization", BARISTA)
    .send({ code, offerId });
  expect(notReady.status).toBe(409);

  // the owner sees the same, and every stamp names who gave it
  const me = await http().get("/loyalty/cards/me").set("x-darb-card", secret);
  expect(me.body.standings[0]).toMatchObject({ stamps: 0, rewards: 1 });
  const events = await prisma.loyaltyEvent.findMany({ include: { staff: true } });
  expect(new Set(events.map((e) => e.staff.clerkUserId))).toEqual(new Set(["user_barista"]));
});

it("two taps at once give one stamp", async () => {
  const { offerId, code } = await setUp();
  const tap = () =>
    http().post("/loyalty/staff/stamp").set("authorization", BARISTA).send({ code, offerId });
  const results = await Promise.all([tap(), tap(), tap()]);
  expect(results.map((r) => r.status).sort()).toEqual([200, 409, 409]);
  expect(await prisma.loyaltyEvent.count()).toBe(1);
});

it("lets only the business's staff and Darb's admins stamp", async () => {
  const { offerId, code } = await setUp();
  const stranger = await http()
    .post("/loyalty/staff/stamp")
    .set("authorization", STRANGER)
    .send({ code, offerId });
  expect(stranger.status).toBe(403);
  const strangerCard = await http()
    .get(`/loyalty/staff/cards/${code}`)
    .set("authorization", STRANGER);
  expect(strangerCard.status).toBe(403);
  expect((await http().get("/loyalty/staff/offers").set("authorization", STRANGER)).body).toEqual(
    [],
  );
  const signedOut = await http().post("/loyalty/staff/stamp").send({ code, offerId });
  expect(signedOut.status).toBe(401);

  const admin = await http()
    .post("/loyalty/staff/stamp")
    .set("authorization", ADMIN)
    .send({ code, offerId });
  expect(admin.status).toBe(200);
  const offers = await http().get("/loyalty/staff/offers").set("authorization", BARISTA);
  expect(offers.body.map((o: { id: string }) => o.id)).toEqual([offerId]);
  const scanned = await http()
    .get(`/loyalty/staff/cards/${code.toLowerCase()}`)
    .set("authorization", BARISTA);
  expect(scanned.status).toBe(200);
  expect(scanned.body.standings[0].stamps).toBe(1);
});

it("refuses unknown cards, stopped offers and expired invites", async () => {
  const { offerId, code } = await setUp();
  const unknown = await http()
    .post("/loyalty/staff/stamp")
    .set("authorization", BARISTA)
    .send({ code: "ZZZZZZZZZZ", offerId });
  expect(unknown.status).toBe(404);
  const notACard = await http()
    .post("/loyalty/staff/stamp")
    .set("authorization", BARISTA)
    .send({ code: "hello", offerId });
  expect(notACard.status).toBe(400);

  const stopped = await http()
    .patch(`/admin/loyalty/offers/${offerId}`)
    .set("authorization", ADMIN)
    .send({ active: false });
  expect(stopped.body.active).toBe(false);
  const off = await http()
    .post("/loyalty/staff/stamp")
    .set("authorization", BARISTA)
    .send({ code, offerId });
  expect(off.status).toBe(404);

  const invite = await http()
    .post(`/admin/loyalty/businesses/${f.tamraBarber.id}/invite`)
    .set("authorization", ADMIN)
    .send({});
  await prisma.loyaltyInvite.updateMany({ data: { expiresAt: new Date(Date.now() - 1000) } });
  const expired = await http()
    .post("/loyalty/staff/join")
    .set("authorization", STRANGER)
    .send({ token: invite.body.token });
  expect(expired.status).toBe(410);
  const bogus = await http()
    .post("/loyalty/staff/join")
    .set("authorization", STRANGER)
    .send({ token: "y".repeat(32) });
  expect(bogus.status).toBe(404);
});

it("keeps the offers and invites to Darb's admins", async () => {
  expect((await http().get("/admin/loyalty/offers").set("authorization", STRANGER)).status).toBe(
    403,
  );
  const create = await http()
    .post("/admin/loyalty/offers")
    .set("authorization", STRANGER)
    .send(offerBody(f.abuSalim.id));
  expect(create.status).toBe(403);
  const invite = await http()
    .post(`/admin/loyalty/businesses/${f.abuSalim.id}/invite`)
    .set("authorization", STRANGER)
    .send({});
  expect(invite.status).toBe(403);
  const missing = await http()
    .post("/admin/loyalty/offers")
    .set("authorization", ADMIN)
    .send(offerBody("0190a000-0000-7000-8000-00000000abcd"));
  expect(missing.status).toBe(404);
});
