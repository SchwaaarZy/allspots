#!/usr/bin/env python3
"""
Import UNESCO World Heritage sites for France (metropole + DOM-TOM).
Outputs POIs in the Firestore JSON format used by the app.

Primary source: UNESCO endpoints (when accessible)
Fallback source: Wikidata SPARQL for UNESCO-inscribed places in France
"""

import argparse
import json
import time
from typing import Dict, Iterable, List, Optional, Tuple

import requests

UNESCO_ENDPOINTS = [
    "https://whc.unesco.org/en/list/json/",
    "https://whc.unesco.org/en/list/?format=json",
    "https://whc.unesco.org/en/list/?json=1",
    "https://whc.unesco.org/en/list/?&json=1",
    "https://whc.unesco.org/en/list/?json",
]

WIKIDATA_SPARQL_ENDPOINT = "https://query.wikidata.org/sparql"

HTTP_HEADERS = {
    "User-Agent": "allspots-import/1.0 (+https://github.com/SchwaaarZy/allspots)",
    "Accept": "application/json, text/plain;q=0.9, */*;q=0.8",
    "Accept-Language": "fr,en;q=0.8",
}

CATEGORY_MAP = {
    "cultural": "histoire",
    "natural": "nature",
    "mixed": "histoire",
}

CATEGORY_CHOICES = [
    "tous",
    "culture",
    "nature",
    "experienceGustative",
    "histoire",
    "activites",
]


def normalize_value(value: Optional[str]) -> str:
    if value is None:
        return ""
    return str(value).strip()


def parse_float(value: Optional[object]) -> Optional[float]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        text = value.strip().replace(",", ".")
        try:
            return float(text)
        except ValueError:
            return None
    return None


def parse_wikidata_point(point_value: str) -> Optional[Tuple[float, float]]:
    text = normalize_value(point_value)
    if not text.startswith("Point(") or not text.endswith(")"):
        return None

    body = text[len("Point(") : -1].strip()
    parts = body.split()
    if len(parts) != 2:
        return None

    lng = parse_float(parts[0])
    lat = parse_float(parts[1])
    if lat is None or lng is None:
        return None

    return lat, lng


def extract_category_from_text(text: str) -> str:
    lower = normalize_value(text).lower()
    if any(token in lower for token in ("natural", "naturel", "natura")):
        return "natural"
    if any(token in lower for token in ("mixed", "mixte")):
        return "mixed"
    return "cultural"


def fetch_unesco_data() -> Dict:
    last_error: Optional[Exception] = None

    for endpoint in UNESCO_ENDPOINTS:
        try:
            response = requests.get(endpoint, timeout=45, headers=HTTP_HEADERS)
            response.raise_for_status()

            content_type = normalize_value(response.headers.get("Content-Type")).lower()
            if "json" not in content_type and not response.text.strip().startswith(("{", "[")):
                continue

            return response.json()
        except Exception as exc:
            last_error = exc
            continue

    raise RuntimeError(f"UNESCO endpoints unavailable: {last_error}")


def fetch_wikidata_unesco_france() -> List[Dict]:
    query = """
    SELECT ?item ?itemLabel ?coord ?unescoId ?heritageLabel WHERE {
      ?item wdt:P1435 ?heritage .
      ?heritage wdt:P279* wd:Q9259 .
      ?item wdt:P17 wd:Q142 .
      OPTIONAL { ?item wdt:P625 ?coord }
      OPTIONAL { ?item wdt:P757 ?unescoId }
      SERVICE wikibase:label { bd:serviceParam wikibase:language "fr,en". }
    }
    """

    response = requests.get(
        WIKIDATA_SPARQL_ENDPOINT,
        params={"query": query, "format": "json"},
        headers=HTTP_HEADERS,
        timeout=60,
    )
    response.raise_for_status()

    payload = response.json()
    records: List[Dict] = []

    for binding in payload.get("results", {}).get("bindings", []):
        item_label = binding.get("itemLabel", {}).get("value", "")
        point = binding.get("coord", {}).get("value", "")
        coords = parse_wikidata_point(point)
        if not item_label or not coords:
            continue

        unesco_id = binding.get("unescoId", {}).get("value", "")
        heritage_label = binding.get("heritageLabel", {}).get("value", "")
        unesco_category = extract_category_from_text(heritage_label)

        records.append(
            {
                "name": normalize_value(item_label),
                "description": normalize_value(heritage_label),
                "lat": coords[0],
                "lng": coords[1],
                "unesco_id": normalize_value(unesco_id),
                "unesco_category": unesco_category,
                "states": ["france"],
                "provider": "wikidata",
            }
        )

    return records


def iter_records(data: Dict) -> Iterable[Dict]:
    if isinstance(data, list):
        return data

    for key in ("features", "results", "records", "items", "properties"):
        value = data.get(key)
        if isinstance(value, list):
            return value

    return [data]


def extract_coordinates(props: Dict, geometry: Optional[Dict]) -> Optional[Tuple[float, float]]:
    if isinstance(geometry, dict):
        coords = geometry.get("coordinates")
        if isinstance(coords, (list, tuple)) and len(coords) >= 2:
            lng = parse_float(coords[0])
            lat = parse_float(coords[1])
            if lat is not None and lng is not None:
                return lat, lng

    for lat_key, lng_key in (
        ("latitude", "longitude"),
        ("lat", "lng"),
        ("lat", "lon"),
    ):
        lat = parse_float(props.get(lat_key))
        lng = parse_float(props.get(lng_key))
        if lat is not None and lng is not None:
            return lat, lng

    return None


def extract_states(props: Dict) -> List[str]:
    raw = None
    for key in (
        "states_name_en",
        "states_name_fr",
        "states_name",
        "states",
        "country",
        "country_en",
        "country_fr",
    ):
        raw = props.get(key)
        if raw:
            break

    if raw is None:
        return []

    values = raw if isinstance(raw, list) else [raw]

    states: List[str] = []
    for value in values:
        text = normalize_value(value)
        if not text:
            continue
        for part in text.replace("/", ",").replace("&", ",").split(","):
            cleaned = part.strip().lower()
            if cleaned:
                states.append(cleaned)
    return states


def matches_countries(states: List[str], countries: List[str]) -> bool:
    if not states:
        return False
    target = {c.lower() for c in countries if c}
    return any(state in target for state in states)


def extract_name(props: Dict) -> str:
    for key in ("name_en", "name_fr", "name", "site", "property", "title"):
        value = props.get(key)
        if value:
            return normalize_value(value)
    return ""


def extract_description(props: Dict) -> str:
    for key in (
        "short_description",
        "short_description_en",
        "short_description_fr",
        "description",
        "desc",
        "summary",
    ):
        value = props.get(key)
        if value:
            return normalize_value(value)
    return ""


def extract_city(props: Dict) -> str:
    for key in ("city", "region", "province", "location"):
        value = props.get(key)
        if value:
            return normalize_value(value)
    return "France"


def extract_unesco_id(props: Dict) -> Optional[str]:
    for key in ("id", "unesco_id", "unique_number", "wh_id"):
        value = props.get(key)
        if value:
            return normalize_value(value)
    return None


def extract_category(props: Dict) -> str:
    raw = None
    for key in ("category", "category_en", "category_short", "type"):
        raw = props.get(key)
        if raw:
            break

    if not raw:
        return "cultural"

    return extract_category_from_text(str(raw))


def convert_unesco_json_records(
    data: Dict,
    countries: List[str],
    category_filter: str,
    limit: Optional[int],
) -> List[Dict]:
    pois: List[Dict] = []
    seen_ids = set()

    for item in iter_records(data):
        props = item.get("properties") if isinstance(item, dict) else None
        if not isinstance(props, dict):
            props = item.get("fields") if isinstance(item, dict) else None
        if not isinstance(props, dict):
            props = item if isinstance(item, dict) else {}

        geometry = item.get("geometry") if isinstance(item, dict) else None
        if not geometry and isinstance(props, dict):
            geometry = props.get("geometry")

        states = extract_states(props)
        if countries and not matches_countries(states, countries):
            continue

        coords = extract_coordinates(props, geometry)
        if not coords:
            continue

        name = extract_name(props)
        if not name:
            continue

        unesco_category = extract_category(props)
        mapped_category = CATEGORY_MAP.get(unesco_category, "histoire")

        if category_filter != "tous" and mapped_category != category_filter:
            continue

        unesco_id = extract_unesco_id(props)
        if unesco_id and unesco_id in seen_ids:
            continue
        if unesco_id:
            seen_ids.add(unesco_id)

        lat, lng = coords
        description = extract_description(props)
        city = extract_city(props)
        website = f"https://whc.unesco.org/en/list/{unesco_id}" if unesco_id else ""

        pois.append(
            {
                "name": name,
                "description": description,
                "location": {"_latitude": lat, "_longitude": lng},
                "category": mapped_category,
                "city": city,
                "images": [],
                "rating": 0.0,
                "website": website,
                "isPublic": True,
                "isValidated": True,
                "source": "unesco",
                "unescoId": unesco_id or "",
                "unescoCategory": unesco_category,
                "country": ", ".join(sorted({c.title() for c in states})),
                "createdAt": {"_seconds": int(time.time()), "_nanoseconds": 0},
            }
        )

        if limit and len(pois) >= limit:
            break

    return pois


def convert_wikidata_records(
    records: List[Dict],
    category_filter: str,
    limit: Optional[int],
) -> List[Dict]:
    pois: List[Dict] = []
    seen_ids = set()

    for item in records:
        unesco_category = item.get("unesco_category", "cultural")
        mapped_category = CATEGORY_MAP.get(unesco_category, "histoire")

        if category_filter != "tous" and mapped_category != category_filter:
            continue

        unesco_id = normalize_value(item.get("unesco_id"))
        if unesco_id and unesco_id in seen_ids:
            continue
        if unesco_id:
            seen_ids.add(unesco_id)

        website = f"https://whc.unesco.org/en/list/{unesco_id}" if unesco_id else ""

        pois.append(
            {
                "name": normalize_value(item.get("name")),
                "description": normalize_value(item.get("description")) or "Site UNESCO",
                "location": {
                    "_latitude": float(item["lat"]),
                    "_longitude": float(item["lng"]),
                },
                "category": mapped_category,
                "city": "France",
                "images": [],
                "rating": 0.0,
                "website": website,
                "isPublic": True,
                "isValidated": True,
                "source": "unesco",
                "unescoId": unesco_id,
                "unescoCategory": unesco_category,
                "country": "France",
                "createdAt": {"_seconds": int(time.time()), "_nanoseconds": 0},
            }
        )

        if limit and len(pois) >= limit:
            break

    return pois


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import UNESCO World Heritage sites for France (metropole + DOM-TOM)."
    )
    parser.add_argument(
        "--output",
        default="pois_unesco_france.json",
        help="Output JSON file path",
    )
    parser.add_argument(
        "--category",
        default="tous",
        choices=CATEGORY_CHOICES,
        help="App category filter (or 'tous')",
    )
    parser.add_argument(
        "--countries",
        default="France",
        help="Comma-separated list of country names to include",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limit number of records (debug)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    countries = [c.strip() for c in args.countries.split(",") if c.strip()]
    limit = args.limit if args.limit > 0 else None

    pois: List[Dict] = []

    try:
        print("Fetching UNESCO data...")
        unesco_data = fetch_unesco_data()
        print("Converting UNESCO records...")
        pois = convert_unesco_json_records(unesco_data, countries, args.category, limit)
    except Exception as error:
        print(f"UNESCO endpoint unavailable ({error}). Falling back to Wikidata...")
        wikidata_records = fetch_wikidata_unesco_france()
        pois = convert_wikidata_records(wikidata_records, args.category, limit)

    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(pois, handle, indent=2, ensure_ascii=False)

    print(f"Done. Wrote {len(pois)} POIs to {args.output}.")


if __name__ == "__main__":
    main()
