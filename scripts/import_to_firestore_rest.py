#!/usr/bin/env python3
"""
Import JSON POIs into Firestore using REST API.
Usage:
  .venv/bin/python scripts/import_to_firestore_rest.py path/to/pois.json
"""

from __future__ import annotations

import json
import re
import sys
import unicodedata
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import requests

# API configuration (from firebase_options.dart)
PROJECT_ID = "allspots-5872e"
API_KEY = "AIzaSyBuR3_AQq905D49EkFr_7R-8vptUaQTG2E"
FIRESTORE_URL = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents"

# Requests session with built-in retry
session = requests.Session()


def normalize_text(value: Any) -> str:
    text = str(value or "")
    text = unicodedata.normalize("NFD", text)
    text = "".join(ch for ch in text if unicodedata.category(ch) != "Mn")
    text = text.lower().strip()
    text = re.sub(r"[^a-z0-9]+", "_", text)
    text = re.sub(r"^_+|_+$", "", text)
    return text


def extract_coordinates(poi: Dict[str, Any]) -> Optional[Tuple[float, float]]:
    lat = poi.get("lat")
    lng = poi.get("lng")
    if isinstance(lat, (int, float)) and isinstance(lng, (int, float)):
        return float(lat), float(lng)

    location = poi.get("location")
    if isinstance(location, dict):
        loc_lat = location.get("_latitude", location.get("latitude"))
        loc_lng = location.get("_longitude", location.get("longitude"))
        if isinstance(loc_lat, (int, float)) and isinstance(loc_lng, (int, float)):
            return float(loc_lat), float(loc_lng)

    return None


def build_deterministic_id(poi: Dict[str, Any], lat: float, lng: float) -> str:
    rounded_lat = f"{lat:.6f}"
    rounded_lng = f"{lng:.6f}"

    if poi.get("source") == "openstreetmap" and poi.get("osmId") is not None:
        return f"osm_{poi['osmId']}"

    if poi.get("place_id"):
        return f"gplaces_{normalize_text(poi['place_id'])}"

    source = normalize_text(poi.get("source") or "unknown")
    category = normalize_text(poi.get("category") or poi.get("categoryGroup") or "other")
    name = normalize_text(poi.get("name") or "spot")
    return f"{source}_{category}_{name}_{rounded_lat}_{rounded_lng}"[:140]


def normalize_image_value(raw: Any) -> Optional[str]:
    if raw is None:
        return None
    value = str(raw).strip()
    if not value:
        return None

    if value.startswith("//"):
        return f"https:{value}"
    if value.startswith("http://") or value.startswith("https://"):
        return value

    lower = value.lower()
    if lower.startswith("file:"):
        filename = value.split(":", 1)[1].strip().replace(" ", "_")
        return (
            f"https://commons.wikimedia.org/wiki/Special:FilePath/{filename}"
            if filename
            else None
        )

    if lower.startswith("wikimedia_commons:"):
        filename = value.split(":", 1)[1].strip().replace(" ", "_")
        return (
            f"https://commons.wikimedia.org/wiki/Special:FilePath/{filename}"
            if filename
            else None
        )

    if re.match(r"^Q\d+$", value):
        return f"https://www.wikidata.org/wiki/{value}"

    if "/" not in value and "." in value:
        filename = value.replace(" ", "_")
        return f"https://commons.wikimedia.org/wiki/Special:FilePath/{filename}"

    return None


def extract_normalized_image_urls(poi: Dict[str, Any]) -> List[str]:
    candidates: List[Any] = []
    for key in ("imageUrls", "images"):
        value = poi.get(key)
        if isinstance(value, list):
            candidates.extend(value)
    for key in ("image", "photo", "thumbnail", "cover_image", "wikimedia_commons"):
        candidates.append(poi.get(key))

    urls: List[str] = []
    for candidate in candidates:
        normalized = normalize_image_value(candidate)
        if normalized and normalized not in urls:
            urls.append(normalized)
        if len(urls) >= 5:
            break
    return urls


def encode_firestore_value(value: Any) -> Any:
    """Encode a Python value as a Firestore value."""
    if value is None:
        return {"nullValue": None}

    if isinstance(value, bool):
        return {"booleanValue": value}

    if isinstance(value, int):
        return {"integerValue": str(value)}

    if isinstance(value, float):
        return {"doubleValue": value}

    if isinstance(value, str):
        return {"stringValue": value}

    if isinstance(value, (list, tuple)):
        return {"arrayValue": {"values": [encode_firestore_value(v) for v in value]}}

    if isinstance(value, dict):
        # Check if it's a GeoPoint
        if len(value) == 2 and "lat" in value and "lng" in value:
            return {
                "geoPointValue": {
                    "latitude": float(value["lat"]),
                    "longitude": float(value["lng"]),
                }
            }
        # Regular map
        return {"mapValue": {"fields": {k: encode_firestore_value(v) for k, v in value.items()}}}

    # Default: convert to string
    return {"stringValue": str(value)}


def create_poi_document(poi: Dict[str, Any], lat: float, lng: float) -> Dict[str, Any]:
    """Create a Firestore document from POI data."""
    image_urls = extract_normalized_image_urls(poi)

    fields = {}
    for key, value in poi.items():
        if key in ("lat", "lng", "location"):
            continue
        fields[key] = encode_firestore_value(value)

    fields["location"] = {
        "geoPointValue": {"latitude": lat, "longitude": lng}
    }
    fields["lat"] = encode_firestore_value(lat)
    fields["lng"] = encode_firestore_value(lng)
    fields["imageUrls"] = encode_firestore_value(image_urls)
    fields["images"] = encode_firestore_value(image_urls)
    fields["isPublic"] = encode_firestore_value(poi.get("isPublic", True))
    fields["isValidated"] = encode_firestore_value(poi.get("isValidated", True))
    fields["dedupeKey"] = encode_firestore_value(f"osm_{poi.get('osmId', 'unknown')}")
    fields["importedAt"] = {"timestampValue": datetime.now(timezone.utc).isoformat()}

    return {"fields": fields}


def upload_document(doc_id: str, document: Dict[str, Any]) -> bool:
    """Upload a single document to Firestore."""
    url = f"{FIRESTORE_URL}/spots/{doc_id}?key={API_KEY}"
    
    try:
        response = session.patch(url, json=document, timeout=10)
        if response.status_code not in (200, 201):
            print(f"⚠️  Erreur doc {doc_id}: {response.status_code} - {response.text[:100]}")
            return False
        return True
    except Exception as e:
        print(f"⚠️  Exception doc {doc_id}: {e}")
        return False


def import_pois(json_path: Path) -> None:
    if not json_path.exists():
        raise FileNotFoundError(f"Fichier introuvable: {json_path}")

    print(f"📥 Lecture: {json_path}")
    raw = json.loads(json_path.read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise ValueError("Le fichier JSON doit contenir une liste de POIs")

    prepared: List[Tuple[str, Dict[str, Any]]] = []
    skipped = 0
    seen_ids = set()

    for poi in raw:
        if not isinstance(poi, dict):
            skipped += 1
            continue

        coords = extract_coordinates(poi)
        if not coords:
            skipped += 1
            continue

        lat, lng = coords
        doc_id = build_deterministic_id(poi, lat, lng)
        if doc_id in seen_ids:
            skipped += 1
            continue
        seen_ids.add(doc_id)

        try:
            document = create_poi_document(poi, lat, lng)
            prepared.append((doc_id, document))
        except Exception as e:
            print(f"⚠️  Erreur préparation POI '{poi.get('name', 'unknown')}': {e}")
            skipped += 1

    print(f"📊 Préparés: {len(prepared)} | ignorés: {skipped}")

    imported = 0
    failed = 0
    for i, (doc_id, document) in enumerate(prepared, 1):
        if upload_document(doc_id, document):
            imported += 1
        else:
            failed += 1
        
        if i % 50 == 0:
            print(f"📤 Progression: {i}/{len(prepared)} (uploaded: {imported}, failed: {failed})")

    print(f"✅ Import terminé: {imported} spots")
    if failed:
        print(f"❌ Échoués: {failed}")
    if skipped:
        print(f"⚠️ Ignorés: {skipped}")


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: .venv/bin/python scripts/import_to_firestore_rest.py <fichier.json>")
        return 1

    json_path = Path(sys.argv[1])
    try:
        import_pois(json_path)
        return 0
    except Exception as exc:
        print(f"❌ Erreur import: {exc}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
