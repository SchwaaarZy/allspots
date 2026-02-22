#!/usr/bin/env python3
"""
Convertisseur GPX universel → Format Firestore
Compatible avec: Visorando, Openrunner, Decathlon, AllTrails, Komoot, etc.
"""

import xml.etree.ElementTree as ET
import json
import os
import argparse
from typing import List, Dict, Optional, Tuple
import math
from datetime import datetime

# Namespaces GPX standards
GPX_NS = {
    'gpx': 'http://www.topografix.com/GPX/1/1',
    'gpx10': 'http://www.topografix.com/GPX/1/0',
    'gpxtpx': 'http://www.garmin.com/xmlschemas/TrackPointExtension/v1',
    'gpxx': 'http://www.garmin.com/xmlschemas/GpxExtensions/v3'
}

def parse_gpx_file(gpx_file: str) -> Optional[Dict]:
    """
    Parse un fichier GPX et extrait toutes les informations
    """
    try:
        tree = ET.parse(gpx_file)
        root = tree.getroot()
        
        # Détecter le namespace
        ns = root.tag.split('}')[0].strip('{')
        if ns:
            GPX_NS['default'] = ns
        else:
            ns = GPX_NS['gpx']
        
        # Extraire les métadonnées
        metadata = {}
        
        # Nom de la trace
        name_elem = root.find(f'.//{{{ns}}}trk/{{{ns}}}name') or root.find(f'.//{{{ns}}}rte/{{{ns}}}name')
        if name_elem is not None:
            metadata['name'] = name_elem.text
        else:
            # Fallback sur le nom du fichier
            metadata['name'] = os.path.splitext(os.path.basename(gpx_file))[0]
        
        # Description
        desc_elem = root.find(f'.//{{{ns}}}trk/{{{ns}}}desc') or root.find(f'.//{{{ns}}}rte/{{{ns}}}desc')
        if desc_elem is not None:
            metadata['description'] = desc_elem.text
        
        # Lien/URL
        link_elem = root.find(f'.//{{{ns}}}trk/{{{ns}}}link') or root.find(f'.//{{{ns}}}metadata/{{{ns}}}link')
        if link_elem is not None:
            metadata['url'] = link_elem.get('href', '')
        
        # Extraire les points (track points)
        coordinates = []
        elevations = []
        
        # Essayer track
        for trkpt in root.findall(f'.//{{{ns}}}trk/{{{ns}}}trkseg/{{{ns}}}trkpt'):
            lat = float(trkpt.get('lat'))
            lon = float(trkpt.get('lon'))
            coordinates.append({'lat': lat, 'lng': lon})
            
            # Élévation
            ele_elem = trkpt.find(f'{{{ns}}}ele')
            if ele_elem is not None and ele_elem.text:
                elevations.append(float(ele_elem.text))
        
        # Si pas de track, essayer route
        if not coordinates:
            for rtept in root.findall(f'.//{{{ns}}}rte/{{{ns}}}rtept'):
                lat = float(rtept.get('lat'))
                lon = float(rtept.get('lon'))
                coordinates.append({'lat': lat, 'lng': lon})
                
                ele_elem = rtept.find(f'{{{ns}}}ele')
                if ele_elem is not None and ele_elem.text:
                    elevations.append(float(ele_elem.text))
        
        if not coordinates:
            print(f"  ⚠️  Aucune coordonnée trouvée dans {gpx_file}")
            return None
        
        metadata['coordinates'] = coordinates
        metadata['elevations'] = elevations
        
        # Extraire les waypoints (points d'intérêt)
        waypoints = []
        for wpt in root.findall(f'.//{{{ns}}}wpt'):
            lat = float(wpt.get('lat'))
            lon = float(wpt.get('lon'))
            
            name_elem = wpt.find(f'{{{ns}}}name')
            desc_elem = wpt.find(f'{{{ns}}}desc')
            
            waypoint = {
                'lat': lat,
                'lng': lon,
                'name': name_elem.text if name_elem is not None else 'Waypoint',
                'description': desc_elem.text if desc_elem is not None else ''
            }
            waypoints.append(waypoint)
        
        metadata['waypoints'] = waypoints
        
        return metadata
    
    except Exception as e:
        print(f"  ❌ Erreur parse GPX {gpx_file}: {e}")
        return None

def calculate_distance(coords: List[Dict]) -> float:
    """
    Calcule la distance totale d'un itinéraire (formule de Haversine)
    Retourne la distance en mètres
    """
    if len(coords) < 2:
        return 0.0
    
    total_distance = 0.0
    R = 6371000  # Rayon de la Terre en mètres
    
    for i in range(len(coords) - 1):
        lat1, lng1 = coords[i]['lat'], coords[i]['lng']
        lat2, lng2 = coords[i + 1]['lat'], coords[i + 1]['lng']
        
        # Conversion en radians
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        delta_phi = math.radians(lat2 - lat1)
        delta_lambda = math.radians(lng2 - lng1)
        
        # Formule de Haversine
        a = math.sin(delta_phi / 2) ** 2 + \
            math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        
        total_distance += R * c
    
    return total_distance

def calculate_elevation_gain(elevations: List[float]) -> Tuple[float, float]:
    """
    Calcule le dénivelé positif et négatif
    Retourne (D+, D-) en mètres
    """
    if len(elevations) < 2:
        return 0.0, 0.0
    
    elevation_gain = 0.0
    elevation_loss = 0.0
    
    for i in range(len(elevations) - 1):
        diff = elevations[i + 1] - elevations[i]
        if diff > 0:
            elevation_gain += diff
        else:
            elevation_loss += abs(diff)
    
    return elevation_gain, elevation_loss

def convert_to_firestore_format(gpx_data: Dict, category: str, source: str, city: str = None) -> Dict:
    """
    Convertit les données GPX au format Firestore
    """
    coords = gpx_data['coordinates']
    elevations = gpx_data.get('elevations', [])
    
    # Position: point de départ
    start_lat = coords[0]['lat']
    start_lng = coords[0]['lng']
    
    # Calculer les statistiques
    distance = calculate_distance(coords)
    elevation_gain, elevation_loss = calculate_elevation_gain(elevations) if elevations else (0.0, 0.0)
    
    # Estimer la durée (formule Naismith: 4km/h + 10min/100m D+)
    base_time = distance / 1000 / 4  # heures
    elevation_time = elevation_gain / 100 * 10 / 60  # heures
    duration = base_time + elevation_time
    
    # Nom et description
    name = gpx_data.get('name', 'Itinéraire sans nom')
    
    description = gpx_data.get('description', '')
    if not description:
        # Construire une description automatique
        parts = [f"{distance/1000:.1f} km"]
        if elevation_gain > 0:
            parts.append(f"D+ {elevation_gain:.0f}m")
        if duration > 0:
            parts.append(f"{duration:.1f}h")
        description = " • ".join(parts)
    
    # Deviner la ville si non fournie
    if not city:
        # Essayer d'extraire de la description ou du nom
        city = "Non spécifiée"
        # TODO: Reverse geocoding si nécessaire
    
    # Construire le POI
    poi = {
        'name': name.strip(),
        'description': description.strip(),
        'location': {
            '_latitude': start_lat,
            '_longitude': start_lng
        },
        'category': category,
        'city': city,
        'images': [],  # Pas d'images dans GPX standard
        'rating': 0.0,
        'website': gpx_data.get('url', ''),
        'isPublic': True,
        'isValidated': True,
        'source': f'{source}_gpx',
        'createdAt': {'_seconds': int(datetime.now().timestamp()), '_nanoseconds': 0}
    }
    
    # Métadonnées outdoor
    poi['distance_km'] = round(distance / 1000, 2)
    poi['elevation_gain_m'] = round(elevation_gain, 0)
    poi['elevation_loss_m'] = round(elevation_loss, 0)
    poi['duration_hours'] = round(duration, 2)
    
    # Coordonnées de l'itinéraire (limitées à 100 points pour Firestore)
    step = max(1, len(coords) // 100)
    poi['route_coordinates'] = coords[::step]
    
    # Waypoints (points d'intérêt sur l'itinéraire)
    if gpx_data.get('waypoints'):
        poi['waypoints'] = gpx_data['waypoints']
    
    return poi

def main():
    parser = argparse.ArgumentParser(
        description='Convertir des fichiers GPX en POIs Firestore'
    )
    parser.add_argument('--input-folder', required=True,
                        help='Dossier contenant les fichiers GPX')
    parser.add_argument('--output', default='pois_gpx_import.json',
                        help='Fichier de sortie JSON')
    parser.add_argument('--category', 
                        choices=['nature', 'activites', 'culture', 'histoire', 'experienceGustative'],
                        default='nature',
                        help='Catégorie pour ces POIs')
    parser.add_argument('--source', default='gpx',
                        help='Source des données (ex: visorando, openrunner, decathlon)')
    parser.add_argument('--city', help='Nom de la ville/région (optionnel)')
    parser.add_argument('--recursive', action='store_true',
                        help='Chercher récursivement dans les sous-dossiers')
    
    args = parser.parse_args()
    
    print("🗺️  Conversion GPX → Firestore")
    print("=" * 60)
    print(f"Dossier: {args.input_folder}")
    print(f"Catégorie: {args.category}")
    print(f"Source: {args.source}")
    print()
    
    # Trouver tous les fichiers GPX
    gpx_files = []
    if args.recursive:
        for root, dirs, files in os.walk(args.input_folder):
            for file in files:
                if file.lower().endswith('.gpx'):
                    gpx_files.append(os.path.join(root, file))
    else:
        for file in os.listdir(args.input_folder):
            if file.lower().endswith('.gpx'):
                gpx_files.append(os.path.join(args.input_folder, file))
    
    if not gpx_files:
        print(f"❌ Aucun fichier GPX trouvé dans {args.input_folder}")
        return
    
    print(f"📁 {len(gpx_files)} fichiers GPX trouvés\n")
    
    # Parser et convertir
    firestore_pois = []
    
    for i, gpx_file in enumerate(gpx_files):
        print(f"{i+1}/{len(gpx_files)} - {os.path.basename(gpx_file)}")
        
        gpx_data = parse_gpx_file(gpx_file)
        if not gpx_data:
            continue
        
        poi = convert_to_firestore_format(
            gpx_data,
            args.category,
            args.source,
            args.city
        )
        
        firestore_pois.append(poi)
        
        # Afficher les stats
        print(f"   ✅ {poi['distance_km']} km • D+ {poi['elevation_gain_m']}m • {poi['duration_hours']}h")
    
    # Sauvegarde
    print(f"\n💾 Sauvegarde de {len(firestore_pois)} POIs...")
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(firestore_pois, f, ensure_ascii=False, indent=2)
    
    print(f"\n✅ Terminé ! {len(firestore_pois)} POIs exportés")
    print(f"📄 Fichier: {args.output}")
    print(f"💰 Coût: GRATUIT")
    print("\n🔥 Import dans Firestore:")
    print(f"   firebase firestore:import {args.output} --project allspots")
    
    # Statistiques
    total_distance = sum(poi['distance_km'] for poi in firestore_pois)
    total_elevation = sum(poi['elevation_gain_m'] for poi in firestore_pois)
    
    print(f"\n📊 Statistiques totales:")
    print(f"   Distance cumulée: {total_distance:.1f} km")
    print(f"   Dénivelé cumulé: {total_elevation:.0f} m")
    print(f"   Moyenne: {total_distance/len(firestore_pois):.1f} km/itinéraire")

if __name__ == '__main__':
    main()
