import type { MetadataRoute } from "next";
import { headers } from "next/headers";
import { indexable, siteUrl } from "@/lib/site";

/**
 * Crawlers that collect pages to train AI models. They are kept out; the assistants' search
 * crawlers (OAI-SearchBot, PerplexityBot and the like) still read the city, so Darb's businesses
 * can come up in their answers.
 */
export const AI_TRAINING_BOTS = [
  "GPTBot",
  "ClaudeBot",
  "anthropic-ai",
  "CCBot",
  "Google-Extended",
  "Applebot-Extended",
  "Bytespider",
  "meta-externalagent",
];

/** Read at request time, so a preview never serves the production rules a build baked in. */
export const dynamic = "force-dynamic";

/** Production opens the city to crawlers; every other deployment is closed (Task 22). */
export default async function robots(): Promise<MetadataRoute.Robots> {
  if (!indexable(process.env, (await headers()).get("host")))
    return { rules: [{ userAgent: "*", disallow: "/" }] };
  const site = siteUrl();
  return {
    rules: [
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
          // Located per visitor and noindex: nothing there for a crawler.
          "/near",
          "/ar/near",
          "/en/near",
        ],
      },
      { userAgent: AI_TRAINING_BOTS, disallow: "/" },
    ],
    // The index (app/sitemap-index.xml) lists every sitemap that has something in it.
    sitemap: `${site}/sitemap-index.xml`,
  };
}
