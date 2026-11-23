import { notFound, redirect } from "next/navigation";
import { helperSession } from "@/helpers/api";
import { ht } from "@/helpers/copy";
import { HelperShell } from "@/helpers/HelperShell";
import { helperHref } from "@/helpers/routes";
import { joinStaff } from "@/loyalty/actions";
import { isLocale } from "@/lib/locale";
import styles from "@/helpers/helpers.module.css";

/** The invite link Darb sends a partner's staff: signed in, one button makes them staff of that business. */
export default async function JoinStaff({
  params,
}: {
  params: Promise<{ locale: string; token: string }>;
}) {
  const { locale, token } = await params;
  if (!isLocale(locale) || !/^[\w-]{20,100}$/.test(token)) notFound();
  const here = helperHref(locale, `/stamp/join/${token}`);
  const session = await helperSession();
  if (session.status === "signed-out")
    redirect(`${helperHref(locale, "/sign-in")}?next=${encodeURIComponent(here)}`);
  return (
    <HelperShell locale={locale}>
      <h1 className={styles.title}>{ht(locale, "joinTitle")}</h1>
      <p className={styles.lead}>{ht(locale, "joinLead")}</p>
      <form action={joinStaff}>
        <input type="hidden" name="locale" value={locale} />
        <input type="hidden" name="token" value={token} />
        <button type="submit" className={`${styles.primary} ${styles.wide}`}>
          {ht(locale, "joinButton")}
        </button>
      </form>
    </HelperShell>
  );
}
