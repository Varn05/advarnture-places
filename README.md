# Advarnture places

Every food shop, café, place to stay, water point and bike shop in Europe from OpenStreetMap, as one
[PMTiles](https://docs.protomaps.com/pmtiles/) file that the Advarnture app reads straight from GitHub Pages.

- `build.sh` downloads each European country from [Geofabrik](https://download.geofabrik.de), keeps only
  the kinds of place in `kinds.json`, and builds `places.pmtiles` with tippecanoe.
- `.github/workflows/update-places.yml` runs it on the 2nd of every month and publishes the result.
  Run it by hand from the Actions tab ("Update places", then "Run workflow").
- `info.json` says when it last ran and how many places it found.

The copy of these files in the Advarnture app repo (`places-build/`) is the master; copy changes here.

Map data © OpenStreetMap contributors, under the [Open Database License](https://www.openstreetmap.org/copyright).
