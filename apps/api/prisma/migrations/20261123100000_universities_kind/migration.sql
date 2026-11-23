-- Four places added by hand were filed under the wrong kind: two University of Haifa dorms (as a daycare
-- and as a school), its city campus and the Technion (as vocational training). They move to universities
-- and colleges, and are marked edited so the seed never touches them. A database without them (CI, tests,
-- a fresh copy) changes nothing.
CREATE TEMP TABLE "_moved" AS
SELECT b.id
FROM "Business" b
JOIN "Place" p ON p.id = b."placeId"
WHERE (p.slug, b.slug) IN (
  ('haifa', 'mavnvt-stvdntym-21-23'),
  ('etgar', 'haifa-university-shikma-dorms'),
  ('haifa', 'university-of-haifa-city-campus-dylan-building'),
  ('nesher', 'technion-israel-institute-of-technology')
);

UPDATE "Business"
SET "primaryKindId" = (SELECT id FROM "Kind" WHERE slug = 'universities'), "editedAt" = now(), "updatedAt" = now()
WHERE id IN (SELECT id FROM "_moved") AND EXISTS (SELECT 1 FROM "Kind" WHERE slug = 'universities');

DELETE FROM "BusinessKind" WHERE "businessId" IN (SELECT id FROM "_moved")
  AND EXISTS (SELECT 1 FROM "Kind" WHERE slug = 'universities');

INSERT INTO "BusinessKind" ("businessId", "kindId")
SELECT m.id, k.id FROM "_moved" m CROSS JOIN "Kind" k WHERE k.slug = 'universities'
ON CONFLICT DO NOTHING;

DROP TABLE "_moved";
