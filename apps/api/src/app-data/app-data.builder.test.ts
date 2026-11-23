import { describe, expect, it } from "vitest";
import { buildAppData, businessId, clean, tri, week } from "./app-data.builder.js";

describe("the app's map", () => {
  it("numbers a business as the bundled data does, from its town and slug", () => {
    // the same numbers the app already has for Darb's clients, so their saved places and shops keep working
    expect(businessId("akko", "caramel", new Set())).toBe(1419998672);
    expect(businessId("nahf", "raghad", new Set())).toBe(729741531);
  });

  it("gives a second business with the same number a new one", () => {
    const taken = new Set([1419998672]);
    expect(businessId("akko", "caramel", taken)).not.toBe(1419998672);
  });

  it("fills a missing language from Hebrew, then from any", () => {
    expect(tri({ he: "קרמל", ar: "كراميل" })).toEqual({ he: "קרמל", ar: "كراميل", en: "קרמל" });
    expect(tri({ en: "Caramel" })).toEqual({ he: "Caramel", ar: "Caramel", en: "Caramel" });
  });

  it("keeps the dash between two times and drops it between two words", () => {
    expect(clean("Bakery — Akko")).toBe("Bakery Akko");
    expect(clean("09:00–21:00")).toBe("09:00-21:00");
  });

  it("reads a week and nothing when there are no hours", () => {
    expect(week({ weekly: { "0": [{ open: "09:00", close: "21:00" }] } })).toEqual({
      "0": [["09:00", "21:00"]],
    });
    expect(week({ weekly: {} })).toBeNull();
  });

  it("writes the businesses as columns, with sample hours marked, and their details by id", () => {
    const data = buildAppData({
      generated: new Date("2026-11-23T10:00:00Z"),
      sectors: [{ slug: "auto", name: { he: "רכב", ar: "سيارات", en: "Auto" }, accent: "#6fa8dc" }],
      kinds: [
        {
          slug: "dealers",
          sector: "auto",
          name: { he: "סוכנויות", ar: "معارض", en: "Dealers" },
          synonyms: { ar: ["معرض"] },
        },
      ],
      places: [
        {
          slug: "nahf",
          name: { he: "נחף", ar: "نحف", en: "Nahf" },
          aliases: [],
          lat: 32.934,
          lng: 35.317,
          type: "village",
          status: "soon",
        },
        {
          slug: "akko",
          name: { he: "עכו", ar: "عكا", en: "Akko" },
          aliases: [],
          lat: 32.92,
          lng: 35.07,
          type: "city",
          status: "soon",
        },
      ],
      businesses: [
        {
          slug: "naiefcar",
          place: "nahf",
          kind: "dealers",
          name: { he: "רכב אבו פיראס", ar: "معرض ابو فراس", en: "Abo Firas Car" },
          tagline: {},
          lat: 32.9371612,
          lng: 35.328244,
          hours: { weekly: { "0": [{ open: "09:00", close: "21:00" }] } },
          address: { he: "נחף", ar: "نحف", en: "Nahf" },
          phone: "0547227619",
          whatsapp: "0547227619",
          website: null,
          attributes: { osmId: "x" },
          links: { tiktok: "https://tiktok.com/@a", waze: "https://waze.com" },
          logo: { key: "pending/logo.webp" },
          photos: [{ key: "pending/front.webp", alt: {} }, { key: "../secret" }],
        },
        {
          slug: "garage",
          place: "nahf",
          kind: "dealers",
          name: { he: "מוסך" },
          tagline: { he: "מוסך" },
          lat: 32.93,
          lng: 35.31,
          hours: {},
          address: {},
          phone: null,
          whatsapp: null,
          website: null,
          attributes: {},
          links: {},
          logo: null,
          photos: [],
        },
      ],
    });
    // every city, town and village is listed, with or without businesses yet
    expect(data.places.map((p) => p.slug)).toEqual(["akko", "nahf"]);
    expect(data.businesses.id).toHaveLength(2);
    const firas = data.businesses.id.indexOf(businessId("nahf", "naiefcar", new Set()));
    expect(data.businesses.name.ar[firas]).toBe("معرض ابو فراس");
    expect(data.businesses.lat[firas]).toBe(32.93716);
    expect(data.businesses.demo[firas]).toBe(0);
    expect(data.businesses.demo[1 - firas]).toBe(1);
    expect(data.hours[data.businesses.hours[firas]!]).toEqual({ "0": [["09:00", "21:00"]] });
    expect(data.kinds[0]!.syn).toEqual({ he: [], ar: ["معرض"], en: [] });
    expect(data.businesses.logo[firas]).toBe("https://media.darb.co.il/pending/logo.webp");
    expect(data.businesses.cover[firas]).toBe("https://media.darb.co.il/pending/front.webp");
    expect(data.businesses.logo[1 - firas]).toBe("");
    expect(data.details[String(data.businesses.id[firas])]).toEqual({
      phone: "0547227619",
      wa: "0547227619",
      links: { tiktok: "https://tiktok.com/@a" },
      photos: ["https://media.darb.co.il/pending/front.webp"],
    });
  });
});
