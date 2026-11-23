import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { INestApplication } from "@nestjs/common";
import forge from "node-forge";
import request from "supertest";
import { afterAll, beforeAll, beforeEach, expect, it } from "vitest";
import { ADMIN, createAdminTestApp } from "../../test/admin.js";
import { resetDatabase } from "../../test/db.js";
import { seedFixtures, type Fixtures } from "../../test/fixtures.js";
import { APP_CONFIG, loadConfig } from "../config.js";
import type { PrismaService } from "../prisma/prisma.service.js";
import { RecordingPusher } from "./apns.js";
import { PASS_PUSHER } from "./wallet.service.js";

const BARISTA = "Bearer fake.user_barista.barista@cafe.test";
const TYPE = "pass.il.co.darb.loyalty";
const DEVICE = "a1b2c3d4e5f6";
const PUSH = "ab".repeat(32);

/** A throwaway certificate standing in for Apple's: the pass is signed the same way, just not trusted. */
function testCredentials() {
  const keys = forge.pki.rsa.generateKeyPair(1024);
  const cert = forge.pki.createCertificate();
  cert.publicKey = keys.publicKey;
  cert.serialNumber = "01";
  cert.validity.notBefore = new Date(Date.now() - 86_400_000);
  cert.validity.notAfter = new Date(Date.now() + 86_400_000);
  const name = [{ name: "commonName", value: "Pass Type ID: test" }];
  cert.setSubject(name);
  cert.setIssuer(name);
  cert.sign(keys.privateKey, forge.md.sha256.create());
  return {
    cert: forge.pki.certificateToPem(cert),
    key: forge.pki.privateKeyToPem(keys.privateKey),
  };
}

/** The entries of a zip of stored files. */
function unzip(data: Buffer): Map<string, Buffer> {
  const out = new Map<string, Buffer>();
  let at = 0;
  while (data.readUInt32LE(at) === 0x04034b50) {
    expect(data.readUInt16LE(at + 8)).toBe(0);
    const size = data.readUInt32LE(at + 18);
    const nameLength = data.readUInt16LE(at + 26);
    const extra = data.readUInt16LE(at + 28);
    const name = data.subarray(at + 30, at + 30 + nameLength).toString("utf8");
    const start = at + 30 + nameLength + extra;
    out.set(name, data.subarray(start, start + size));
    at = start + size;
  }
  return out;
}

const binary = (res: request.Response, cb: (err: Error | null, body: Buffer) => void) => {
  const chunks: Buffer[] = [];
  res.on("data", (c: Buffer) => chunks.push(c));
  res.on("end", () => cb(null, Buffer.concat(chunks)));
};

const creds = testCredentials();
const pusher = new RecordingPusher();
let app: INestApplication;
let prisma: PrismaService;
let f: Fixtures;
beforeAll(async () => {
  ({ app, prisma } = await createAdminTestApp((b) =>
    b
      .overrideProvider(APP_CONFIG)
      .useValue(
        loadConfig({
          ...process.env,
          WALLET_PASS_CERT: creds.cert,
          WALLET_PASS_KEY: Buffer.from(creds.key).toString("base64"),
        }),
      )
      .overrideProvider(PASS_PUSHER)
      .useValue(pusher),
  ));
});
beforeEach(async () => {
  await resetDatabase(prisma);
  f = await seedFixtures(prisma);
  pusher.sent.length = 0;
});
afterAll(() => app.close());
const http = () => request(app.getHttpServer());

async function setUp() {
  const offer = await http()
    .post("/admin/loyalty/offers")
    .set("authorization", ADMIN)
    .send({
      businessId: f.abuSalim.id,
      title: { he: "קפה", en: "Coffee" },
      reward: { he: "קפה חינם", en: "A free coffee" },
      goal: 3,
      cooldownMinutes: 180,
    });
  expect(offer.status).toBe(201);
  const card = await http().post("/loyalty/cards").send({});
  const invite = await http()
    .post(`/admin/loyalty/businesses/${f.abuSalim.id}/invite`)
    .set("authorization", ADMIN)
    .send({});
  await http()
    .post("/loyalty/staff/join")
    .set("authorization", BARISTA)
    .send({ token: invite.body.token });
  return {
    offerId: offer.body.id as string,
    code: card.body.code as string,
    secret: card.body.secret as string,
  };
}

const download = (secret: string) =>
  http().get("/loyalty/cards/me/pass").set("x-darb-card", secret).buffer(true).parse(binary);

it("hands the card's owner a signed pass, in three languages", async () => {
  const { code, secret } = await setUp();
  const res = await download(secret);
  expect(res.status).toBe(200);
  expect(res.headers["content-type"]).toBe("application/vnd.apple.pkpass");
  const files = unzip(res.body as Buffer);
  for (const name of [
    "pass.json",
    "manifest.json",
    "signature",
    "icon.png",
    "icon@3x.png",
    "logo@2x.png",
    "strip@3x.png",
    "he.lproj/pass.strings",
    "ar.lproj/pass.strings",
    "en.lproj/pass.strings",
  ])
    expect(files.has(name), name).toBe(true);

  // the manifest names every other file by its SHA-1
  const manifest = JSON.parse(files.get("manifest.json")!.toString("utf8")) as Record<
    string,
    string
  >;
  for (const [name, data] of files) {
    if (name === "manifest.json" || name === "signature") continue;
    expect(manifest[name], name).toBe(createHash("sha1").update(data).digest("hex"));
  }

  const pass = JSON.parse(files.get("pass.json")!.toString("utf8"));
  expect(pass).toMatchObject({
    passTypeIdentifier: TYPE,
    serialNumber: code,
    webServiceURL: "https://api.darb.co.il/wallet",
    sharingProhibited: true,
  });
  expect(pass.authenticationToken.length).toBeGreaterThanOrEqual(16);
  expect(pass.barcodes[0].message).toBe(`https://darb.co.il/helpers/stamp/${code}`);
  expect(pass.storeCard.headerFields[0].value).toBe("0/3");

  const he = files.get("he.lproj/pass.strings")!;
  expect([...he.subarray(0, 2)]).toEqual([0xff, 0xfe]);
  expect(he.subarray(2).toString("utf16le")).toContain('"f.reward" = "קפה חינם";');
  expect(files.get("en.lproj/pass.strings")!.subarray(2).toString("utf16le")).toContain(
    '"f.more" = "3 more stamps";',
  );

  // the signature is a detached PKCS #7 of the manifest, made with the pass certificate
  const dir = mkdtempSync(join(tmpdir(), "pass-"));
  writeFileSync(join(dir, "manifest.json"), files.get("manifest.json")!);
  writeFileSync(join(dir, "signature"), files.get("signature")!);
  writeFileSync(join(dir, "cert.pem"), creds.cert);
  execFileSync(
    "openssl",
    [
      "smime",
      "-verify",
      "-binary",
      "-inform",
      "DER",
      "-in",
      join(dir, "signature"),
      "-content",
      join(dir, "manifest.json"),
      "-CAfile",
      join(dir, "cert.pem"),
      "-purpose",
      "any",
      "-out",
      "/dev/null",
    ],
    { stdio: "pipe" },
  );

  expect(
    (await http().get("/loyalty/cards/me/pass").set("x-darb-card", "x".repeat(32))).status,
  ).toBe(404);
});

it("serves Wallet: registers the phone, wakes it on a stamp, hands it the newer pass", async () => {
  const { code, offerId, secret } = await setUp();
  const pass = JSON.parse(
    unzip((await download(secret)).body as Buffer)
      .get("pass.json")!
      .toString(),
  );
  const auth = `ApplePass ${pass.authenticationToken}`;
  const reg = `/wallet/v1/devices/${DEVICE}/registrations/${TYPE}/${code}`;

  expect(
    (await http().post(reg).set("authorization", "ApplePass nope").send({ pushToken: PUSH }))
      .status,
  ).toBe(401);
  expect((await http().post(reg).set("authorization", auth).send({ pushToken: PUSH })).status).toBe(
    201,
  );
  expect((await http().post(reg).set("authorization", auth).send({ pushToken: PUSH })).status).toBe(
    200,
  );

  const first = await http().get(`/wallet/v1/devices/${DEVICE}/registrations/${TYPE}`);
  expect(first.status).toBe(200);
  expect(first.body.serialNumbers).toEqual([code]);
  const tag = first.body.lastUpdated as string;
  expect(
    (
      await http().get(
        `/wallet/v1/devices/${DEVICE}/registrations/${TYPE}?passesUpdatedSince=${tag}`,
      )
    ).status,
  ).toBe(204);

  // a stamp marks the card newer and wakes the phone
  await new Promise((r) => setTimeout(r, 5));
  const stamped = await http()
    .post("/loyalty/staff/stamp")
    .set("authorization", BARISTA)
    .send({ code, offerId });
  expect(stamped.status).toBe(200);
  await expect.poll(() => pusher.sent.flat()).toContain(PUSH);
  await expect
    .poll(
      async () =>
        (
          await http().get(
            `/wallet/v1/devices/${DEVICE}/registrations/${TYPE}?passesUpdatedSince=${tag}`,
          )
        ).body.serialNumbers,
    )
    .toEqual([code]);

  const latest = await http()
    .get(`/wallet/v1/passes/${TYPE}/${code}`)
    .set("authorization", auth)
    .buffer(true)
    .parse(binary);
  expect(latest.status).toBe(200);
  const now = JSON.parse(
    unzip(latest.body as Buffer)
      .get("pass.json")!
      .toString(),
  );
  expect(now.storeCard.headerFields[0].value).toBe("1/3");
  expect(
    (
      await http()
        .get(`/wallet/v1/passes/${TYPE}/${code}`)
        .set("authorization", auth)
        .set("if-modified-since", latest.headers["last-modified"]!)
    ).status,
  ).toBe(304);
  expect((await http().get(`/wallet/v1/passes/${TYPE}/${code}`)).status).toBe(401);

  expect((await http().delete(reg).set("authorization", auth)).status).toBe(200);
  expect((await http().get(`/wallet/v1/devices/${DEVICE}/registrations/${TYPE}`)).status).toBe(204);
});

it("wakes every phone holding a card when an offer changes", async () => {
  const { code, offerId, secret } = await setUp();
  const pass = JSON.parse(
    unzip((await download(secret)).body as Buffer)
      .get("pass.json")!
      .toString(),
  );
  await http()
    .post(`/wallet/v1/devices/${DEVICE}/registrations/${TYPE}/${code}`)
    .set("authorization", `ApplePass ${pass.authenticationToken}`)
    .send({ pushToken: PUSH });
  pusher.sent.length = 0;
  const paused = await http()
    .patch(`/admin/loyalty/offers/${offerId}`)
    .set("authorization", ADMIN)
    .send({ active: false });
  expect(paused.status).toBe(200);
  await expect.poll(() => pusher.sent.flat()).toContain(PUSH);
});
