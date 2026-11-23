# Retired listings

Imported open data that is no longer loaded: OpenStreetMap places, schools, garages and food places from
public lists. Too many of them had closed or moved, so on 2026-11-23 Darb switched them off and began
covering the north town by town, by hand.

The seed loader reads only `data/listings/`. A business that left it is suspended, not deleted: it disappears
from the website, the app, search and the sitemap, and its row stays in the database. A business an admin
edited (`editedAt` set), one added in the admin or by a helper, and one with a claim, an owner or a join
request is never suspended.

To bring a file back, move it into `data/listings/` and run the "Seed and reindex" workflow with the seed box
ticked.
