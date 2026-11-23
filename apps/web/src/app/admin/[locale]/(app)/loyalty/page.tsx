import { notFound } from "next/navigation";
import type { AdminBusinessRowDto, LoyaltyOfferDto } from "@darb/contracts";
import { pickText } from "@darb/core";
import { adminApi } from "@/admin/api";
import { at, type AdminKey } from "@/admin/copy";
import { createOffer, inviteStaff, toggleOffer } from "@/admin/loyalty-actions";
import { loyaltyAdminApi } from "@/admin/loyalty-api";
import { one, type SearchParams } from "@/admin/params";
import { adminHref } from "@/admin/routes";
import { Empty, PageHead } from "@/admin/ui";
import { helperHref } from "@/helpers/routes";
import { isLocale } from "@/lib/locale";
import styles from "@/admin/admin.module.css";

const SITE = (process.env.SITE_URL ?? "https://darb.co.il").replace(/\/+$/, "");

/**
 * Loyalty: the partners' offers, and the links that make someone a partner's staff. Find a business, give it an
 * offer, then send its staff the invite link; they stamp cards from the helper app.
 */
export default async function LoyaltyPage({
  params,
  searchParams,
}: {
  params: Promise<{ locale: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const sp = await searchParams;
  const q = (one(sp.q) ?? "").trim();
  const invite = one(sp.invite);
  const done = one(sp.done);
  const t = (key: AdminKey, vars?: Record<string, string | number>) => at(locale, key, vars);
  const res = await (await loyaltyAdminApi()).offers();
  const offers: LoyaltyOfferDto[] = res.status === 200 ? res.body : [];
  const found: AdminBusinessRowDto[] = q
    ? await (
        await adminApi()
      ).businesses
        .list({ query: { q, limit: 8 } })
        .then((r) => (r.status === 200 ? (r.body as { items: AdminBusinessRowDto[] }).items : []))
    : [];
  const base = adminHref(locale, "/loyalty");
  return (
    <div className={styles.narrow}>
      <PageHead title={t("navLoyalty")} sub={t("loyaltyIntro")} />
      {done ? (
        <p className={styles.notice} role="status">
          <span>{t(done === "created" ? "loyaltyCreated" : "loyaltyFailed")}</span>
        </p>
      ) : null}
      {invite ? (
        <section className={styles.panel} aria-labelledby="invite">
          <h2 id="invite" className={styles.h2}>
            {t("loyaltyInviteTitle")}
          </h2>
          <p>{t("loyaltyInviteLead")}</p>
          <input
            className={styles.input}
            readOnly
            value={`${SITE}${helperHref(locale, `/stamp/join/${invite}`)}`}
            aria-label={t("loyaltyInviteTitle")}
          />
        </section>
      ) : null}

      <section className={styles.panel} aria-labelledby="offers">
        <h2 id="offers" className={styles.h2}>
          {t("loyaltyOffers")}
        </h2>
        {offers.length === 0 ? (
          <Empty icon="tag" title={t("loyaltyNone")} />
        ) : (
          <table className={styles.table}>
            <tbody>
              {offers.map((o) => (
                <tr key={o.id}>
                  <td>
                    <strong>{pickText(o.business.name, locale)}</strong>
                    <br />
                    {pickText(o.title, locale)} · {pickText(o.reward, locale)} ·{" "}
                    {t("loyaltyGoal", { goal: o.goal })}
                  </td>
                  <td>{t(o.active ? "statusLive" : "loyaltyPaused")}</td>
                  <td className={styles.end}>
                    <form action={toggleOffer} style={{ display: "inline" }}>
                      <input type="hidden" name="locale" value={locale} />
                      <input type="hidden" name="id" value={o.id} />
                      <input type="hidden" name="active" value={o.active ? "0" : "1"} />
                      <button type="submit" className={`${styles.ghost} ${styles.sm}`}>
                        {t(o.active ? "loyaltyPause" : "loyaltyResume")}
                      </button>
                    </form>{" "}
                    <form action={inviteStaff} style={{ display: "inline" }}>
                      <input type="hidden" name="locale" value={locale} />
                      <input type="hidden" name="businessId" value={o.business.id} />
                      <button type="submit" className={`${styles.ghost} ${styles.sm}`}>
                        {t("loyaltyInvite")}
                      </button>
                    </form>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section className={styles.panel} aria-labelledby="new-offer">
        <h2 id="new-offer" className={styles.h2}>
          {t("loyaltyNew")}
        </h2>
        <form action={base} method="get" role="search">
          <input
            className={styles.input}
            type="search"
            name="q"
            defaultValue={q}
            placeholder={t("loyaltyFind")}
            aria-label={t("loyaltyFind")}
          />
        </form>
        {found.map((b) => (
          <form key={b.id} action={createOffer} className={styles.panel}>
            <input type="hidden" name="locale" value={locale} />
            <input type="hidden" name="businessId" value={b.id} />
            <strong>
              {pickText(b.name, locale)} ·{" "}
              {b.placeName ? pickText(b.placeName, locale) : b.placeSlug}
            </strong>
            {(["title", "reward"] as const).map((field) => (
              <fieldset key={field} style={{ border: 0, padding: 0, display: "grid", gap: 6 }}>
                <legend>{t(field === "title" ? "loyaltyTitle" : "loyaltyReward")}</legend>
                {(["He", "Ar", "En"] as const).map((l) => (
                  <input
                    key={l}
                    className={styles.input}
                    name={`${field}${l}`}
                    placeholder={l === "He" ? "עברית" : l === "Ar" ? "العربية" : "English"}
                    dir={l === "En" ? "ltr" : "rtl"}
                    required={l === "He"}
                  />
                ))}
              </fieldset>
            ))}
            <label className={styles.field}>
              <span>{t("loyaltyGoalLabel")}</span>
              <input name="goal" type="number" min={2} max={20} defaultValue={5} required />
            </label>
            <label className={styles.field}>
              <span>{t("loyaltyCooldown")}</span>
              <input name="cooldown" type="number" min={0} max={1440} defaultValue={180} />
            </label>
            <button type="submit" className={styles.primary}>
              {t("loyaltyCreate")}
            </button>
          </form>
        ))}
      </section>
    </div>
  );
}
