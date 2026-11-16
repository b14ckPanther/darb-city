// @vitest-environment node
import { afterEach, expect, it, vi } from "vitest";
import { GET, dynamic } from "./route";

// 2,501 businesses: two business slices per language besides its page sitemap.
vi.mock("@/lib/api", () => ({ getSitemapBusinesses: async () => Array.from({ length: 2501 }) }));
afterEach(() => vi.unstubAllEnvs());

it("lists each language's page sitemap and the business slices that hold businesses", async () => {
  vi.stubEnv("SITE_URL", "https://darb.co.il");
  const res = await GET();
  expect(res.headers.get("content-type")).toContain("application/xml");
  const body = await res.text();
  expect(body).toContain("<sitemapindex");
  const locs = [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
  expect(locs).toEqual(
    [0, 1, 2, 100, 101, 102, 200, 201, 202].map((i) => `https://darb.co.il/sitemap/${i}.xml`),
  );
});

it("renders on request, so the build never needs the API", () => {
  expect(dynamic).toBe("force-dynamic");
});
