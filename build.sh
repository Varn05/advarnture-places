#!/usr/bin/env bash
# Builds places.pmtiles: every food shop, place to stay, water point and bike shop in Europe,
# from OpenStreetMap extracts on download.geofabrik.de. Needs osmium-tool, tippecanoe and node.
#
#   ./build.sh                         all of Europe, one country at a time
#   REGIONS="portugal spain" ./build.sh  just those countries
#   PBF_FILES="a.osm.pbf" ./build.sh    files you already have (no download)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$PWD/work}
OUT=${OUT:-$PWD/site}
GEOFABRIK=https://download.geofabrik.de
# Groupings of other countries, skipped so nothing is downloaded twice.
SKIP=" alps britain-and-ireland dach united-kingdom "
mkdir -p "$WORK/geo" "$OUT"
rm -f "$WORK"/geo/*

# "nwr/shop=supermarket,bakery nwr/amenity=cafe ..." from kinds.json, so the app and the build agree.
FILTERS=$(node -e '
  const kinds = require(process.argv[1]);
  const byKey = {};
  for (const k of kinds) (byKey[k.key] ??= []).push(k.value);
  console.log(Object.entries(byKey).map(([key, vals]) => `nwr/${key}=${vals.join(",")}`).join(" "));
' "$HERE/kinds.json")
KEYS=$(node -e 'console.log(JSON.stringify([...new Set(require(process.argv[1]).map((k) => k.key))]))' "$HERE/kinds.json")
cat > "$WORK/export.json" <<EOF
{ "attributes": { "type": false, "id": false }, "include_tags": ["name", "name:en", "brand", ${KEYS:1:-1}] }
EOF

extract() { # file name
  osmium tags-filter "$1" $FILTERS --overwrite -o "$WORK/filtered.osm.pbf"
  osmium export "$WORK/filtered.osm.pbf" -c "$WORK/export.json" -f geojsonseq -x print_record_separator=false \
    --add-unique-id=type_id --overwrite -o "$WORK/geo/$2.geojsonseq"
  rm -f "$WORK/filtered.osm.pbf"
  echo "$2: $(wc -l < "$WORK/geo/$2.geojsonseq") features"
}

if [ -n "${PBF_FILES:-}" ]; then
  for f in $PBF_FILES; do extract "$f" "$(basename "$f" | cut -d. -f1)"; done
else
  if [ -z "${REGIONS:-}" ]; then
    curl -fsSL --retry 5 "$GEOFABRIK/index-v1-nogeom.json" -o "$WORK/index.json"
    REGIONS=$(node -e '
      const idx = require(process.argv[1]);
      console.log(idx.features.map((f) => f.properties).filter((p) => p.parent === "europe").map((p) => p.id).join(" "));
    ' "$WORK/index.json")
  fi
  for r in $REGIONS; do
    case "$SKIP" in *" $r "*) continue ;; esac
    echo "Downloading $r"
    curl -fsSL --retry 5 --retry-delay 30 "$GEOFABRIK/europe/$r-latest.osm.pbf" -o "$WORK/in.osm.pbf"
    extract "$WORK/in.osm.pbf" "$r"
    rm -f "$WORK/in.osm.pbf"
  done
fi

node "$HERE/to-points.mjs" "$WORK"/geo/*.geojsonseq > "$WORK/points.geojsonseq"

# Zoomed out (5 to 12): at most 600 places a tile, dropping the most crowded ones first, so quiet
# countryside keeps everything and busy towns thin out. Zoom 13 keeps every place, and the map
# reuses those tiles when zoomed in further.
tippecanoe -q -o "$WORK/low.pmtiles" -l places -Z5 -z12 -r1 --maximum-tile-features=600 --drop-densest-as-needed --force "$WORK/points.geojsonseq"
tippecanoe -q -o "$WORK/full.pmtiles" -l places -Z13 -z13 -r1 --no-feature-limit --no-tile-size-limit --force "$WORK/points.geojsonseq"
BUILT=$(date -u +%Y-%m-%d)
tile-join -q -o "$OUT/places.pmtiles" -n "Advarnture places" -A "© OpenStreetMap contributors" \
  -N "Built $BUILT" --no-tile-size-limit --force "$WORK/low.pmtiles" "$WORK/full.pmtiles"

COUNT=$(wc -l < "$WORK/points.geojsonseq")
echo "{\"built\":\"$BUILT\",\"places\":$COUNT}" > "$OUT/info.json"
echo "Built $OUT/places.pmtiles: $COUNT places, $(du -h "$OUT/places.pmtiles" | cut -f1)"
