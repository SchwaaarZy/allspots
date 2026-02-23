#!/usr/bin/env python3
"""
Import JSON POIs into Firestore using gcloud authenticated credentials.
"""

import json
import sys
from pathlib import Path
from datetime import datetime, timezone

import firebase_admin
from firebase_admin import credentials, firestore


def import_pois(json_path: Path) -> None:
    """Import POIs from JSON file into Firestore."""
    
    if not json_path.exists():
        raise FileNotFoundError(f"Fichier introuvable: {json_path}")
    
    print(f"📥 Lecture du fichier: {json_path}")
    data = json.loads(json_path.read_text(encoding="utf-8"))
    
    if not isinstance(data, list):
        raise ValueError("Le fichier JSON doit contenir une liste de POIs")
    
    print(f"📊 Nombre de POIs: {len(data)}")
    
    # Initialize Firebase with Application Default Credentials (from gcloud)
    if not firebase_admin._apps:
        try:
            # Utilise les credentials de gcloud auth login
            options = {
                'projectId': 'allspots-5872e',
            }
            firebase_admin.initialize_app(options=options)
        except Exception as e:
            print(f"❌ Erreur initialisation Firebase: {e}")
            return
    
    db = firestore.client()
    
    # Import en batch
    imported = 0
    failed = 0
    batch_size = 100
    
    for i, poi in enumerate(data):
        if not isinstance(poi, dict):
            failed += 1
            continue
        
        # Créer un ID unique basé sur l'osmId
        doc_id = f"osm_{poi.get('osmId', i)}"
        
        # Préparer le document
        doc = {
            **poi,
            "importedAt": datetime.now(timezone.utc),
            "isPublic": True,
        }
        
        # Écrire dans Firestore (merge pour pas écraser)
        try:
            db.collection("spots").document(doc_id).set(doc, merge=True)
            imported += 1
        except Exception as e:
            print(f"⚠️  Erreur sur POI {doc_id}: {e}")
            failed += 1
        
        # Afficher progression tous les 500
        if (i + 1) % 500 == 0:
            print(f"📤 Progression: {i + 1}/{len(data)} (importés: {imported}, échoués: {failed})")
    
    print(f"\n✅ Import terminé!")
    print(f"  📊 Total importés: {imported}")
    print(f"  ❌ Échoués: {failed}")


if __name__ == "__main__":
    # Utilise le fichier fourni en argument, sinon un fichier par défaut
    if len(sys.argv) > 1:
        json_path = Path(sys.argv[1])
    else:
        json_path = Path("scripts/out/pois_all_categories_20260223_093423.json")
    
    try:
        import_pois(json_path)
    except Exception as e:
        print(f"❌ Erreur: {e}")
        sys.exit(1)
