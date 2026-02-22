#!/usr/bin/env python3
"""
Script d'importation de POIs depuis Google Places API (quota gratuit)
Utilise le quota gratuit de 200$/mois pour compléter les données OSM
Idéal pour les photos de qualité et les lieux populaires
"""

import requests
import json
import time
import argparse
from typing import List, Dict, Optional
import sys

# Configuration
GOOGLE_PLACES_API_KEY = ""  # À remplir avec votre clé API
BASE_URL = "https://maps.googleapis.com/maps/api/place"

# Mapping des catégories app vers types Google Places
CATEGORY_TO_GOOGLE_TYPES = {
    'culture': ['museum', 'art_gallery', 'library', 'theater', 'cultural_center'],
    'nature': ['park', 'natural_feature', 'campground', 'hiking_area'],
    'experienceGustative': ['restaurant', 'cafe', 'bakery', 'bar', 'wine_bar'],
    'histoire': ['historical_landmark', 'monument', 'castle', 'archaeological_site'],
    'activites': ['tourist_attraction', 'amusement_park', 'aquarium', 'zoo', 'sports_complex']
}

def search_places(location: str, category: str, radius: int = 10000) -> List[Dict]:
    """
    Recherche des lieux via Google Places API Nearby Search
    
    Args:
        location: "lat,lng" format
        category: catégorie de l'app
        radius: rayon de recherche en mètres (max 50000)
    
    Returns:
        Liste de lieux trouvés
    """
    if not GOOGLE_PLACES_API_KEY:
        print("❌ Erreur: GOOGLE_PLACES_API_KEY non configurée")
        print("Obtenez une clé sur: https://console.cloud.google.com/apis/credentials")
        sys.exit(1)
    
    google_types = CATEGORY_TO_GOOGLE_TYPES.get(category, ['tourist_attraction'])
    all_places = []
    
    for place_type in google_types:
        print(f"  🔍 Recherche type: {place_type}...")
        
        url = f"{BASE_URL}/nearbysearch/json"
        params = {
            'location': location,
            'radius': radius,
            'type': place_type,
            'key': GOOGLE_PLACES_API_KEY
        }
        
        try:
            response = requests.get(url, params=params, timeout=30)
            response.raise_for_status()
            data = response.json()
            
            if data.get('status') == 'OK':
                results = data.get('results', [])
                print(f"    ✅ Trouvé {len(results)} lieux")
                all_places.extend(results)
                
                # Gérer la pagination (max 60 résultats par type)
                next_page_token = data.get('next_page_token')
                while next_page_token and len(all_places) < 200:
                    time.sleep(2)  # Délai requis pour next_page_token
                    response = requests.get(
                        url,
                        params={'pagetoken': next_page_token, 'key': GOOGLE_PLACES_API_KEY},
                        timeout=30
                    )
                    data = response.json()
                    if data.get('status') == 'OK':
                        results = data.get('results', [])
                        all_places.extend(results)
                        next_page_token = data.get('next_page_token')
                    else:
                        break
            
            elif data.get('status') == 'ZERO_RESULTS':
                print(f"    ℹ️  Aucun résultat pour {place_type}")
            else:
                print(f"    ⚠️  Erreur API: {data.get('status')}")
            
            time.sleep(1)  # Rate limiting
            
        except Exception as e:
            print(f"    ❌ Erreur: {e}")
            continue
    
    # Dédupliquer par place_id
    seen_ids = set()
    unique_places = []
    for place in all_places:
        place_id = place.get('place_id')
        if place_id and place_id not in seen_ids:
            seen_ids.add(place_id)
            unique_places.append(place)
    
    print(f"  📊 Total unique: {len(unique_places)} lieux")
    return unique_places

def get_place_details(place_id: str) -> Optional[Dict]:
    """
    Récupère les détails complets d'un lieu (photos, horaires, etc.)
    """
    url = f"{BASE_URL}/details/json"
    params = {
        'place_id': place_id,
        'fields': 'name,formatted_address,geometry,photos,rating,website,formatted_phone_number,opening_hours,types',
        'language': 'fr',
        'key': GOOGLE_PLACES_API_KEY
    }
    
    try:
        response = requests.get(url, params=params, timeout=30)
        response.raise_for_status()
        data = response.json()
        
        if data.get('status') == 'OK':
            return data.get('result')
        return None
    except Exception as e:
        print(f"    ⚠️  Erreur détails: {e}")
        return None

def get_photo_url(photo_reference: str, max_width: int = 800) -> str:
    """
    Génère l'URL d'une photo Google Places
    """
    return f"{BASE_URL}/photo?maxwidth={max_width}&photoreference={photo_reference}&key={GOOGLE_PLACES_API_KEY}"

def convert_to_firestore_format(places: List[Dict], category: str, city_name: str) -> List[Dict]:
    """
    Convertit les résultats Google Places au format Firestore
    """
    firestore_pois = []
    
    for idx, place in enumerate(places):
        print(f"  {idx+1}/{len(places)} - {place.get('name', 'Sans nom')}")
        
        # Récupérer les détails complets
        details = get_place_details(place.get('place_id', ''))
        if not details:
            details = place  # Fallback aux données basiques
        
        # Position
        location = details.get('geometry', {}).get('location', {})
        lat = location.get('lat')
        lng = location.get('lng')
        
        if not lat or not lng:
            continue
        
        # Photos (qualité supérieure de Google)
        images = []
        photos = details.get('photos', [])[:5]  # Max 5 photos
        for photo in photos:
            photo_ref = photo.get('photo_reference')
            if photo_ref:
                images.append(get_photo_url(photo_ref))
        
        # Construction du POI
        poi = {
            'name': details.get('name', 'Sans nom'),
            'description': details.get('formatted_address', ''),
            'location': {
                '_latitude': lat,
                '_longitude': lng
            },
            'category': category,
            'city': city_name,
            'images': images,
            'rating': details.get('rating', 0.0),
            'website': details.get('website', ''),
            'phone': details.get('formatted_phone_number', ''),
            'isPublic': True,
            'isValidated': True,
            'source': 'google_places',
            'place_id': place.get('place_id', ''),
            'types': details.get('types', []),
            'createdAt': {'_seconds': int(time.time()), '_nanoseconds': 0}
        }
        
        # Horaires d'ouverture
        opening_hours = details.get('opening_hours')
        if opening_hours:
            poi['opening_hours'] = opening_hours.get('weekday_text', [])
        
        firestore_pois.append(poi)
        
        time.sleep(0.5)  # Rate limiting pour les détails
    
    return firestore_pois

def main():
    parser = argparse.ArgumentParser(
        description='Importer des POIs depuis Google Places API (quota gratuit)'
    )
    parser.add_argument('--city', required=True, help='Nom de la ville (ex: Paris)')
    parser.add_argument('--location', required=True, help='Coordonnées "lat,lng" (ex: 48.8566,2.3522)')
    parser.add_argument('--category', required=True, 
                        choices=['culture', 'nature', 'experienceGustative', 'histoire', 'activites'],
                        help='Catégorie à importer')
    parser.add_argument('--radius', type=int, default=10000, 
                        help='Rayon de recherche en mètres (max 50000)')
    parser.add_argument('--output', default='pois_google_import.json',
                        help='Fichier de sortie JSON')
    parser.add_argument('--limit', type=int, default=50,
                        help='Nombre maximum de POIs à importer (pour gérer le quota)')
    
    args = parser.parse_args()
    
    print(f"🔍 Recherche Google Places pour {args.city}")
    print(f"📍 Localisation: {args.location}")
    print(f"📂 Catégorie: {args.category}")
    print(f"📏 Rayon: {args.radius}m")
    print(f"🎯 Limite: {args.limit} POIs")
    print()
    
    # Recherche des lieux
    print("🔍 Recherche en cours...")
    places = search_places(args.location, args.category, args.radius)
    
    if not places:
        print("❌ Aucun lieu trouvé")
        return
    
    # Limiter le nombre pour respecter le quota
    places = places[:args.limit]
    print(f"\n📊 {len(places)} POIs sélectionnés (limite: {args.limit})")
    
    # Conversion au format Firestore
    print("\n🔄 Conversion au format Firestore...")
    firestore_pois = convert_to_firestore_format(places, args.category, args.city)
    
    # Sauvegarde
    print(f"\n💾 Sauvegarde dans {args.output}...")
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(firestore_pois, f, ensure_ascii=False, indent=2)
    
    print(f"\n✅ Terminé ! {len(firestore_pois)} POIs exportés")
    print(f"📄 Fichier: {args.output}")
    print(f"\n💰 Coût estimé: ~{len(firestore_pois) * 0.017:.2f}$ (sur quota gratuit 200$/mois)")
    print(f"📊 Quota restant: ~{200 - (len(firestore_pois) * 0.017):.2f}$")
    print("\n🔥 Import dans Firestore:")
    print(f"   firebase firestore:import {args.output} --project allspots")

if __name__ == '__main__':
    main()
