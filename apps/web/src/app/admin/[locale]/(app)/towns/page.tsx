import Link from "next/link";
import { notFound } from "next/navigation";
import { COVERAGE_NEEDS, type CoverageRowDto } from "@darb/contracts";
import { pickText } from "@darb/core";
import { adminApi, okOr } from "@/admin/api";
import { at, type AdminKey } from "@/admin/copy";
import { PLACE_TYPE_KEY } from "@/admin/labels";
import { one, withParams, type SearchParams } from "@/admin/params";
import { adminHref } from "@/admin/routes";
import { Empty, numberFormat, PageHead, StatusTabs } from "@/admin/ui";
import { isLocale } from "@/lib/locale";
import styles from "@/admin/admin.module.css";
import board from "@/admin/coverage.module.css";

const NEED_KEY = {
  food: "needFood",
  sweets: "needSweets",
  coffee: "needCoffee",
  bakery: "needBakery",
  pharmacy: "needPharmacy",
  grocery: "needGrocery",
  fuel: "needFuel",
  garage: "needGarage",
  bank: "needBank",
} as const satisfies Record<string, AdminKey>;

const VIEWS = ["todo", "started", "covered", "all"] as const;
type View = (typeof VIEWS)[number];
const VIEW_KEY: Record<View, AdminKey> = {
  todo: "coverageTodo",
  started: "coverageStarted",
  covered: "coverageCovered",
  all: "coverageAll",
};
const SHOWN = 120;

/** How many of the nine needs have at least one real, published place. */
const covered = (r: CoverageRowDto) => COVERAGE_NEEDS.filter((n) => (r.needs[n.key] ?? 0) > 0).length;

/** Town by town: which of the nine everyday needs already have a real place, the biggest towns first. */
export default async function CoveragePage({
  params,
  searchParams,
}: {
  params: Promise<{ locale: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const sp = await searchParams;
  const raw = one(sp.view);
  const view: View = VIEWS.find((v) => v === raw) ?? "todo";
  const q = (one(sp.q) ?? "").trim().toLowerCase();
  const rows = okOr<CoverageRowDto[]>(await (await adminApi()).misc.coverage(), locale);
  const t = (key: AdminKey, vars?: Record<string, string | number>) => at(locale, key, vars);
  const n = numberFormat(locale);
  const base = adminHref(locale, "/towns");
  const inView = (r: CoverageRowDto, v: View) => {
    const c = covered(r);
    return v === "all" || (v === "todo" ? c === 0 : v === "started" ? c > 0 && c < 9 : c === 9);
  };
  const counts = Object.fromEntries(VIEWS.map((v) => [v, rows.filter((r) => inView(r, v)).length]));
  const matches = rows
    .filter((r) => inView(r, view))
    .filter((r) => !q || [r.slug, ...Object.values(r.name)].some((s) => s.toLowerCase().includes(q)));
  const shown = matches.slice(0, SHOWN);
  const done = rows.filter((r) => covered(r) === 9).length;
  return (
    <div className={styles.page}>
      <PageHead
        title={t("navCoverage")}
        sub={t("coverageIntro", { done: n.format(done), total: n.format(rows.length) })}
      />
      <StatusTabs
        label={t("coverageView")}
        tabs={VIEWS.map((v) => ({
          href: withParams(base, { view: v === "todo" ? undefined : v, q: q || undefined }),
          label: t(VIEW_KEY[v]),
          current: view === v,
          count: counts[v],
        }))}
      />
      <form action={base} className={board.legend} role="search">
        {view !== "todo" ? <input type="hidden" name="view" value={view} /> : null}
        <input
          className={styles.input}
          type="search"
          name="q"
          defaultValue={q}
          placeholder={t("searchPlaces")}
          aria-label={t("searchPlaces")}
        />
      </form>
      <p className={board.legend} aria-hidden="true">
        {COVERAGE_NEEDS.map((need, i) => (
          <span key={need.key}>
            <b>{i + 1}</b>
            {t(NEED_KEY[need.key])}
          </span>
        ))}
      </p>
      {shown.length === 0 ? (
        <div className={styles.tableWrap}>
          <Empty icon="pin" title={t("noMatches")} />
        </div>
      ) : (
        <ol className={board.board} role="list">
          {shown.map((r) => {
            const c = covered(r);
            const name = pickText(r.name, locale) || r.slug;
            const missing = COVERAGE_NEEDS.filter((need) => !(r.needs[need.key] ?? 0))
              .map((need) => t(NEED_KEY[need.key]))
              .join(", ");
            return (
              <li key={r.id} className={board.row}>
                <div className={board.town}>
                  <Link href={adminHref(locale, `/places/${r.id}`)}>{name}</Link>
                  <span className={board.meta}>
                    {t(PLACE_TYPE_KEY[r.type])}
                    {r.population ? ` · ${t("coveragePeople", { count: n.format(r.population) })}` : ""}
                    {` · ${t("coverageBusinesses", { count: n.format(r.businesses) })}`}
                    {" · "}
                    <span className={board.score}>{t("coverageScore", { done: c })}</span>
                    {r.status === "live" ? ` · ${t("statusLive")}` : ""}
                  </span>
                  {c > 0 && c < 9 ? (
                    <span className={board.meta}>{t("coverageMissing", { needs: missing })}</span>
                  ) : null}
                </div>
                <div className={board.needs}>
                  {COVERAGE_NEEDS.map((need, i) => {
                    const count = r.needs[need.key] ?? 0;
                    return (
                      <span
                        key={need.key}
                        className={board.need}
                        data-covered={count > 0 ? "" : undefined}
                        title={`${t(NEED_KEY[need.key])}: ${n.format(count)}`}
                        aria-label={`${t(NEED_KEY[need.key])}: ${n.format(count)}`}
                      >
                        {count > 0 ? (count > 9 ? "9+" : count) : i + 1}
                      </span>
                    );
                  })}
                </div>
              </li>
            );
          })}
        </ol>
      )}
      {matches.length > SHOWN ? (
        <p className={board.meta}>
          {t("coverageMore", { shown: n.format(SHOWN), total: n.format(matches.length) })}
        </p>
      ) : null}
    </div>
  );
}
