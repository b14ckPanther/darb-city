import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";
import { Controller, Get, Headers, Res } from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service.js";
import { buildAppData } from "./app-data.builder.js";

/** What the HTTP layer needs from the response; Express's response has all of it. */
interface Reply {
  status(code: number): Reply;
  setHeader(name: string, value: string): void;
  end(body?: Buffer): void;
}

interface Built {
  at: number;
  etag: string;
  json: Buffer;
  gzip: Buffer;
}

/** How long one build is served before the database is read again: an admin edit reaches phones within this. */
const FRESH_MS = 60_000;

/**
 * GET /app/data: every published business, with the sectors, kinds and places, for the iPhone app. The app keeps
 * the last copy and asks again with its ETag, so an unchanged map costs a 304 and nothing more.
 */
@Controller()
export class AppDataController {
  private built: Built | null = null;
  private building: Promise<Built> | null = null;

  constructor(private readonly prisma: PrismaService) {}

  @Get("app/data")
  async data(
    @Headers("if-none-match") ifNoneMatch: string | undefined,
    @Headers("accept-encoding") acceptEncoding: string | undefined,
    @Res() res: Reply,
  ): Promise<void> {
    const b = await this.current();
    res.setHeader("ETag", b.etag);
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Vary", "Accept-Encoding");
    if (ifNoneMatch && ifNoneMatch.split(",").some((t) => t.trim() === b.etag)) {
      res.status(304).end();
      return;
    }
    res.setHeader("Content-Type", "application/json; charset=utf-8");
    if (/\bgzip\b/.test(acceptEncoding ?? "")) {
      res.setHeader("Content-Encoding", "gzip");
      res.status(200).end(b.gzip);
    } else {
      res.status(200).end(b.json);
    }
  }

  private async current(): Promise<Built> {
    if (this.built && Date.now() - this.built.at < FRESH_MS) return this.built;
    // one read of the database at a time, shared by every request that arrives meanwhile
    this.building ??= this.build().finally(() => {
      this.building = null;
    });
    // a stale copy is served while a fresh one is built, rather than making the phone wait
    if (this.built) return this.built;
    return this.building;
  }

  private async build(): Promise<Built> {
    const [sectors, kinds, places, businesses] = await Promise.all([
      this.prisma.sector.findMany({ select: { slug: true, name: true, accent: true }, orderBy: [{ order: "asc" }, { slug: "asc" }] }),
      this.prisma.kind.findMany({
        where: { status: "active" },
        select: { slug: true, name: true, synonyms: true, sector: { select: { slug: true } } },
        orderBy: [{ order: "asc" }, { slug: "asc" }],
      }),
      this.prisma.place.findMany({ select: { slug: true, name: true, aliases: true, lat: true, lng: true, type: true, status: true } }),
      this.prisma.business.findMany({
        where: { status: "published", tier: { not: "example" }, primaryKind: { is: { status: "active" } } },
        select: {
          slug: true, name: true, tagline: true, lat: true, lng: true, hours: true, address: true,
          phone: true, whatsapp: true, website: true, attributes: true, links: true,
          place: { select: { slug: true } },
          primaryKind: { select: { slug: true } },
        },
      }),
    ]);
    const payload = buildAppData({
      sectors,
      kinds: kinds.map((k) => ({ slug: k.slug, sector: k.sector.slug, name: k.name, synonyms: k.synonyms })),
      places,
      businesses: businesses.map((b) => ({ ...b, place: b.place.slug, kind: b.primaryKind.slug })),
      generated: new Date(),
    });
    // the ETag is the content's own, so it changes only when the map does
    const { generated: _date, ...content } = payload;
    const etag = `"${createHash("sha256").update(JSON.stringify(content)).digest("base64url").slice(0, 27)}"`;
    const json = Buffer.from(JSON.stringify(payload), "utf8");
    const built = { at: Date.now(), etag, json, gzip: gzipSync(json, { level: 6 }) };
    this.built = built;
    return built;
  }
}
