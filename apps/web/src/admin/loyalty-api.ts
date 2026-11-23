import "server-only";
import { contract } from "@darb/contracts";
import { initClient, type ApiFetcher } from "@ts-rest/core";
import { adminToken } from "./auth";

const noStore: ApiFetcher = async ({ path, method, headers, body }) => {
  const res = await fetch(path, { method, headers, body, cache: "no-store" });
  const type = res.headers.get("content-type") ?? "";
  return {
    status: res.status,
    body: type.includes("json") ? await res.json() : await res.text(),
    headers: res.headers,
  };
};

/** The admin's loyalty routes: offers and staff invite links. */
export async function loyaltyAdminApi() {
  const base = (process.env.API_URL ?? "").replace(/\/+$/, "");
  const token = (await adminToken()) ?? "";
  return initClient(contract.loyalty.admin, {
    baseUrl: base,
    baseHeaders: { authorization: `Bearer ${token}` },
    api: noStore,
    throwOnUnknownStatus: true,
  });
}
