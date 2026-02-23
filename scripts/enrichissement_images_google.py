#!/usr/bin/env python3
"""
Script d'enrichissement des POIs existants avec des photos Google Places
"""

import requests
import json
import time
import argparse
from typing import List, Dict, Optional
import sys
from pathlib import Path
import firebase_admin
from firebase_admin import credentials, firestore
from google.cloud import firestore as gfirestore

# Configuration
GOOGLE_PLACES_API_KEY = "AIzaSyBbHU0nLg_T6v9tDsdh9_0cc3ksc1TC-dU"
BASE_URL = "https://maps.googleapis.com/maps/api/place"

# Départements PACA
PACA_DEPARTMENTS = ['04', '05', '06', '13', '83', '84']

def get_photo_url(photo_reference: str, max_width: int = 800) -> str:
    """Génère l'URL d'une photo Google Places"""
    return f"{BASE_URL}/photo?maxwidth={max_width}&photoreference={photo_reference}&key={GOOGLE_PLACES_API_KEY}"

def search_place_by_name_location(name: str, lat: float, lng: float, radius: int = 100) -> Optional[str]:
    """
    Recherche un lieu sur Google Places par nom et coordonnées
    Retourne le place_id si trouvé
    """
    url = f"{BASE_URL}/nearbysearch/json"
    params = {
        'location': f"{lat},{lng}",
        'radius': radius,
        'keyword': name,
        'key': GOOGLE_PLACES_API_KEY
    }
    
    try:
        response = requests.get(url, params=params, timeout=30)
        response.raise_for_status()
        data = response.json()
        
        if data.get('status') == 'OK' and data.get('results'):
            # Prendre le premier résultat (le plus proche)
            return data['results'][0].get('place_id')
        
        return None
    except Exception as e:
        print(f"    ⚠️  Erreur recherche: {e}")
        return None

def get_place_photos(place_id: str) -> List[str]:
    """
    Récupère les URLs des photos d'un lieu
    """
    url = f"{BASE_URL}/details/json"
    params = {
        'place_id': place_id,
        'fields': 'photos',
        'language': 'fr',
        'key': GOOGLE_PLACES_API_KEY
    }
    
    try:
        response = requests.get(url, params=params, timeout=30)
        response.raise_for_status()
        data = response.json()
        
        if data.get('status') == 'OK':
            photos = data.get('result', {}).get('photos', [])
            photo_urls = []
            
            # Prendre les 3 premières photos
            for photo in photos[:3]:
                photo_ref = photo.get('photo_reference')
                if photo_ref:
                    photo_urls.append(get_photo_url(photo_ref, max_width=1200))
            
            return photo_urls
        
        return []
    except Exception as e:
        print(f"    ⚠️  Erreur récupération photos: {e}")
        return []

def enrich_pois_with_google_photos(limit: int = None, test_mode: bool = False):
    """
    Enrichit les POIs PACA existants avec des photos Google Places
    """
    # Initialiser Firebase
    if not firebase_admin._apps:
        firebase_admin.initialize_app(options={'projectId': 'allspots-5872e'})
    
    db = firestore.client()
    
    # Récupérer les POIs PACA sans images ou avec peu d'images
    print("📊 Récupération des POIs PACA...")
    
    pois_query = db.collection('pois')
    
    if test_mode:
        # Mode test: seulement quelques POIs pour vérifier
        print("🧪 MODE TEST: 10 premiers POIs")
        pois_docs = pois_query.limit(10).stream()
    else:
        # Filtrer par départements PACA
        pois_docs = pois_query.where('departmentCode', 'in', PACA_DEPARTMENTS).stream()
    
    pois_to_enrich = []
    for doc in pois_docs:
        poi_data = doc.to_dict()
        poi_id = doc.id
        
        # Filtrer les POIs sans images ou avec moins de 2 images
        image_urls = poi_data.get('imageUrls', [])
        if not image_urls or len(image_urls) < 2:
            pois_to_enrich.append({
                'id': poi_id,
                'name': poi_data.get('name', ''),
                'category': poi_data.get('category', {}).get('label', ''),
                'lat': poi_data.get('location', {}).get('_latitude'),
                'lng': poi_data.get('location', {}).get('_longitude'),
                'current_images': len(image_urls)
            })
    
    print(f"✅ Trouvé {len(pois_to_enrich)} POIs à enrichir")
    
    if limit:
        pois_to_enrich = pois_to_enrich[:limit]
        print(f"🎯 Limite à {limit} POIs")
    
    # Enrichissement
    enriched_count = 0
    not_found_count = 0
    no_photos_count = 0
    error_count = 0
    
    for idx, poi in enumerate(pois_to_enrich):
        print(f"\n[{idx+1}/{len(pois_to_enrich)}] {poi['name']} ({poi['category']})")
        print(f"  📍 {poi['lat']:.5f}, {poi['lng']:.5f}")
        print(f"  📷 Images actuelles: {poi['current_images']}")
        
        try:
            # Rechercher sur Google Places
            place_id = search_place_by_name_location(
                poi['name'],
                poi['lat'],
                poi['lng'],
                radius=150  # 150m de rayon
            )
            
            if not place_id:
                print("  ❌ Pas trouvé sur Google Places")
                not_found_count += 1
                time.sleep(0.5)
                continue
            
            print(f"  ✅ Trouvé: {place_id}")
            
            # Récupérer les photos
            photo_urls = get_place_photos(place_id)
            
            if not photo_urls:
                print("  ⚠️  Aucune photo disponible")
                no_photos_count += 1
                time.sleep(0.5)
                continue
            
            print(f"  📸 {len(photo_urls)} photos récupérées")
            
            # Mettre à jour Firestore
            doc_ref = db.collection('pois').document(poi['id'])
            doc_ref.update({
                'imageUrls': photo_urls,
                'googlePlaceId': place_id,
                'enrichedAt': gfirestore.SERVER_TIMESTAMP
            })
            
            print(f"  ✅ Firestore mis à jour avec {len(photo_urls)} images")
            enriched_count += 1
            
            # Rate limiting (pour respecter le quota gratuit)
            time.sleep(1)
            
        except Exception as e:
            print(f"  ❌ Erreur: {e}")
            error_count += 1
            time.sleep(0.5)
            continue
    
    # Rapport final
    print("\n" + "="*60)
    print("📊 RAPPORT D'ENRICHISSEMENT")
    print("="*60)
    print(f"✅ POIs enrichis:        {enriched_count}")
    print(f"❌ Non trouvés:          {not_found_count}")
    print(f"⚠️  Sans photos:         {no_photos_count}")
    print(f"🔥 Erreurs:              {error_count}")
    print(f"📊 Total traité:         {len(pois_to_enrich)}")
    print("="*60)
    
    # Estimation du coût
    # Google Places: $17 / 1000 requêtes (Nearby Search) + $17 / 1000 (Place Details)
    total_requests = enriched_count * 2  # 1 nearby + 1 details par POI enrichi
    estimated_cost = (total_requests / 1000) * 17 * 2
    print(f"\n💰 Coût estimé: ${estimated_cost:.2f}")
    print(f"   (Quota gratuit: $200/mois)")

def main():
    parser = argparse.ArgumentParser(
        description='Enrichir les POIs PACA avec des photos Google Places'
    )
    parser.add_argument('--limit', type=int, default=None,
                        help='Nombre maximum de POIs à traiter')
    parser.add_argument('--test', action='store_true',
                        help='Mode test: traite seulement 10 POIs')
    
    args = parser.parse_args()
    
    print("🖼️  ENRICHISSEMENT DES POIS AVEC PHOTOS GOOGLE PLACES")
    print("="*60)
    print("📍 Région: PACA")
    print(f"🔑 API Key: {GOOGLE_PLACES_API_KEY[:20]}...")
    print("="*60)
    print()
    
    enrich_pois_with_google_photos(
        limit=args.limit,
        test_mode=args.test
    )
    
    print("\n✅ Enrichissement terminé!")

if __name__ == '__main__':
    main()
