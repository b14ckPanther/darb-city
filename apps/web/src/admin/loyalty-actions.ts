"use server";

import { redirect } from "next/navigation";
import { isLocale } from "@/lib/locale";
import { loyaltyAdminApi } from "./loyalty-api";
import { adminHref } from "./routes";

const localeOf = (fd: FormData) => {
  const l = String(fd.get("locale") ?? "");
  return isLocale(l) ? l : "he";
};
const text = (fd: FormData, name: string) => String(fd.get(name) ?? "").trim();

/** A new offer for a business: what earns a stamp, the reward, and how many stamps it takes. */
export async function createOffer(fd: FormData): Promise<void> {
  const locale = localeOf(fd);
  const tri = (prefix: string) => {
    const v = {
      he: text(fd, `${prefix}He`),
      ar: text(fd, `${prefix}Ar`),
      en: text(fd, `${prefix}En`),
    };
    return Object.fromEntries(Object.entries(v).filter(([, s]) => s)) as Record<string, string>;
  };
  const res = await (
    await loyaltyAdminApi()
  ).create({
    body: {
      businessId: text(fd, "businessId"),
      title: tri("title"),
      reward: tri("reward"),
      goal: Number(text(fd, "goal")) || 5,
      cooldownMinutes: Number(text(fd, "cooldown") || 180),
      active: true,
    },
  });
  redirect(`${adminHref(locale, "/loyalty")}?done=${res.status === 201 ? "created" : "failed"}`);
}

/** Pauses an offer, or runs it again. */
export async function toggleOffer(fd: FormData): Promise<void> {
  const locale = localeOf(fd);
  await (
    await loyaltyAdminApi()
  ).update({
    params: { id: text(fd, "id") },
    body: { active: text(fd, "active") === "1" },
  });
  redirect(adminHref(locale, "/loyalty"));
}

/** A new invite link for a business's staff, shown once on the page. */
export async function inviteStaff(fd: FormData): Promise<void> {
  const locale = localeOf(fd);
  const res = await (
    await loyaltyAdminApi()
  ).invite({ params: { id: text(fd, "businessId") }, body: {} });
  if (res.status !== 201) redirect(`${adminHref(locale, "/loyalty")}?done=failed`);
  redirect(
    `${adminHref(locale, "/loyalty")}?invite=${encodeURIComponent(res.body.token)}&for=${encodeURIComponent(text(fd, "businessId"))}`,
  );
}
