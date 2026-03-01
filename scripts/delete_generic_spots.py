#!/usr/bin/env python3
"""
Supprime les spots génériques de Firestore (ex: "Autre", "POI sans nom").

Par défaut: dry-run (aucune suppression).
Utiliser --apply pour supprimer réellement.

Usage:
  python3 scripts/delete_generic_spots.py
  python3 scripts/delete_generic_spots.py --apply
  python3 scripts/delete_generic_spots.py --apply --limit 1000
  python3 scripts/delete_generic_spots.py --apply --backup scripts/out/deleted_generic_spots.json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import time
import unicodedata
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional

import firebase_admin
from firebase_admin import firestore


def normalize_text(value: Any) -> str:
    text = str(value or "").strip().lower()
    text = unicodedata.normalize("NFD", text)
    text = "".join(ch for ch in text if unicodedata.category(ch) != "Mn")
    text = text.replace("'", " ").replace("-", " ").replace(":", " ")
    text = re.sub(r"[^a-z0-9 ]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def is_generic_spot(data: Dict[str, Any]) -> bool:
    name = normalize_text(data.get("name"))
    category_group = normalize_text(data.get("categoryGroup") or data.get("category"))
    category_item = normalize_text(data.get("categoryItem") or data.get("subCategory"))

    generic_names = {
        "autre",
        "other",
        "poi",
        "spot",
        "sans nom",
        "poi sans nom",
        "point d interet poi sans nom",
        "point dinteret poi sans nom",
        "point interet poi sans nom",
        "point d interet",
        "point interet",
        "unknown",
        "unnamed",
        "",
    }

    generic_categories = {"autre", "other"}
    generic_sub_categories = {
        "autre",
        "other",
        "poi",
        "point d interet",
        "point interet",
    }

    if name in generic_names:
        return True
    if "poi sans nom" in name:
        return True
    if category_group in generic_categories:
        return True
    if category_item in generic_sub_categories:
        return True

    return False


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


def _query_with_retry(query, *, max_retries: int = 4, base_delay: float = 2.0):
    for attempt in range(max_retries + 1):
        try:
            return list(query.stream())
        except Exception as exc:
            if attempt >= max_retries or not _is_retryable_firestore_error(exc):
                raise
            wait_seconds = min(base_delay * (2**attempt), 90.0)
            print(
                f"⏳ Query retry {attempt + 1}/{max_retries} après erreur quota/réseau: {exc} | pause={wait_seconds:.1f}s"
            )
            time.sleep(wait_seconds)


def _commit_with_retry(batch, *, max_retries: int = 8, base_delay: float = 2.0) -> None:
    for attempt in range(max_retries + 1):
        try:
            batch.commit()
            return
        except Exception as exc:
            if attempt >= max_retries or not _is_retryable_firestore_error(exc):
                raise
            wait_seconds = min(base_delay * (2**attempt), 90.0)
            print(
                f"⏳ Commit retry {attempt + 1}/{max_retries} après erreur quota/réseau: {exc} | pause={wait_seconds:.1f}s"
            )
            time.sleep(wait_seconds)


def _collect_candidate_docs(
    db,
    *,
    limit: Optional[int] = None,
    query_limit: int = 300,
    max_retries: int = 4,
    base_delay: float = 2.0,
):
    names_exact = [
        "POI sans nom",
        "poi sans nom",
        "Sans nom",
        "Autre",
        "Other",
    ]
    group_values = ["Autre", "Other", "autre", "other"]
    item_values = [
        "Autre",
        "Other",
        "POI",
        "poi",
        "Point d'intérêt",
        "Point d interet",
        "Point interet",
    ]

    by_id = {}

    def add_docs(docs):
        for d in docs:
            if limit is not None and limit > 0 and len(by_id) >= limit:
                return
            by_id.setdefault(d.id, d)

    for value in names_exact:
        if limit is not None and limit > 0 and len(by_id) >= limit:
            break
        docs = _query_with_retry(
            db.collection("spots").where("name", "==", value).limit(query_limit),
            max_retries=max_retries,
            base_delay=base_delay,
        )
        add_docs(docs)

    for value in group_values:
        if limit is not None and limit > 0 and len(by_id) >= limit:
            break
        docs = _query_with_retry(
            db.collection("spots").where("categoryGroup", "==", value).limit(query_limit),
            max_retries=max_retries,
            base_delay=base_delay,
        )
        add_docs(docs)

    for value in item_values:
        if limit is not None and limit > 0 and len(by_id) >= limit:
            break
        docs = _query_with_retry(
            db.collection("spots").where("categoryItem", "==", value).limit(query_limit),
            max_retries=max_retries,
            base_delay=base_delay,
        )
        add_docs(docs)

    for value in item_values:
        if limit is not None and limit > 0 and len(by_id) >= limit:
            break
        docs = _query_with_retry(
            db.collection("spots").where("subCategory", "==", value).limit(query_limit),
            max_retries=max_retries,
            base_delay=base_delay,
        )
        add_docs(docs)

    return list(by_id.values())


def main() -> int:
    parser = argparse.ArgumentParser(description="Suppression des spots génériques")
    parser.add_argument("--apply", action="store_true", help="Supprime réellement les documents")
    parser.add_argument("--limit", type=int, default=0, help="Limite de documents scannés")
    parser.add_argument(
        "--backup",
        type=str,
        default="",
        help="Fichier JSON de backup des documents supprimés (fortement recommandé en --apply)",
    )
    parser.add_argument(
        "--project-id",
        type=str,
        default="",
        help="ID du projet Firebase/GCP (ex: allspots-5872e)",
    )
    parser.add_argument(
        "--print-limit",
        type=int,
        default=80,
        help="Nombre max de lignes candidates à afficher dans le terminal",
    )
    parser.add_argument(
        "--query-limit",
        type=int,
        default=300,
        help="Nombre max de documents récupérés par requête ciblée",
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=4,
        help="Nombre maximum de retries sur erreurs quota/réseau",
    )
    parser.add_argument(
        "--base-delay",
        type=float,
        default=2.0,
        help="Pause initiale (secondes) pour backoff retries",
    )
    args = parser.parse_args()

    project_id = (
        args.project_id.strip()
        or os.getenv("GOOGLE_CLOUD_PROJECT", "").strip()
        or os.getenv("GCLOUD_PROJECT", "").strip()
        or os.getenv("FIREBASE_PROJECT_ID", "").strip()
        or "allspots-5872e"
    )

    if not firebase_admin._apps:
        firebase_admin.initialize_app(options={"projectId": project_id})

    scanned = 0
    candidates = 0
    deleted = 0
    backup_rows = []
    printed = 0

    db = firestore.client()
    batch = db.batch()
    batch_count = 0

    candidate_docs = _collect_candidate_docs(
        db,
        limit=args.limit if args.limit > 0 else None,
        query_limit=max(1, args.query_limit),
        max_retries=max(0, args.max_retries),
        base_delay=max(0.1, args.base_delay),
    )

    for doc in candidate_docs:
        scanned += 1
        data = doc.to_dict() or {}

        if not is_generic_spot(data):
            continue

        candidates += 1
        name = (data.get("name") or "").strip()
        category_group = (data.get("categoryGroup") or data.get("category") or "").strip()
        category_item = (data.get("categoryItem") or data.get("subCategory") or "").strip()
        department = (
            data.get("departmentCode")
            or data.get("departementCode")
            or data.get("dept")
            or ""
        )

        if args.print_limit <= 0 or printed < args.print_limit:
            print(
                f"- {doc.id} | name='{name or '∅'}' | group='{category_group or '∅'}' | item='{category_item or '∅'}' | dept='{department or '∅'}'"
            )
            printed += 1

        if args.backup:
            backup_rows.append(
                {
                    "id": doc.id,
                    "name": data.get("name"),
                    "categoryGroup": data.get("categoryGroup"),
                    "categoryItem": data.get("categoryItem"),
                    "subCategory": data.get("subCategory"),
                    "departmentCode": data.get("departmentCode")
                    or data.get("departementCode")
                    or data.get("dept"),
                    "lat": data.get("lat"),
                    "lng": data.get("lng"),
                }
            )

        if args.apply:
            batch.delete(doc.reference)
            batch_count += 1
            deleted += 1

            if batch_count >= 400:
                _commit_with_retry(batch)
                batch = db.batch()
                batch_count = 0

    if args.apply and batch_count > 0:
        _commit_with_retry(batch)

    if args.backup:
        backup_path = Path(args.backup)
        backup_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "generatedAt": datetime.utcnow().isoformat() + "Z",
            "mode": "apply" if args.apply else "dry-run",
            "scanned": scanned,
            "candidates": candidates,
            "deleted": deleted,
            "changes": backup_rows,
        }
        backup_path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"Backup JSON écrit: {backup_path}")

    mode = "APPLY" if args.apply else "DRY-RUN"
    print("\n=== Résumé ===")
    print(f"Mode      : {mode}")
    print(f"Scannés   : {scanned}")
    print(f"Candidats : {candidates}")
    print(f"Supprimés : {deleted}")
    if candidates > printed and args.print_limit > 0:
        print(f"Affichage terminal limité à {printed}/{candidates} candidats.")

    if not args.apply:
        print("\nRelancer avec --apply pour supprimer en base.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
