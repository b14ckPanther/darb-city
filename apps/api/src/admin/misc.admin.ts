import { Controller, Injectable, Req, UseGuards } from "@nestjs/common";
import {
  contract,
  COVERAGE_NEEDS,
  type AdminEntity,
  type AuditRowDto,
  type CoverageRowDto,
} from "@darb/contracts";
import { TsRestHandler, tsRestHandler } from "@ts-rest/nest";
import { AdminGuard, type AdminActor, type AdminRequest } from "../auth/admin.guard.js";
import { PrismaService } from "../prisma/prisma.service.js";
import { ReportRepository } from "../search/report.repository.js";
import { AdminWriter } from "./admin-writer.js";
import { conflict, notFound } from "./outcome.js";
import { OverviewAdmin } from "./overview.admin.js";
import { seedSource } from "./seed-source.js";
import { webTags } from "./tags.js";

@Injectable()
export class MiscAdmin {
  constructor(
    private readonly prisma: PrismaService,
    private readonly writer: AdminWriter,
  ) {}

  /**
   * Every city, town and village, the biggest first, with its published real businesses and how many answer each
   * of the nine everyday needs: where to send helpers next.
   */
  async coverage(): Promise<CoverageRowDto[]> {
    const rows = await this.prisma.$queryRaw<
      {
        id: string;
        slug: string;
        name: Record<string, string>;
        type: "city" | "town" | "village";
        status: "live" | "soon";
        population: number | null;
        kind: string | null;
        n: bigint;
      }[]
    >`
      SELECT p.id, p.slug, p.name, p.type::text AS type, p.status::text AS status, p.population,
             k.slug AS kind, count(b.id) AS n
      FROM "Place" p
      LEFT JOIN "Business" b ON b."placeId" = p.id AND b.status = 'published' AND b.tier <> 'example'
      LEFT JOIN "Kind" k ON k.id = b."primaryKindId" AND k.status = 'active'
      WHERE p.type IN ('city', 'town', 'village')
      GROUP BY p.id, k.slug`;
    const needOf = new Map<string, string>(
      COVERAGE_NEEDS.flatMap((need) => need.kinds.map((k) => [k, need.key] as const)),
    );
    const out = new Map<string, CoverageRowDto>();
    for (const r of rows) {
      const row = out.get(r.id) ?? {
        id: r.id,
        slug: r.slug,
        name: r.name,
        type: r.type,
        status: r.status,
        population: r.population,
        businesses: 0,
        needs: Object.fromEntries(COVERAGE_NEEDS.map((need) => [need.key, 0])),
      };
      if (r.kind) {
        const n = Number(r.n);
        row.businesses += n;
        const need = needOf.get(r.kind);
        if (need) row.needs[need] = (row.needs[need] ?? 0) + n;
      }
      out.set(r.id, row);
    }
    return [...out.values()].sort(
      (a, b) => (b.population ?? -1) - (a.population ?? -1) || a.slug.localeCompare(b.slug),
    );
  }

  async audit(entityType: AdminEntity, entityId: string): Promise<AuditRowDto[]> {
    const rows = await this.prisma.auditLog.findMany({
      where: { entityType, entityId },
      orderBy: [{ at: "desc" }, { id: "desc" }],
      take: 50,
      include: { actor: { select: { clerkUserId: true } } },
    });
    return rows.map((r) => ({
      id: r.id,
      at: r.at.toISOString(),
      actor: r.actor.clerkUserId,
      action: r.action,
      // The where above keeps to the asked entity type, never a helper's.
      entityType: r.entityType as AdminEntity,
      entityId: r.entityId,
      fields: r.fields,
    }));
  }

  /** The web cache tags of one entity, or null when it does not exist. */
  private async tagsFor(entity: AdminEntity, id: string): Promise<string[] | null> {
    if (entity === "place") {
      const p = await this.prisma.place.findUnique({ where: { id } });
      return p ? webTags.place(p.slug) : null;
    }
    if (entity === "sector")
      return (await this.prisma.sector.findUnique({ where: { id } })) ? webTags.sector() : null;
    if (entity === "kind")
      return (await this.prisma.kind.findUnique({ where: { id } })) ? webTags.kind() : null;
    if (entity === "plan")
      return (await this.prisma.plan.findUnique({ where: { id } })) ? webTags.plan() : null;
    if (entity === "text")
      return (await this.prisma.siteText.findUnique({ where: { id } })) ? webTags.text() : null;
    const b = await this.prisma.business.findUnique({
      where: { id },
      include: { place: { select: { slug: true } } },
    });
    return b ? webTags.business(b.place.slug, b.slug) : null;
  }

  /**
   * Retry after a takedown whose web revalidation failed. A deleted business has no row left, so
   * its retry expires "businesses", which covers every list, count and detail page.
   */
  async revalidate(entity: AdminEntity, id: string) {
    const tags =
      (await this.tagsFor(entity, id)) ?? (entity === "business" ? ["businesses"] : null);
    if (!tags) return notFound(entity);
    return { status: 200 as const, body: { revalidated: await this.writer.retryTakedown(tags) } };
  }

  /** Whether the row exists and has a seed counterpart; null when it does not exist. */
  private async seeded(entity: AdminEntity, id: string): Promise<boolean | null> {
    if (entity === "place") {
      const p = await this.prisma.place.findUnique({ where: { id } });
      return p ? seedSource.place(p) : null;
    }
    if (entity === "sector") {
      const s = await this.prisma.sector.findUnique({ where: { id } });
      return s ? seedSource.sector(s.slug) : null;
    }
    if (entity === "kind") {
      const k = await this.prisma.kind.findUnique({ where: { id } });
      return k ? seedSource.kind(k.slug) : null;
    }
    if (entity === "plan") {
      const p = await this.prisma.plan.findUnique({ where: { id } });
      return p ? seedSource.plan(p.slug) : null;
    }
    if (entity === "text") {
      const t = await this.prisma.siteText.findUnique({ where: { id } });
      return t ? seedSource.text(t.key) : null;
    }
    const b = await this.prisma.business.findUnique({
      where: { id },
      include: { place: { select: { slug: true } } },
    });
    return b ? seedSource.business(b.place.slug, b.slug) : null;
  }

  /** "Return to seed data": the next seed run overwrites this row again (Task 3). */
  async release(actor: AdminActor, entity: AdminEntity, id: string) {
    const tags = await this.tagsFor(entity, id);
    if (!tags) return notFound(entity);
    // An admin-created row has nothing to return to: releasing it would only let the next seed
    // run hide or suspend it (12-17 #10).
    if (!(await this.seeded(entity, id)))
      return conflict(
        "This was created in admin, so there is no seed data to return to",
        "no_seed_source",
      );
    await this.writer.write(actor, "release", entity, async (tx) => {
      const data = { editedAt: null };
      if (entity === "place") await tx.place.update({ where: { id }, data });
      else if (entity === "sector") await tx.sector.update({ where: { id }, data });
      else if (entity === "kind") await tx.kind.update({ where: { id }, data });
      else if (entity === "plan") await tx.plan.update({ where: { id }, data });
      else if (entity === "text") await tx.siteText.update({ where: { id }, data });
      else await tx.business.update({ where: { id }, data });
      return { row: null, entityId: id, fields: ["editedAt"], tags };
    });
    return { status: 200 as const, body: { released: true as const } };
  }
}

@Controller()
@UseGuards(AdminGuard)
export class AdminMiscController {
  constructor(
    private readonly misc: MiscAdmin,
    private readonly reports: ReportRepository,
    private readonly overview: OverviewAdmin,
  ) {}

  @TsRestHandler(contract.admin.misc)
  // Headers go through Express's req.res: @Res({ passthrough: true }) makes ts-rest handlers hang
  // in this codebase (see search.controller.ts).
  handler(@Req() req: AdminRequest & { res?: { setHeader(k: string, v: string): void } }) {
    const actor = req.admin!;
    return tsRestHandler(contract.admin.misc, {
      me: async () => ({
        status: 200,
        body: { clerkUserId: actor.clerkUserId, userId: actor.userId },
      }),
      audit: async ({ query }) => ({
        status: 200,
        body: await this.misc.audit(query.entityType, query.entityId),
      }),
      report: async ({ query }) => {
        // Raw visitor search terms (Plan 3 note): never cached anywhere.
        req.res?.setHeader("cache-control", "no-store");
        return {
          status: 200,
          body: await this.reports.report(query.days, query.limit, new Date()),
        };
      },
      release: async ({ params }) => this.misc.release(actor, params.entity, params.id),
      revalidate: async ({ params }) => this.misc.revalidate(params.entity, params.id),
      overview: async () => {
        req.res?.setHeader("cache-control", "no-store");
        return { status: 200, body: await this.overview.overview(actor) };
      },
      coverage: async () => {
        req.res?.setHeader("cache-control", "no-store");
        return { status: 200, body: await this.misc.coverage() };
      },
      search: async ({ query }) => {
        req.res?.setHeader("cache-control", "no-store");
        return { status: 200, body: await this.overview.search(query.q) };
      },
    });
  }
}
