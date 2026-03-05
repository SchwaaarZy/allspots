#!/usr/bin/env python3
"""
Audit and cleanup for Firestore `spots` collection:
- detect duplicate spots
- detect nameless/generic POIs
- optionally delete unwanted documents

Default mode is DRY-RUN. Use --apply to write changes.

Usage examples:
  python3 scripts/audit_cleanup_spots.py
  python3 scripts/audit_cleanup_spots.py --report scripts/out/spots_audit_report.json
  python3 scripts/audit_cleanup_spots.py --apply --backup scripts/out/spots_cleanup_backup.json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import time
import unicodedata
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

import firebase_admin
from firebase_admin import firestore


@dataclass
class SpotRecord:
    doc_id: str
    ref: Any
    data: Dict[str, Any]


def normalize_text(value: Any) -> str:
    text = str(value or "").strip().lower()
    text = unicodedata.normalize("NFD", text)
    text = "".join(ch for ch in text if unicodedata.category(ch) != "Mn")
    text = text.replace("'", " ").replace("-", " ").replace(":", " ")
    text = re.sub(r"[^a-z0-9 ]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def to_number(value: Any) -> Optional[float]:
    if isinstance(value, (int, float)):
        return float(value)
    return None


def extract_coords(data: Dict[str, Any]) -> Optional[Tuple[float, float]]:
    lat = to_number(data.get("lat"))
    lng = to_number(data.get("lng"))
    if lat is not None and lng is not None:
        return lat, lng

    location = data.get("location") or {}
    lat = to_number(location.get("latitude"))
    lng = to_number(location.get("longitude"))
    if lat is not None and lng is not None:
        return lat, lng

    lat = to_number(location.get("_latitude"))
    lng = to_number(location.get("_longitude"))
    if lat is not None and lng is not None:
        return lat, lng

    return None


def read_millis(value: Any) -> int:
    if value is None:
        return 0
    if hasattr(value, "timestamp"):
        try:
            return int(value.timestamp() * 1000)
        except Exception:
            return 0
    if isinstance(value, str):
        try:
            return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)
        except Exception:
            return 0
    return 0


def is_nameless_or_generic(name: Any) -> bool:
    normalized = normalize_text(name)
    generic_names = {
        "",
        "autre",
        "other",
        "poi",
        "spot",
        "sans nom",
        "poi sans nom",
        "point d interet",
        "point interet",
        "point d interet poi sans nom",
        "point interet poi sans nom",
        "unknown",
        "unnamed",
    }
    if normalized in generic_names:
        return True
    if "sans nom" in normalized and "poi" in normalized:
        return True
    return False


def build_dedupe_key(record: SpotRecord) -> str:
    data = record.data

    dedupe_key = data.get("dedupeKey")
    if isinstance(dedupe_key, str) and dedupe_key.strip():
        return dedupe_key.strip()

    source = normalize_text(data.get("source") or "unknown")

    osm_id = data.get("osmId")
    if source == "openstreetmap" and osm_id:
        return f"osm:{osm_id}"

    place_id = data.get("place_id")
    if place_id:
        return f"gplaces:{normalize_text(place_id)}"

    coords = extract_coords(data)
    if coords is None:
        return f"doc:{record.doc_id}"

    lat, lng = coords
    category = normalize_text(data.get("category") or data.get("categoryGroup") or "other")
    name = normalize_text(data.get("name") or "spot")

    return f"{source}:{category}:{name}:{lat:.6f}:{lng:.6f}"


def quality_score(record: SpotRecord) -> int:
    data = record.data
    score = 0

    description = str(data.get("description") or "").strip()
    if len(description) >= 40:
        score += 3
    elif len(description) >= 15:
        score += 2
    elif description:
        score += 1

    image_urls = data.get("imageUrls") if isinstance(data.get("imageUrls"), list) else []
    images = data.get("images") if isinstance(data.get("images"), list) else []
    image_count = max(len(image_urls), len(images))
    if image_count >= 3:
        score += 3
    elif image_count >= 1:
        score += 2

    if str(data.get("website") or data.get("websiteUrl") or "").strip():
        score += 1

    if str(data.get("category") or data.get("categoryGroup") or "").strip():
        score += 1

    if data.get("isValidated") is True:
        score += 1

    # Avoid keeping nameless records when a better equivalent exists.
    if is_nameless_or_generic(data.get("name")):
        score -= 4

    return score


def choose_keeper(records: List[SpotRecord]) -> SpotRecord:
    return sorted(
        records,
        key=lambda rec: (
            quality_score(rec),
            read_millis(rec.data.get("updatedAt")),
            read_millis(rec.data.get("createdAt")),
            rec.doc_id,
        ),
        reverse=True,
    )[0]


def is_retryable_firestore_error(exc: Exception) -> bool:
    message = str(exc).lower()
    markers = (
        "429",
        "quota exceeded",
        "resource exhausted",
        "deadline exceeded",
        "timed out",
        "unavailable",
    )
    return any(marker in message for marker in markers)


def query_get_with_retry(
    query,
    *,
    max_retries: int,
    base_delay: float,
    query_timeout: float,
):
    for attempt in range(max_retries + 1):
        try:
            # Disable client auto-retry to keep retry strategy centralized here.
            return query.get(retry=None, timeout=query_timeout)
        except Exception as exc:
            if attempt >= max_retries or not is_retryable_firestore_error(exc):
                raise
            wait_seconds = min(base_delay * (2**attempt), 120.0)
            print(
                f"Retry query {attempt + 1}/{max_retries} after Firestore quota/network error: {exc} | wait={wait_seconds:.1f}s"
            )
            time.sleep(wait_seconds)


def commit_with_retry(batch, *, max_retries: int, base_delay: float) -> None:
    for attempt in range(max_retries + 1):
        try:
            batch.commit()
            return
        except Exception as exc:
            if attempt >= max_retries or not is_retryable_firestore_error(exc):
                raise
            wait_seconds = min(base_delay * (2**attempt), 120.0)
            print(
                f"Retry commit {attempt + 1}/{max_retries} after Firestore quota/network error: {exc} | wait={wait_seconds:.1f}s"
            )
            time.sleep(wait_seconds)


def fetch_all_spots(
    db,
    *,
    page_size: int,
    sleep_seconds: float,
    max_retries: int,
    base_delay: float,
    query_timeout: float,
    max_docs: int,
) -> List[SpotRecord]:
    records: List[SpotRecord] = []
    last_doc = None

    while True:
        query = (
            db.collection("spots")
            .order_by("__name__")
            .limit(page_size)
        )
        if last_doc is not None:
            query = query.start_after(last_doc)

        snap = query_get_with_retry(
            query,
            max_retries=max_retries,
            base_delay=base_delay,
            query_timeout=query_timeout,
        )

        if not snap:
            break

        for doc in snap:
            records.append(SpotRecord(doc_id=doc.id, ref=doc.reference, data=doc.to_dict() or {}))
            if max_docs > 0 and len(records) >= max_docs:
                return records

        last_doc = snap[-1]
        print(f"Scanned: {len(records)} docs")

        if len(snap) < page_size:
            break

        if sleep_seconds > 0:
            time.sleep(sleep_seconds)

    return records


def build_duplicate_groups(records: Iterable[SpotRecord]):
    by_key: Dict[str, List[SpotRecord]] = {}
    for record in records:
        key = build_dedupe_key(record)
        by_key.setdefault(key, []).append(record)

    groups = []
    for key, items in by_key.items():
        if len(items) <= 1:
            continue
        keeper = choose_keeper(items)
        to_delete = [item for item in items if item.doc_id != keeper.doc_id]
        groups.append({"key": key, "keeper": keeper, "to_delete": to_delete, "all": items})

    return groups


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit and cleanup Firestore spots")
    parser.add_argument("--apply", action="store_true", help="Apply deletes/updates")
    parser.add_argument("--project-id", type=str, default="", help="Firebase/GCP project ID")
    parser.add_argument("--page-size", type=int, default=250, help="Documents read per page")
    parser.add_argument("--write-batch-size", type=int, default=400, help="Writes per batch commit")
    parser.add_argument("--sleep-seconds", type=float, default=0.2, help="Pause between pages")
    parser.add_argument("--max-retries", type=int, default=6, help="Max retries on quota/network errors")
    parser.add_argument("--base-delay", type=float, default=2.0, help="Initial retry delay")
    parser.add_argument("--query-timeout", type=float, default=30.0, help="Per-query timeout in seconds")
    parser.add_argument("--max-docs", type=int, default=0, help="Max docs to read (0 = all)")
    parser.add_argument(
        "--report",
        type=str,
        default="scripts/out/spots_audit_report.json",
        help="Path to JSON audit report",
    )
    parser.add_argument(
        "--backup",
        type=str,
        default="",
        help="Path to JSON backup of documents that would be deleted",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    project_id = (
        args.project_id.strip()
        or os.getenv("GOOGLE_CLOUD_PROJECT", "").strip()
        or os.getenv("GCLOUD_PROJECT", "").strip()
        or os.getenv("FIREBASE_PROJECT_ID", "").strip()
        or "allspots-5872e"
    )

    if not firebase_admin._apps:
        firebase_admin.initialize_app(options={"projectId": project_id})

    db = firestore.client()

    print("Scanning Firestore spots...")
    records = fetch_all_spots(
        db,
        page_size=max(1, args.page_size),
        sleep_seconds=max(0.0, args.sleep_seconds),
        max_retries=max(0, args.max_retries),
        base_delay=max(0.1, args.base_delay),
        query_timeout=max(5.0, args.query_timeout),
        max_docs=max(0, args.max_docs),
    )

    by_id = {r.doc_id: r for r in records}
    nameless_ids = {
        r.doc_id
        for r in records
        if is_nameless_or_generic(r.data.get("name"))
    }

    duplicate_groups = build_duplicate_groups(records)
    duplicate_delete_ids = {
        r.doc_id
        for group in duplicate_groups
        for r in group["to_delete"]
    }

    delete_ids = sorted(nameless_ids | duplicate_delete_ids)
    duplicate_overlap_nameless = len(nameless_ids & duplicate_delete_ids)

    report = {
        "generatedAt": datetime.utcnow().isoformat() + "Z",
        "mode": "apply" if args.apply else "dry-run",
        "projectId": project_id,
        "scanned": len(records),
        "duplicates": {
            "groups": len(duplicate_groups),
            "docsToDelete": len(duplicate_delete_ids),
            "samples": [
                {
                    "dedupeKey": group["key"],
                    "keeperId": group["keeper"].doc_id,
                    "docIds": [r.doc_id for r in group["all"]],
                }
                for group in duplicate_groups[:20]
            ],
        },
        "nameless": {
            "docs": len(nameless_ids),
            "samples": [
                {
                    "id": r.doc_id,
                    "name": r.data.get("name"),
                    "category": r.data.get("category") or r.data.get("categoryGroup"),
                    "source": r.data.get("source"),
                }
                for r in records
                if r.doc_id in nameless_ids
            ][:50],
        },
        "cleanup": {
            "totalUniqueDocsToDelete": len(delete_ids),
            "overlapNamelessAndDuplicate": duplicate_overlap_nameless,
        },
    }

    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print("\n=== Summary ===")
    print(f"Mode                : {'APPLY' if args.apply else 'DRY-RUN'}")
    print(f"Scanned             : {len(records)}")
    print(f"Duplicate groups    : {len(duplicate_groups)}")
    print(f"Duplicate docs      : {len(duplicate_delete_ids)}")
    print(f"Nameless docs       : {len(nameless_ids)}")
    print(f"Delete unique docs  : {len(delete_ids)}")
    print(f"Report              : {report_path}")

    if not args.apply:
        print("\nDry-run only. Re-run with --apply to delete documents.")
        return 0

    if not delete_ids:
        print("Nothing to delete.")
        return 0

    if args.backup:
        backup_rows = []
        for doc_id in delete_ids:
            rec = by_id.get(doc_id)
            if rec is None:
                continue
            reasons = []
            if doc_id in nameless_ids:
                reasons.append("nameless")
            if doc_id in duplicate_delete_ids:
                reasons.append("duplicate")
            backup_rows.append(
                {
                    "id": doc_id,
                    "reasons": reasons,
                    "data": rec.data,
                }
            )

        backup_payload = {
            "generatedAt": datetime.utcnow().isoformat() + "Z",
            "projectId": project_id,
            "total": len(backup_rows),
            "rows": backup_rows,
        }
        backup_path = Path(args.backup)
        backup_path.parent.mkdir(parents=True, exist_ok=True)
        backup_path.write_text(json.dumps(backup_payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Backup written: {backup_path}")

    # Persist dedupe metadata on keepers before deleting duplicates.
    keepers = [group["keeper"] for group in duplicate_groups]
    batch_size = max(1, args.write_batch_size)

    updated = 0
    for i in range(0, len(keepers), batch_size):
        batch = db.batch()
        slice_keepers = keepers[i : i + batch_size]
        for keeper in slice_keepers:
            batch.set(
                keeper.ref,
                {
                    "dedupeKey": build_dedupe_key(keeper),
                    "dedupedAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,
            )
            updated += 1
        commit_with_retry(batch, max_retries=max(0, args.max_retries), base_delay=max(0.1, args.base_delay))

    deleted = 0
    for i in range(0, len(delete_ids), batch_size):
        batch = db.batch()
        chunk = delete_ids[i : i + batch_size]
        for doc_id in chunk:
            batch.delete(db.collection("spots").document(doc_id))
        commit_with_retry(batch, max_retries=max(0, args.max_retries), base_delay=max(0.1, args.base_delay))
        deleted += len(chunk)
        print(f"Deleted: {deleted}/{len(delete_ids)}")

    print("\nCleanup completed.")
    print(f"Keepers updated: {updated}")
    print(f"Documents deleted: {deleted}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
