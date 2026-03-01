#!/usr/bin/env python3
"""
Import JSON POIs into Firestore using Firebase Admin SDK (Python).
Usage:
  .venv/bin/python scripts/import_to_firestore.py path/to/pois.json
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
import unicodedata
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

import firebase_admin
from firebase_admin import firestore


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


def to_timestamp(value: Any):
    if isinstance(value, dict) and "_seconds" in value:
        try:
            seconds = int(value["_seconds"])
            nanos = int(value.get("_nanoseconds", 0))
            dt = datetime.fromtimestamp(seconds + nanos / 1_000_000_000, tz=timezone.utc)
            return firestore.Timestamp.from_datetime(dt)
        except Exception:
            pass

    if isinstance(value, str):
        try:
            if value.endswith("Z"):
                value = value.replace("Z", "+00:00")
            dt = datetime.fromisoformat(value)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return firestore.Timestamp.from_datetime(dt)
        except Exception:
            pass

    return firestore.SERVER_TIMESTAMP


def chunks(items: List[Tuple[str, Dict[str, Any]]], size: int) -> Iterable[List[Tuple[str, Dict[str, Any]]]]:
    for index in range(0, len(items), size):
        yield items[index : index + size]


def _is_retryable_firestore_error(exc: Exception) -> bool:
    message = str(exc).lower()
    retry_markers = (
        "429",
        "quota exceeded",
        "resource exhausted",
        "deadline exceeded",
        "timed out",
        "unavailable",
    )
    return any(marker in message for marker in retry_markers)


def commit_with_retry(batch, *, max_retries: int = 8, base_delay: float = 2.0) -> None:
    for attempt in range(max_retries + 1):
        try:
            batch.commit()
            return
        except Exception as exc:
            if attempt >= max_retries or not _is_retryable_firestore_error(exc):
                raise
            wait_seconds = min(base_delay * (2**attempt), 90.0)
            print(
                f"⏳ Batch retry {attempt + 1}/{max_retries} après erreur quota/réseau: {exc} | pause={wait_seconds:.1f}s"
            )
            time.sleep(wait_seconds)


def import_pois(json_path: Path) -> None:
    if not json_path.exists():
        raise FileNotFoundError(f"Fichier introuvable: {json_path}")

    if not firebase_admin._apps:
        firebase_admin.initialize_app()

    db = firestore.client()

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

        image_urls = extract_normalized_image_urls(poi)

        record = dict(poi)
        record["location"] = firestore.GeoPoint(lat, lng)
        record["lat"] = lat
        record["lng"] = lng
        record["imageUrls"] = image_urls
        record["images"] = image_urls
        record["isPublic"] = bool(record.get("isPublic", True))
        record["isValidated"] = bool(record.get("isValidated", True))
        record["createdAt"] = to_timestamp(record.get("createdAt"))
        record["updatedAt"] = to_timestamp(record.get("updatedAt"))
        record["dedupeKey"] = doc_id
        record["importedAt"] = firestore.SERVER_TIMESTAMP

        prepared.append((doc_id, record))

    print(f"📊 Préparés: {len(prepared)} | ignorés: {skipped}")

    progress_dir = Path(
        os.getenv("FIRESTORE_PROGRESS_DIR", str(json_path.parent / "import_progress"))
    )
    progress_dir.mkdir(parents=True, exist_ok=True)
    progress_file = progress_dir / f"{json_path.stem}.offset"

    start_offset = 0
    if progress_file.exists():
        try:
            start_offset = int(progress_file.read_text(encoding="utf-8").strip() or "0")
        except Exception:
            start_offset = 0

    total_prepared = len(prepared)
    if start_offset > 0:
        if start_offset >= total_prepared:
            print(f"✅ Chunk déjà terminé (offset={start_offset}/{total_prepared})")
            return
        prepared = prepared[start_offset:]
        print(f"↪️ Reprise depuis offset {start_offset}/{total_prepared}")

    batch_size = int(os.getenv("FIRESTORE_BATCH_SIZE", "250"))
    batch_size = max(1, min(batch_size, 500))
    inter_batch_sleep = float(os.getenv("FIRESTORE_BATCH_SLEEP", "0.2"))

    imported = start_offset
    for part in chunks(prepared, batch_size):
        batch = db.batch()
        for doc_id, record in part:
            ref = db.collection("spots").document(doc_id)
            batch.set(ref, record, merge=True)
        commit_with_retry(batch)
        imported += len(part)
        progress_file.write_text(str(imported), encoding="utf-8")
        print(f"💾 Batch ok: {imported}/{total_prepared}")
        if inter_batch_sleep > 0:
            time.sleep(inter_batch_sleep)

    print(f"✅ Import terminé: {imported} spots")
    if progress_file.exists():
        progress_file.unlink()
    if skipped:
        print(f"⚠️ Ignorés: {skipped}")


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: .venv/bin/python scripts/import_to_firestore.py <fichier.json>")
        return 1

    json_path = Path(sys.argv[1])
    try:
        import_pois(json_path)
        return 0
    except Exception as exc:
        print(f"❌ Erreur import: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
