import { notFound, redirect } from "next/navigation";
import { CardCodeSchema } from "@darb/contracts";
import { pickText } from "@darb/core";
import { helperSession } from "@/helpers/api";
import { ht, type HelperKey } from "@/helpers/copy";
import { HelperShell } from "@/helpers/HelperShell";
import { helperHref } from "@/helpers/routes";
import { scanCard } from "@/loyalty/actions";
import { staffApi } from "@/loyalty/api";
import { Dots } from "@/loyalty/Dots";
import { INTL_TAG, isLocale } from "@/lib/locale";
import styles from "@/helpers/helpers.module.css";

const DONE: Record<string, HelperKey> = {
  stamped: "doneStamped",
  redeemed: "doneRedeemed",
  too_soon: "doneTooSoon",
  reward_ready: "doneRewardReady",
  not_ready: "doneNotReady",
  failed: "doneFailed",
};

/**
 * A scanned card at the counter: the QR on a Darb card opens this page. For each offer this person stamps for,
 * the stamps so far and one big button: stamp, or hand over the reward when it is ready.
 */
export default async function StampCard({
  params,
  searchParams,
}: {
  params: Promise<{ locale: string; code: string }>;
  searchParams: Promise<{ done?: string; offer?: string }>;
}) {
  const { locale, code: raw } = await params;
  if (!isLocale(locale)) notFound();
  const parsed = CardCodeSchema.safeParse(raw);
  if (!parsed.success) notFound();
  const code = parsed.data;
  const here = helperHref(locale, `/stamp/${code}`);
  const session = await helperSession();
  if (session.status === "signed-out")
    redirect(`${helperHref(locale, "/sign-in")}?next=${encodeURIComponent(here)}`);
  const { done, offer: doneOffer } = await searchParams;
  const res = session.status === "ok" ? await (await staffApi()).card({ params: { code } }) : null;
  const time = new Intl.DateTimeFormat(INTL_TAG[locale], { hour: "2-digit", minute: "2-digit" });
  return (
    <HelperShell locale={locale}>
      <h1 className={styles.title}>{ht(locale, "stampCard", { code })}</h1>
      {!res || res.status === 404 ? (
        <p className={styles.lead}>{ht(locale, "stampUnknown")}</p>
      ) : res.status !== 200 ? (
        <p className={styles.lead}>{ht(locale, "stampNoOffers")}</p>
      ) : (
        <ul className={styles.list}>
          {res.body.standings.map((s) => {
            const note = s.offer.id === doneOffer && done ? DONE[done] : undefined;
            return (
              <li key={s.offer.id} className={styles.item}>
                <span className={styles.itemName}>{pickText(s.offer.business.name, locale)}</span>
                <span className={styles.muted}>
                  {pickText(s.offer.title, locale)} · {pickText(s.offer.reward, locale)}
                </span>
                <span>
                  <Dots stamps={s.stamps} goal={s.offer.goal} />{" "}
                  <strong>
                    {ht(locale, "stampCount", { stamps: s.stamps, goal: s.offer.goal })}
                  </strong>
                </span>
                {note ? (
                  <p className={styles.lead} role="status">
                    {ht(locale, note)}
                  </p>
                ) : null}
                {s.ready ? <strong>{ht(locale, "stampReady")}</strong> : null}
                {!s.ready && s.nextStampAt ? (
                  <span className={styles.muted}>
                    {ht(locale, "stampNext", { time: time.format(new Date(s.nextStampAt)) })}
                  </span>
                ) : null}
                <form action={scanCard}>
                  <input type="hidden" name="locale" value={locale} />
                  <input type="hidden" name="code" value={code} />
                  <input type="hidden" name="offerId" value={s.offer.id} />
                  <input type="hidden" name="action" value={s.ready ? "redeem" : "stamp"} />
                  <button
                    type="submit"
                    className={`${styles.primary} ${styles.wide}`}
                    disabled={!s.ready && s.nextStampAt !== null}
                  >
                    {ht(locale, s.ready ? "stampRedeem" : "stampButton")}
                  </button>
                </form>
                {s.rewards > 0 ? (
                  <span className={styles.muted}>
                    {ht(locale, "stampRewards", { count: s.rewards })}
                  </span>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}
    </HelperShell>
  );
}
