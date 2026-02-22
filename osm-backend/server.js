import express from "express";

const app = express();
const port = process.env.PORT || 3000;

app.use((_, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  next();
});

app.get("/health", (_, res) => {
  res.json({ status: "ok" });
});

app.get("/poi", async (req, res) => {
  try {
    const lat = parseFloat(req.query.lat);
    const lng = parseFloat(req.query.lng);
    const radius = Math.min(Math.max(parseFloat(req.query.radius) || 10000, 1000), 50000);
    const categoriesRaw = (req.query.categories || "").toString();
    const categories = categoriesRaw
      .split(",")
      .map((c) => c.trim())
      .filter(Boolean);

    if (Number.isNaN(lat) || Number.isNaN(lng)) {
      return res.status(400).json({ error: "lat/lng required" });
    }

    const tagFilters = buildTagFilters(categories);
    const overpassQuery = buildOverpassQuery(lat, lng, radius, tagFilters);

    const overpassRes = await fetch("https://overpass-api.de/api/interpreter", {
      method: "POST",
      headers: { "Content-Type": "text/plain" },
      body: overpassQuery,
    });

    if (!overpassRes.ok) {
      return res.status(502).json({ error: "overpass error" });
    }

    const data = await overpassRes.json();
    const elements = Array.isArray(data.elements) ? data.elements : [];

    const pois = [];
    const seen = new Set();

    for (const el of elements) {
      if (!el.tags) continue;
      const name = el.tags.name;
      if (!name) continue;

      const id = `osm_${el.id}`;
      if (seen.has(id)) continue;
      seen.add(id);

      const coords = getCoordinates(el);
      if (!coords) continue;

      const category = classifyCategory(el.tags, categories);
      if (!category) continue;

      pois.push({
        id,
        name,
        category,
        subCategory: el.tags.tourism || el.tags.amenity || el.tags.historic || el.tags.natural || null,
        lat: coords.lat,
        lng: coords.lng,
        shortDescription: el.tags.description || el.tags.operator || "",
        imageUrls: [],
        websiteUrl: el.tags.website || null,
        isFree: null,
        pmrAccessible: el.tags.wheelchair === "yes" ? true : el.tags.wheelchair === "no" ? false : null,
        kidsFriendly: null,
        source: "osm",
        updatedAt: new Date().toISOString(),
      });
    }

    res.json(pois);
  } catch (err) {
    res.status(500).json({ error: "server error" });
  }
});

function buildTagFilters(categories) {
  const filters = new Set();
  const cats = categories.length ? categories : ["culture", "nature", "histoire", "experience_gustative", "activites"];

  if (cats.includes("culture")) {
    filters.add("tourism=museum");
    filters.add("tourism=art_gallery");
    filters.add("tourism=attraction");
  }
  if (cats.includes("nature")) {
    filters.add("leisure=park");
    filters.add("tourism=viewpoint");
    filters.add("natural=peak");
    filters.add("natural=waterfall");
  }
  if (cats.includes("histoire")) {
    filters.add("historic=monument");
    filters.add("historic=ruins");
    filters.add("historic=castle");
  }
  if (cats.includes("experience_gustative")) {
    filters.add("amenity=restaurant");
    filters.add("amenity=cafe");
    filters.add("amenity=marketplace");
  }
  if (cats.includes("activites")) {
    filters.add("leisure=sports_centre");
    filters.add("leisure=stadium");
    filters.add("tourism=alpine_hut");
  }

  return Array.from(filters);
}

function buildOverpassQuery(lat, lng, radius, tagFilters) {
  const filters = tagFilters
    .map((tag) => {
      const [k, v] = tag.split("=");
      return `node[${k}=${v}](around:${radius},${lat},${lng});`;
    })
    .join("\n");

  return `[out:json][timeout:25];\n(${filters});\nout center 200;`;
}

function getCoordinates(el) {
  if (typeof el.lat === "number" && typeof el.lon === "number") {
    return { lat: el.lat, lng: el.lon };
  }
  if (el.center && typeof el.center.lat === "number" && typeof el.center.lon === "number") {
    return { lat: el.center.lat, lng: el.center.lon };
  }
  return null;
}

function classifyCategory(tags, categories) {
  const cats = categories.length ? categories : ["culture", "nature", "histoire", "experience_gustative", "activites"];

  if (cats.includes("culture") && (tags.tourism === "museum" || tags.tourism === "art_gallery" || tags.tourism === "attraction")) {
    return "culture";
  }
  if (cats.includes("nature") && (tags.leisure === "park" || tags.tourism === "viewpoint" || tags.natural === "peak" || tags.natural === "waterfall")) {
    return "nature";
  }
  if (cats.includes("histoire") && (tags.historic === "monument" || tags.historic === "ruins" || tags.historic === "castle")) {
    return "histoire";
  }
  if (cats.includes("experience_gustative") && (tags.amenity === "restaurant" || tags.amenity === "cafe" || tags.amenity === "marketplace")) {
    return "experience_gustative";
  }
  if (cats.includes("activites") && (tags.leisure === "sports_centre" || tags.leisure === "stadium" || tags.tourism === "alpine_hut")) {
    return "activites";
  }

  return null;
}

app.listen(port, () => {
  console.log(`OSM API listening on ${port}`);
});
