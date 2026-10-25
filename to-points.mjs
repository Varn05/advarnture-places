// Turns `osmium export` output (one GeoJSON feature per line) into small point features for tippecanoe.
// Usage: node to-points.mjs a.geojsonseq b.geojsonseq ... > places.geojsonseq
import { createReadStream, readFileSync } from "node:fs";
import { createInterface } from "node:readline";

const KINDS = JSON.parse(readFileSync(new URL("./kinds.json", import.meta.url), "utf8"));

/** Osmium gives areas made from ways and relations their own ids (2n and 2n+1); map them back. */
export function osmId(id) {
  const m = /^([nwra])(\d+)$/.exec(String(id));
  if (!m) return undefined;
  if (m[1] !== "a") return m[1] + m[2];
  const n = BigInt(m[2]);
  return (n % 2n === 0n ? "w" : "r") + (n / 2n).toString();
}

/** A rough middle of a shape: the average of its outline's points is plenty for a map bubble. */
export function middle(geometry) {
  const ring =
    geometry.type === "Point"
      ? [geometry.coordinates]
      : geometry.type === "LineString"
        ? geometry.coordinates
        : geometry.type === "Polygon"
          ? geometry.coordinates[0]
          : geometry.type === "MultiPolygon"
            ? geometry.coordinates[0][0]
            : undefined;
  if (!ring?.length) return undefined;
  const lon = ring.reduce((s, c) => s + c[0], 0) / ring.length;
  const lat = ring.reduce((s, c) => s + c[1], 0) / ring.length;
  return [Math.round(lon * 1e5) / 1e5, Math.round(lat * 1e5) / 1e5];
}

/** One osmium feature to one point feature (or undefined if it isn't a kind of place we keep). */
export function toPoint(feature) {
  const tags = feature.properties ?? {};
  const kind = KINDS.find((k) => tags[k.key] === k.value);
  const id = osmId(feature.id);
  const at = feature.geometry && middle(feature.geometry);
  if (!kind || !id || !at) return undefined;
  const name = tags.name || tags["name:en"] || tags.brand;
  // Short keys keep the file small: k = kind, n = name, i = OpenStreetMap id.
  const properties = { k: kind.value, i: id };
  if (name) properties.n = name.slice(0, 60);
  return { type: "Feature", geometry: { type: "Point", coordinates: at }, properties };
}

async function main(files) {
  const seen = new Set();
  let kept = 0;
  for (const file of files) {
    const lines = createInterface({ input: createReadStream(file), crlfDelay: Infinity });
    for await (const raw of lines) {
      const line = raw.replace(/^\x1e/, "").trim();
      if (!line) continue;
      const point = toPoint(JSON.parse(line));
      // Places near a border appear in both countries' files, and closed ways appear twice.
      if (!point || seen.has(point.properties.i)) continue;
      seen.add(point.properties.i);
      process.stdout.write(JSON.stringify(point) + "\n");
      kept++;
    }
  }
  process.stderr.write(`Kept ${kept} places\n`);
}

if (import.meta.url === `file://${process.argv[1]}`) await main(process.argv.slice(2));
