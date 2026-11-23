import type { INestApplication } from "@nestjs/common";
import request from "supertest";
import { afterAll, beforeAll, expect, it } from "vitest";
import { createTestApp } from "../../test/app.js";
import { resetDatabase } from "../../test/db.js";
import { seedFixtures } from "../../test/fixtures.js";
import { businessId } from "./app-data.builder.js";

let app: INestApplication;
beforeAll(async () => {
  const created = await createTestApp();
  app = created.app;
  await resetDatabase(created.prisma);
  const f = await seedFixtures(created.prisma);
  await created.prisma.business.update({
    where: { id: f.abuSalim.id },
    data: { tier: "darb", status: "published" },
  });
  // real but not shown: a draft, and one whose kind is hidden
  await created.prisma.business.update({
    where: { id: f.draft.id },
    data: { tier: "darb", status: "draft" },
  });
  await created.prisma.business.update({
    where: { id: f.littleCuts.id },
    data: { tier: "basic", status: "published" },
  });
  await created.prisma.kind.update({ where: { id: f.kidsCuts.id }, data: { status: "hidden" } });
});
afterAll(() => app.close());

it("sends every published, real business in the app's columns", async () => {
  const res = await request(app.getHttpServer()).get("/app/data");
  expect(res.status).toBe(200);
  expect(res.body.version).toBe(2);
  expect(res.body.businesses.id).toContain(businessId("sakhnin", "abu-salim", new Set()));
  expect(res.body.businesses.id).not.toContain(businessId("sakhnin", "draft-barber", new Set()));
  expect(res.body.businesses.id).not.toContain(businessId("sakhnin", "little-cuts", new Set()));
  const n = res.body.businesses.id.length;
  for (const col of ["kind", "place", "lat", "lng", "hours", "demo", "tag"])
    expect(res.body.businesses[col]).toHaveLength(n);
  expect(res.headers.etag).toMatch(/^".+"$/);
});

it("answers an unchanged map with 304", async () => {
  const first = await request(app.getHttpServer()).get("/app/data");
  const again = await request(app.getHttpServer())
    .get("/app/data")
    .set("If-None-Match", first.headers.etag!);
  expect(again.status).toBe(304);
});
