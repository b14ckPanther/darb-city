// @vitest-environment node
import { afterEach, expect, it, vi } from "vitest";
import robots, { AI_TRAINING_BOTS, dynamic } from "./robots";

let host = "darb.co.il";
vi.mock("next/headers", () => ({ headers: async () => new Headers({ host }) }));

afterEach(() => {
  vi.unstubAllEnvs();
  host = "darb.co.il";
});

it("blocks everything off production", async () => {
  vi.stubEnv("VERCEL_ENV", "preview");
  vi.stubEnv("VERCEL_URL", "x.vercel.app");
  expect((await robots()).rules).toEqual([{ userAgent: "*", disallow: "/" }]);
});

it("blocks production's *.vercel.app host", async () => {
  vi.stubEnv("VERCEL_ENV", "production");
  vi.stubEnv("SITE_URL", "https://darb.co.il");
  host = "darb-city.vercel.app";
  expect((await robots()).rules).toEqual([{ userAgent: "*", disallow: "/" }]);
});

it("opens production except admin, helpers, api, search and near, and points to the index", async () => {
  vi.stubEnv("VERCEL_ENV", "production");
  vi.stubEnv("SITE_URL", "https://darb.co.il");
  const r = await robots();
  expect(r.rules).toEqual([
    {
      userAgent: "*",
      allow: "/",
      disallow: [
        "/admin",
        "/ar/admin",
        "/en/admin",
        "/helpers",
        "/ar/helpers",
        "/en/helpers",
        "/api/",
        "/search",
        "/ar/search",
        "/en/search",
        "/near",
        "/ar/near",
        "/en/near",
      ],
    },
    { userAgent: AI_TRAINING_BOTS, disallow: "/" },
  ]);
  expect(r.sitemap).toBe("https://darb.co.il/sitemap-index.xml");
});

it("keeps AI training crawlers out but lets search engines and AI search crawlers in", () => {
  expect(AI_TRAINING_BOTS).toContain("GPTBot");
  expect(AI_TRAINING_BOTS).toContain("Google-Extended");
  for (const bot of ["Googlebot", "Bingbot", "OAI-SearchBot", "PerplexityBot"])
    expect(AI_TRAINING_BOTS).not.toContain(bot);
});

it("reads the deployment at request time, not at build", () => {
  expect(dynamic).toBe("force-dynamic");
});
