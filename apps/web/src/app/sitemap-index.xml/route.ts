import { getSitemapBusinesses } from "@/lib/api";
import { BUSINESSES_PER_SITEMAP, sitemapIds } from "@/lib/sitemap-ids";
import { siteUrl } from "@/lib/site";

/** Read at request time, like the sitemaps it lists: the build never calls the API. */
export const dynamic = "force-dynamic";

/**
 * The sitemap index: one URL for robots.txt and Search Console. It lists each language's page
 * sitemap and only the business slices that hold businesses (an unreachable API lists the page
 * sitemaps only).
 */
export async function GET(): Promise<Response> {
  const count = await getSitemapBusinesses()
    .then((b) => b.length)
    .catch(() => 0);
  const site = siteUrl();
  const entries = sitemapIds(Math.ceil(count / BUSINESSES_PER_SITEMAP))
    .map((id) => `  <sitemap><loc>${site}/sitemap/${id}.xml</loc></sitemap>`)
    .join("\n");
  return new Response(
    `<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${entries}\n</sitemapindex>\n`,
    { headers: { "content-type": "application/xml; charset=utf-8" } },
  );
}
