import { notFound, redirect } from "next/navigation";
import { CardCodeSchema } from "@darb/contracts";
import { pickText } from "@darb/core";
import { helperSession } from "@/helpers/api";
import { ht, type HelperKey } from "@/helpers/copy";
import { HelperShell } from "@/helpers/HelperShell";
import { helperHref } from "@/helpers/routes";
import { staffApi } from "@/loyalty/api";
import { isLocale } from "@/lib/locale";
import styles from "@/helpers/helpers.module.css";

const JOINED: Record<string, HelperKey> = {
  "1": "joinedOk",
  expired: "joinedExpired",
  invalid: "joinedInvalid",
};

/** The counter's start: the offers this person stamps for, and a code to type when the camera is not at hand. */
export default async function StampHome({
  params,
  searchParams,
}: {
  params: Promise<{ locale: string }>;
  searchParams: Promise<{ code?: string; joined?: string }>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const { code, joined } = await searchParams;
  if (code) {
    const parsed = CardCodeSchema.safeParse(code.replace(/[\s-]/g, ""));
    if (parsed.success) redirect(helperHref(locale, `/stamp/${parsed.data}`));
  }
  const session = await helperSession();
  if (session.status === "signed-out")
    redirect(
      `${helperHref(locale, "/sign-in")}?next=${encodeURIComponent(helperHref(locale, "/stamp"))}`,
    );
  const offers =
    session.status === "ok"
      ? await (await staffApi()).offers().then((r) => (r.status === 200 ? r.body : []))
      : [];
  const note = joined ? JOINED[joined] : undefined;
  return (
    <HelperShell locale={locale}>
      <h1 className={styles.title}>{ht(locale, "stampTitle")}</h1>
      {note ? (
        <p className={styles.lead} role="status">
          {ht(locale, note)}
        </p>
      ) : null}
      <p className={styles.lead}>{ht(locale, "stampLead")}</p>
      <form action={helperHref(locale, "/stamp")} method="get" className={styles.formCard}>
        <label>
          <span className={styles.muted}>{ht(locale, "stampCode")}</span>
          <input
            name="code"
            autoComplete="off"
            autoCapitalize="characters"
            inputMode="text"
            maxLength={14}
            required
          />
        </label>
        <button type="submit" className={`${styles.primary} ${styles.wide}`}>
          {ht(locale, "stampOpen")}
        </button>
      </form>
      {offers.length > 0 ? (
        <section aria-labelledby="stamp-offers">
          <h2 id="stamp-offers" className={styles.screenTitle}>
            {ht(locale, "stampYours")}
          </h2>
          <ul className={styles.list}>
            {offers.map((o) => (
              <li key={o.id} className={styles.item}>
                <span className={styles.itemName}>{pickText(o.business.name, locale)}</span>
                <span className={styles.muted}>
                  {pickText(o.title, locale)} · {pickText(o.reward, locale)} ({o.goal})
                </span>
              </li>
            ))}
          </ul>
        </section>
      ) : (
        <p className={styles.muted}>{ht(locale, "stampNotStaff")}</p>
      )}
    </HelperShell>
  );
}
