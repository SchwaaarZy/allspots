#!/usr/bin/env python3
"""
Script d'orchestration pour import hybride de POIs
Stratégie: 80% OpenStreetMap + 20% Google Places + Data.gouv.fr
"""

import subprocess
import json
import os
import argparse
import time
from typing import List, Dict

# Configuration des villes principales de France
MAJOR_CITIES = {
    'paris': {
        'department': '75',
        'location': '48.8566,2.3522',
        'radius': 25000,
        'use_google': True,  # Ville prioritaire pour Google Places
        'google_limit': 50
    },
    'marseille': {
        'department': '13',
        'location': '43.2965,5.3698',
        'radius': 20000,
        'use_google': True,
        'google_limit': 40
    },
    'lyon': {
        'department': '69',
        'location': '45.7640,4.8357',
        'radius': 20000,
        'use_google': True,
        'google_limit': 40
    },
    'toulouse': {
        'department': '31',
        'location': '43.6047,1.4442',
        'radius': 18000,
        'use_google': True,
        'google_limit': 30
    },
    'nice': {
        'department': '06',
        'location': '43.7102,7.2620',
        'radius': 15000,
        'use_google': True,
        'google_limit': 30
    },
    'nantes': {
        'department': '44',
        'location': '47.2184,-1.5536',
        'radius': 15000,
        'use_google': False,
        'google_limit': 0
    },
    'strasbourg': {
        'department': '67',
        'location': '48.5734,7.7521',
        'radius': 15000,
        'use_google': False,
        'google_limit': 0
    },
    'montpellier': {
        'department': '34',
        'location': '43.6108,3.8767',
        'radius': 15000,
        'use_google': False,
        'google_limit': 0
    },
    'bordeaux': {
        'department': '33',
        'location': '44.8378,-0.5792',
        'radius': 18000,
        'use_google': True,
        'google_limit': 30
    },
    'lille': {
        'department': '59',
        'location': '50.6292,3.0573',
        'radius': 15000,
        'use_google': False,
        'google_limit': 0
    }
}

CATEGORIES = ['culture', 'nature', 'experienceGustative', 'histoire', 'activites']

def run_osm_import(city: str, config: Dict, category: str) -> str:
    """
    ✅ Importe depuis OpenStreetMap (gratuit, illimité)
    """
    print(f"\n🗺️  OpenStreetMap - {city.capitalize()} / {category}")
    print("=" * 60)
    
    output_file = f"pois_{city}_{category}_osm.json"
    
    cmd = [
        'python3',
        'scripts/import_osm_france.py',
        '--department', config['department'],
        '--category', category,
        '--radius', str(config['radius']),
        '--output', output_file
    ]
    
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        print(result.stdout)
        return output_file
    except subprocess.CalledProcessError as e:
        print(f"❌ Erreur OSM: {e}")
        print(e.stderr)
        return None

def run_google_import(city: str, config: Dict, category: str) -> str:
    """
    🌟 Importe depuis Google Places (quota gratuit 200$/mois)
    """
    if not config['use_google'] or config['google_limit'] == 0:
        return None
    
    print(f"\n📍 Google Places - {city.capitalize()} / {category}")
    print("=" * 60)
    
    output_file = f"pois_{city}_{category}_google.json"
    
    cmd = [
        'python3',
        'scripts/import_google_places.py',
        '--city', city.capitalize(),
        '--location', config['location'],
        '--category', category,
        '--radius', str(config['radius']),
        '--limit', str(config['google_limit']),
        '--output', output_file
    ]
    
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        print(result.stdout)
        return output_file
    except subprocess.CalledProcessError as e:
        print(f"⚠️  Google Places non disponible (probablement pas de clé API)")
        print("   -> Continue avec OSM uniquement")
        return None

def run_datagouv_import(department: str) -> str:
    """
    🇫🇷 Importe depuis Data.gouv.fr (gratuit, données publiques)
    """
    print(f"\n🏛️  Data.gouv.fr - Département {department}")
    print("=" * 60)
    
    output_file = f"pois_dept{department}_datagouv.json"
    
    cmd = [
        'python3',
        'scripts/import_datagouv.py',
        '--dataset', 'all',
        '--department', department,
        '--output', output_file
    ]
    
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        print(result.stdout)
        return output_file
    except subprocess.CalledProcessError as e:
        print(f"⚠️  Data.gouv.fr non disponible")
        return None

def merge_json_files(files: List[str], output: str):
    """
    Fusionne plusieurs fichiers JSON en un seul
    """
    all_pois = []
    seen_names = set()  # Dédupliquer par nom + position approximative
    
    for file in files:
        if not file or not os.path.exists(file):
            continue
        
        try:
            with open(file, 'r', encoding='utf-8') as f:
                pois = json.load(f)
                
                for poi in pois:
                    # Clé de déduplication: nom + ville + lat/lng arrondi
                    name = poi.get('name', '').lower().strip()
                    lat = round(poi['location']['_latitude'], 4)
                    lng = round(poi['location']['_longitude'], 4)
                    key = f"{name}_{lat}_{lng}"
                    
                    if key not in seen_names:
                        seen_names.add(key)
                        all_pois.append(poi)
                    else:
                        # Si c'est Google Places, on préfère sa version (meilleures photos)
                        if poi.get('source') == 'google_places':
                            # Remplacer la version OSM par la version Google
                            for i, existing in enumerate(all_pois):
                                existing_key = f"{existing.get('name', '').lower().strip()}_{round(existing['location']['_latitude'], 4)}_{round(existing['location']['_longitude'], 4)}"
                                if existing_key == key:
                                    all_pois[i] = poi
                                    break
        except Exception as e:
            print(f"⚠️  Erreur lecture {file}: {e}")
    
    # Sauvegarder le fichier fusionné
    with open(output, 'w', encoding='utf-8') as f:
        json.dump(all_pois, f, ensure_ascii=False, indent=2)
    
    return len(all_pois)

def main():
    parser = argparse.ArgumentParser(
        description='Import hybride: 80% OSM + 20% Google Places + Data.gouv.fr'
    )
    parser.add_argument('--cities', nargs='+', 
                        choices=list(MAJOR_CITIES.keys()) + ['all'],
                        default=['all'],
                        help='Villes à importer (défaut: all)')
    parser.add_argument('--categories', nargs='+',
                        choices=CATEGORIES + ['all'],
                        default=['all'],
                        help='Catégories à importer (défaut: all)')
    parser.add_argument('--skip-osm', action='store_true',
                        help='Ignorer OpenStreetMap')
    parser.add_argument('--skip-google', action='store_true',
                        help='Ignorer Google Places')
    parser.add_argument('--skip-datagouv', action='store_true',
                        help='Ignorer Data.gouv.fr')
    parser.add_argument('--output', default='pois_france_complet.json',
                        help='Fichier de sortie final')
    
    args = parser.parse_args()
    
    # Déterminer les villes et catégories
    cities = list(MAJOR_CITIES.keys()) if 'all' in args.cities else args.cities
    categories = CATEGORIES if 'all' in args.categories else args.categories
    
    print("🇫🇷 IMPORT HYBRIDE DE POIS POUR LA FRANCE")
    print("=" * 60)
    print(f"📍 Villes: {', '.join([c.capitalize() for c in cities])}")
    print(f"📂 Catégories: {', '.join(categories)}")
    print(f"\n🎯 Stratégie:")
    print(f"   • OpenStreetMap: {'❌ DÉSACTIVÉ' if args.skip_osm else '✅ ACTIVÉ (80%)'}")
    print(f"   • Google Places: {'❌ DÉSACTIVÉ' if args.skip_google else '✅ ACTIVÉ (20%)'}")
    print(f"   • Data.gouv.fr: {'❌ DÉSACTIVÉ' if args.skip_datagouv else '✅ ACTIVÉ'}")
    print("\n" + "=" * 60)
    
    all_files = []
    total_google_requests = 0
    
    # Pour chaque ville
    for city in cities:
        config = MAJOR_CITIES[city]
        print(f"\n\n🌆 VILLE: {city.upper()}")
        print("=" * 60)
        
        # Pour chaque catégorie
        for category in categories:
            
            # 1. OpenStreetMap (base gratuite, 80%)
            if not args.skip_osm:
                osm_file = run_osm_import(city, config, category)
                if osm_file:
                    all_files.append(osm_file)
                time.sleep(2)  # Rate limiting
            
            # 2. Google Places (qualité, 20%, seulement villes majeures)
            if not args.skip_google and config['use_google']:
                google_file = run_google_import(city, config, category)
                if google_file:
                    all_files.append(google_file)
                    total_google_requests += config['google_limit']
                time.sleep(2)  # Rate limiting
        
        # 3. Data.gouv.fr (monuments, musées - une seule fois par département)
        if not args.skip_datagouv:
            datagouv_file = run_datagouv_import(config['department'])
            if datagouv_file:
                all_files.append(datagouv_file)
        
        print(f"\n⏳ Pause de 60s avant ville suivante (respect des limites API)...")
        time.sleep(60)
    
    # Fusion de tous les fichiers
    print(f"\n\n🔄 FUSION DES DONNÉES")
    print("=" * 60)
    print(f"📁 {len(all_files)} fichiers à fusionner")
    
    total_pois = merge_json_files(all_files, args.output)
    
    # Résumé final
    print(f"\n\n✅ IMPORT TERMINÉ")
    print("=" * 60)
    print(f"📊 Total: {total_pois} POIs uniques")
    print(f"📄 Fichier: {args.output}")
    print(f"\n💰 Coût estimé:")
    print(f"   • OpenStreetMap: GRATUIT")
    print(f"   • Google Places: ~{total_google_requests * 0.017:.2f}$ (sur quota 200$/mois)")
    print(f"   • Data.gouv.fr: GRATUIT")
    print(f"   • TOTAL: ~{total_google_requests * 0.017:.2f}$ (100% dans quota gratuit)")
    
    print(f"\n🔥 Import dans Firestore:")
    print(f"   firebase firestore:import {args.output} --project allspots")
    
    print(f"\n🧹 Nettoyage des fichiers temporaires:")
    print(f"   rm pois_*_osm.json pois_*_google.json pois_*_datagouv.json")

if __name__ == '__main__':
    main()
