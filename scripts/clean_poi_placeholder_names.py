#!/usr/bin/env python3
"""
Nettoie les noms placeholder des POIs Firestore (ex: "POI sans nom").

Par défaut, exécute un dry-run.
Utiliser --apply pour appliquer réellement les mises à jour.

Usage:
  python3 scripts/clean_poi_placeholder_names.py
  python3 scripts/clean_poi_placeholder_names.py --apply
  python3 scripts/clean_poi_placeholder_names.py --apply --limit 500
"""

from __future__ import annotations

import argparse
import json
import re
import unicodedata
from typing import Any, Dict, Iterable, Optional
from pathlib import Path

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


def is_placeholder_name(name: Any) -> bool:
    normalized = normalize_text(name)
    if not normalized:
        return True

    placeholders = {
        "poi sans nom",
        "point d interet poi sans nom",
        "point dinteret poi sans nom",
        "point interet poi sans nom",
        "sans nom",
        "spot",
        "poi",
        "unknown",
        "unnamed",
    }

    if normalized in placeholders:
        return True
    if "poi sans nom" in normalized:
        return True
    if "point d interet" in normalized and "sans nom" in normalized:
        return True

    return False


def category_label(raw_category: Any) -> str:
    normalized = normalize_text(raw_category)
    mapping = {
        "culture": "Culture",
        "nature": "Nature",
        "histoire": "Histoire",
        "experience gustative": "Expérience gustative",
        "experiencegustative": "Expérience gustative",
        "experience_gustative": "Expérience gustative",
        "activites": "Activités",
        "activites plein air": "Activités",
    }
    return mapping.get(normalized, "Culture")


def format_subcategory(raw: Any) -> str:
    text = str(raw or "").strip()
    if not text:
        return ""

    normalized = normalize_text(text)
    dictionary = {
        "scenic viewpoint": "Point de vue",
        "viewpoint": "Point de vue",
        "natural feature": "Site naturel",
        "tourist attraction": "Attraction touristique",
        "art gallery": "Galerie d'art",
        "sports complex": "Complexe sportif",
        "hiking area": "Zone de randonnée",
        "place of worship": "Lieu de culte",
        "amusement park": "Parc d'attractions",
    }
    if normalized in dictionary:
        return dictionary[normalized]

    words = [w for w in normalized.split(" ") if w]
    if not words:
        return ""

    return " ".join(word[0].upper() + word[1:] for word in words)


def build_replacement_name(data: Dict[str, Any]) -> str:
    description = normalize_text(data.get("description"))
    if "point de vue" in description:
        return "Point de vue"

    subcategory = format_subcategory(data.get("categoryItem") or data.get("subCategory"))
    if subcategory:
        return subcategory

    category = category_label(data.get("categoryGroup") or data.get("category"))
    return category


def iter_spots(limit: Optional[int]) -> Iterable[firestore.DocumentSnapshot]:
    db = firestore.client()
    query = db.collection("spots")
    if limit is not None and limit > 0:
        query = query.limit(limit)
    return query.stream()


def main() -> int:
    parser = argparse.ArgumentParser(description="Nettoyage des noms POI placeholder")
    parser.add_argument("--apply", action="store_true", help="Applique réellement les modifications")
    parser.add_argument("--limit", type=int, default=0, help="Limite le nombre de documents scannés")
    parser.add_argument(
        "--backup",
        type=str,
        default="",
        help="Chemin du backup JSON des modifications (recommandé avec --apply)",
    )
    args = parser.parse_args()

    if not firebase_admin._apps:
        firebase_admin.initialize_app()

    scanned = 0
    candidates = 0
    updated = 0
    backup_rows = []

    batch = firestore.client().batch()
    batch_count = 0

    for doc in iter_spots(args.limit if args.limit > 0 else None):
        scanned += 1
        data = doc.to_dict() or {}

        current_name = data.get("name")
        if not is_placeholder_name(current_name):
            continue

        replacement = build_replacement_name(data)
        if normalize_text(replacement) == normalize_text(current_name):
            continue

        candidates += 1
        print(f"- {doc.id}: '{current_name}' -> '{replacement}'")

        if args.backup:
            backup_rows.append(
                {
                    "id": doc.id,
                    "oldName": current_name,
                    "newName": replacement,
                }
            )

        if args.apply:
            batch.update(
                doc.reference,
                {
                    "name": replacement,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                },
            )
            batch_count += 1
            updated += 1

            if batch_count >= 400:
                batch.commit()
                batch = firestore.client().batch()
                batch_count = 0

    if args.apply and batch_count > 0:
        batch.commit()

    if args.backup:
        backup_path = Path(args.backup)
        backup_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "mode": "apply" if args.apply else "dry-run",
            "scanned": scanned,
            "candidates": candidates,
            "updated": updated,
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
    print(f"Modifiés  : {updated}")

    if not args.apply:
        print("\nRelancer avec --apply pour écrire en base.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
