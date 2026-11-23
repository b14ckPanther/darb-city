"use server";

import { CardCodeSchema } from "@darb/contracts";
import { redirect } from "next/navigation";
import { helperHref } from "@/helpers/routes";
import { isLocale } from "@/lib/locale";
import { staffApi } from "./api";

/** Stamps a card, or hands over its reward, then shows the card again with what happened. */
export async function scanCard(fd: FormData): Promise<void> {
  const locale = String(fd.get("locale") ?? "");
  const lang = isLocale(locale) ? locale : "he";
  const code = CardCodeSchema.safeParse(String(fd.get("code") ?? ""));
  const offerId = String(fd.get("offerId") ?? "");
  const action = fd.get("action") === "redeem" ? "redeem" : "stamp";
  if (!code.success) redirect(helperHref(lang, "/stamp"));
  const api = await staffApi();
  const res =
    action === "redeem"
      ? await api.redeem({ body: { code: code.data, offerId } })
      : await api.stamp({ body: { code: code.data, offerId } });
  const outcome =
    res.status === 200
      ? action === "redeem"
        ? "redeemed"
        : "stamped"
      : res.status === 409 && "code" in res.body && res.body.code
        ? res.body.code
        : "failed";
  redirect(
    `${helperHref(lang, `/stamp/${code.data}`)}?done=${encodeURIComponent(outcome)}&offer=${encodeURIComponent(offerId)}`,
  );
}

/** Joins a partner's staff from an invite link. */
export async function joinStaff(fd: FormData): Promise<void> {
  const locale = String(fd.get("locale") ?? "");
  const lang = isLocale(locale) ? locale : "he";
  const token = String(fd.get("token") ?? "");
  const res = await (await staffApi()).join({ body: { token } });
  redirect(
    `${helperHref(lang, "/stamp")}?joined=${res.status === 200 ? "1" : res.status === 410 ? "expired" : "invalid"}`,
  );
}
