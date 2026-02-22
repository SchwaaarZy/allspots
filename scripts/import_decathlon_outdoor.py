#!/usr/bin/env python3
"""
Script d'importation de POIs depuis Decathlon Outdoor
Source: Itinéraires de randonnée, vélo, trail, etc.
"""

import requests
import json
import time
import argparse
from typing import List, Dict, Optional

# API Decathlon Outdoor (à vérifier)
# Note: Cette API peut nécessiter une clé ou être restreinte
DECATHLON_API_BASE = "https://www.decathlon-outdoor.com/api"

# Mapping des activités Decathlon vers catégories AllSpots
ACTIVITY_MAPPING = {
    'hiking': 'nature',
    'trail': 'activites',
    'cycling': 'activites',
    'mountain-bike': 'activites',
    'climbing': 'activites',
    'via-ferrata': 'activites',
    'snowshoeing': 'nature',
    'skiing': 'activites',
    'running': 'activites',
    'walking': 'nature'
}

def search_decathlon_routes(lat: float, lng: float, radius: int = 20000, activity: str = 'hiking') -> List[Dict]:
    """
    Recherche des itinéraires Decathlon Outdoor autour d'une position
    
    Args:
        lat: Latitude
        lng: Longitude
        radius: Rayon en mètres
        activity: Type d'activité (hiking, trail, cycling, etc.)
    
    Returns:
        Liste d'itinéraires
    """
    print(f"🔍 Recherche Decathlon Outdoor: {activity}")
    print(f"   📍 Position: {lat}, {lng}")
    print(f"   📏 Rayon: {radius}m")
    
    # Méthode 1: API publique (si disponible)
    try:
        url = f"{DECATHLON_API_BASE}/routes/search"
        params = {
            'lat': lat,
            'lng': lng,
            'radius': radius / 1000,  # Conversion en km
            'activity': activity,
            'limit': 100
        }
        
        response = requests.get(url, params=params, timeout=30)
        
        if response.status_code == 200:
            data = response.json()
            routes = data.get('routes', data.get('results', []))
            print(f"   ✅ Trouvé {len(routes)} itinéraires")
            return routes
        else:
            print(f"   ⚠️  API non disponible (status {response.status_code})")
            return []
    
    except Exception as e:
        print(f"   ⚠️  Erreur API: {e}")
        print("   💡 Alternative: Import manuel depuis l'app Decathlon Outdoor")
        return []

def search_decathlon_by_region(region: str, activity: str = 'hiking') -> List[Dict]:
    """
    Recherche par région/département
    """
    print(f"🔍 Recherche Decathlon Outdoor: {region}")
    
    try:
        # Possibilité d'utiliser le sitemap ou le moteur de recherche
        url = f"{DECATHLON_API_BASE}/routes"
        params = {
            'region': region,
            'activity': activity,
            'country': 'FR',
            'limit': 100
        }
        
        response = requests.get(url, params=params, timeout=30)
        
        if response.status_code == 200:
            data = response.json()
            routes = data.get('routes', data.get('results', []))
            print(f"   ✅ Trouvé {len(routes)} itinéraires")
            return routes
        else:
            print(f"   ⚠️  API non disponible")
            return []
    
    except Exception as e:
        print(f"   ⚠️  Erreur: {e}")
        return []

def parse_manual_export(json_file: str) -> List[Dict]:
    """
    Parse un export JSON manuel depuis l'app Decathlon Outdoor
    
    Instructions pour export manuel:
    1. Ouvrir l'app Decathlon Outdoor
    2. Aller dans "Mes itinéraires" ou "Explorer"
    3. Exporter/Partager au format GPX ou JSON
    4. Convertir en JSON si nécessaire
    """
    print(f"📥 Lecture du fichier d'export: {json_file}")
    
    try:
        with open(json_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        # Détecter le format
        if isinstance(data, list):
            routes = data
        elif isinstance(data, dict):
            routes = data.get('routes', data.get('itineraires', data.get('tracks', [data])))
        else:
            routes = []
        
        print(f"   ✅ {len(routes)} itinéraires chargés")
        return routes
    
    except Exception as e:
        print(f"   ❌ Erreur lecture: {e}")
        return []

def convert_to_firestore_format(routes: List[Dict], source: str = 'decathlon') -> List[Dict]:
    """
    Convertit les itinéraires Decathlon au format Firestore
    """
    firestore_pois = []
    
    for idx, route in enumerate(routes):
        try:
            # Extraire les informations selon le format
            name = route.get('name', route.get('title', route.get('nom', 'Sans nom')))
            
            # Position: début de l'itinéraire
            # Format possible 1: lat/lng directs
            lat = route.get('lat', route.get('latitude'))
            lng = route.get('lng', route.get('longitude'))
            
            # Format possible 2: start_point object
            if not lat or not lng:
                start = route.get('start_point', route.get('depart', route.get('start', {})))
                lat = start.get('lat', start.get('latitude'))
                lng = start.get('lng', start.get('longitude'))
            
            # Format possible 3: coordinates array (premier point)
            if not lat or not lng:
                coords = route.get('coordinates', route.get('points', []))
                if coords and len(coords) > 0:
                    first_point = coords[0]
                    if isinstance(first_point, dict):
                        lat = first_point.get('lat', first_point.get('latitude'))
                        lng = first_point.get('lng', first_point.get('longitude'))
                    elif isinstance(first_point, (list, tuple)) and len(first_point) >= 2:
                        lat, lng = first_point[0], first_point[1]
            
            if not lat or not lng:
                print(f"  ⚠️  Pas de coordonnées pour: {name}")
                continue
            
            # Description
            description = route.get('description', route.get('summary', ''))
            if not description:
                # Construire une description à partir des stats
                distance = route.get('distance', route.get('length', 0))
                elevation = route.get('elevation_gain', route.get('denivele', 0))
                duration = route.get('duration', route.get('duree', 0))
                
                parts = []
                if distance:
                    parts.append(f"{distance/1000:.1f} km")
                if elevation:
                    parts.append(f"D+ {elevation}m")
                if duration:
                    hours = duration / 3600
                    parts.append(f"{hours:.1f}h")
                
                description = " • ".join(parts) if parts else "Itinéraire outdoor"
            
            # Catégorie basée sur l'activité
            activity = route.get('activity', route.get('type', 'hiking')).lower()
            category = ACTIVITY_MAPPING.get(activity, 'activites')
            
            # Ville/région
            city = route.get('city', route.get('commune', route.get('location', 'Non spécifiée')))
            if isinstance(city, dict):
                city = city.get('name', 'Non spécifiée')
            
            # Images
            images = []
            # Format 1: champ direct
            if route.get('image'):
                images.append(route['image'])
            if route.get('cover_image'):
                images.append(route['cover_image'])
            # Format 2: array
            route_images = route.get('images', route.get('photos', []))
            if isinstance(route_images, list):
                images.extend(route_images[:5])
            elif isinstance(route_images, str):
                images.append(route_images)
            
            # Nettoyer les URLs d'images
            images = [img if img.startswith('http') else f"https://www.decathlon-outdoor.com{img}" 
                      for img in images if img]
            
            # Construire le POI
            poi = {
                'name': str(name).strip(),
                'description': str(description).strip(),
                'location': {
                    '_latitude': float(lat),
                    '_longitude': float(lng)
                },
                'category': category,
                'city': str(city).strip(),
                'images': images,
                'rating': route.get('rating', route.get('note', 0.0)),
                'website': route.get('url', route.get('link', '')),
                'isPublic': True,
                'isValidated': True,
                'source': f'{source}_outdoor',
                'createdAt': {'_seconds': int(time.time()), '_nanoseconds': 0}
            }
            
            # Métadonnées spécifiques outdoor
            if route.get('distance'):
                poi['distance_km'] = round(route['distance'] / 1000, 2)
            if route.get('elevation_gain'):
                poi['elevation_gain_m'] = route['elevation_gain']
            if route.get('duration'):
                poi['duration_hours'] = round(route['duration'] / 3600, 2)
            if route.get('difficulty'):
                poi['difficulty'] = route['difficulty']
            
            # Coordonnées complètes de l'itinéraire (pour affichage sur carte)
            if route.get('coordinates'):
                poi['route_coordinates'] = route['coordinates'][:100]  # Limiter la taille
            
            firestore_pois.append(poi)
            
            if (idx + 1) % 10 == 0:
                print(f"  📊 {idx + 1}/{len(routes)} convertis...")
        
        except Exception as e:
            print(f"  ⚠️  Erreur itinéraire {idx}: {e}")
            continue
    
    return firestore_pois

def main():
    parser = argparse.ArgumentParser(
        description='Importer des itinéraires depuis Decathlon Outdoor'
    )
    parser.add_argument('--method', choices=['api', 'manual', 'region'], default='manual',
                        help='Méthode d\'import (api=API, manual=fichier JSON, region=par région)')
    parser.add_argument('--file', help='Fichier JSON d\'export manuel')
    parser.add_argument('--location', help='Coordonnées "lat,lng" pour recherche API')
    parser.add_argument('--region', help='Nom de région (ex: "Alpes", "Pyrénées")')
    parser.add_argument('--activity', default='hiking',
                        choices=list(ACTIVITY_MAPPING.keys()),
                        help='Type d\'activité')
    parser.add_argument('--radius', type=int, default=50000,
                        help='Rayon de recherche en mètres (défaut: 50km)')
    parser.add_argument('--output', default='pois_decathlon_import.json',
                        help='Fichier de sortie JSON')
    
    args = parser.parse_args()
    
    print("🏔️  Import Decathlon Outdoor")
    print("=" * 60)
    print(f"Méthode: {args.method}")
    print(f"Activité: {args.activity}")
    print()
    
    routes = []
    
    # Méthode 1: API (si disponible)
    if args.method == 'api':
        if not args.location:
            print("❌ --location requis pour méthode API")
            return
        
        lat, lng = map(float, args.location.split(','))
        routes = search_decathlon_routes(lat, lng, args.radius, args.activity)
    
    # Méthode 2: Export manuel
    elif args.method == 'manual':
        if not args.file:
            print("❌ --file requis pour méthode manual")
            print("\n💡 Instructions:")
            print("   1. Ouvrir https://www.decathlon-outdoor.com")
            print("   2. Explorer les itinéraires de votre région")
            print("   3. Exporter les données (via DevTools si nécessaire)")
            print("   4. Réexécuter avec --file export.json")
            return
        
        routes = parse_manual_export(args.file)
    
    # Méthode 3: Par région
    elif args.method == 'region':
        if not args.region:
            print("❌ --region requis")
            return
        
        routes = search_decathlon_by_region(args.region, args.activity)
    
    if not routes:
        print("\n❌ Aucun itinéraire trouvé")
        print("\n💡 Solutions alternatives:")
        print("   1. Export manuel depuis l'app Decathlon Outdoor")
        print("   2. Utiliser AllTrails, Visorando, ou Openrunner")
        print("   3. Se concentrer sur OpenStreetMap pour les sentiers")
        return
    
    # Conversion au format Firestore
    print(f"\n🔄 Conversion de {len(routes)} itinéraires...")
    firestore_pois = convert_to_firestore_format(routes, 'decathlon')
    
    # Sauvegarde
    print(f"\n💾 Sauvegarde dans {args.output}...")
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(firestore_pois, f, ensure_ascii=False, indent=2)
    
    print(f"\n✅ Terminé ! {len(firestore_pois)} POIs exportés")
    print(f"📄 Fichier: {args.output}")
    print(f"💰 Coût: GRATUIT (données communautaires)")
    print("\n🔥 Import dans Firestore:")
    print(f"   firebase firestore:import {args.output} --project allspots")
    
    # Statistiques
    print("\n📊 Répartition par catégorie:")
    categories = {}
    for poi in firestore_pois:
        cat = poi.get('category', 'unknown')
        categories[cat] = categories.get(cat, 0) + 1
    
    for cat, count in sorted(categories.items()):
        print(f"   {cat}: {count} itinéraires")

if __name__ == '__main__':
    main()
