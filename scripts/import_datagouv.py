#!/usr/bin/env python3
"""
Script d'importation de POIs depuis Data.gouv.fr
Datasets publics français : monuments historiques, musées, équipements culturels
"""

import requests
import json
import time
import argparse
from typing import List, Dict, Optional
import csv
from io import StringIO

# URLs des datasets Data.gouv.fr
DATASETS = {
    'monuments': {
        'url': 'https://data.culture.gouv.fr/api/explore/v2.1/catalog/datasets/liste-des-immeubles-proteges-au-titre-des-monuments-historiques/exports/json',
        'category': 'histoire',
        'name_field': 'tico',
        'description_field': 'ppro',
        'lat_field': 'latitude',
        'lng_field': 'longitude',
        'city_field': 'commune'
    },
    'musees': {
        'url': 'https://data.culture.gouv.fr/api/explore/v2.1/catalog/datasets/liste-et-localisation-des-musees-de-france/exports/json',
        'category': 'culture',
        'name_field': 'nom_officiel',
        'description_field': 'adresse',
        'lat_field': 'latitude',
        'lng_field': 'longitude',
        'city_field': 'commune'
    },
    'equipements': {
        'url': 'https://www.data.gouv.fr/fr/datasets/r/0d8f0f0e-4d5f-4f7e-8c1b-5f3f9e4e3f5e',
        'category': 'activites',
        'name_field': 'nom',
        'description_field': 'type',
        'lat_field': 'latitude',
        'lng_field': 'longitude',
        'city_field': 'commune'
    }
}

def fetch_dataset(dataset_type: str, department: Optional[str] = None) -> List[Dict]:
    """
    Récupère un dataset depuis Data.gouv.fr
    
    Args:
        dataset_type: 'monuments', 'musees' ou 'equipements'
        department: Code département (ex: '75' pour Paris) - optionnel
    
    Returns:
        Liste de POIs
    """
    if dataset_type not in DATASETS:
        print(f"❌ Type de dataset inconnu: {dataset_type}")
        return []
    
    config = DATASETS[dataset_type]
    url = config['url']
    
    print(f"📥 Téléchargement du dataset '{dataset_type}'...")
    print(f"   URL: {url}")
    
    try:
        # Paramètres pour filtrer par département si spécifié
        params = {}
        if department:
            params['refine.departement'] = department
        
        response = requests.get(url, params=params, timeout=60)
        response.raise_for_status()
        
        # Détecter le format de réponse
        content_type = response.headers.get('Content-Type', '')
        
        if 'application/json' in content_type:
            data = response.json()
            
            # Gérer différents formats de réponse
            if isinstance(data, list):
                results = data
            elif isinstance(data, dict):
                # Format OpenDataSoft
                results = data.get('records', [])
                if results and 'fields' in results[0]:
                    results = [r['fields'] for r in results]
                # Format alternatif
                elif 'results' in data:
                    results = data['results']
                else:
                    results = [data]
            else:
                results = []
        
        elif 'text/csv' in content_type:
            # Parser le CSV
            csv_data = response.text
            csv_file = StringIO(csv_data)
            reader = csv.DictReader(csv_file)
            results = list(reader)
        
        else:
            print(f"⚠️  Format inconnu: {content_type}")
            results = []
        
        print(f"   ✅ {len(results)} entrées téléchargées")
        return results
    
    except Exception as e:
        print(f"   ❌ Erreur: {e}")
        return []

def filter_by_department(data: List[Dict], department: str, city_field: str) -> List[Dict]:
    """
    Filtre les données par département
    """
    if not department:
        return data
    
    filtered = []
    for item in data:
        # Essayer différents champs pour le département
        dept_code = item.get('departement', item.get('dep', item.get('code_departement', '')))
        
        # Normaliser le code département
        if isinstance(dept_code, str):
            dept_code = dept_code.zfill(2)  # '5' -> '05'
        
        if str(dept_code) == str(department).zfill(2):
            filtered.append(item)
    
    print(f"   📍 {len(filtered)} entrées pour le département {department}")
    return filtered

def convert_to_firestore_format(data: List[Dict], dataset_type: str) -> List[Dict]:
    """
    Convertit les données Data.gouv.fr au format Firestore
    """
    config = DATASETS[dataset_type]
    firestore_pois = []
    
    for idx, item in enumerate(data):
        try:
            # Extraire les champs selon la configuration
            name = item.get(config['name_field'], '')
            if not name or name == 'None':
                name = item.get('nom', item.get('titre', 'Sans nom'))
            
            # Position
            lat = item.get(config['lat_field'])
            lng = item.get(config['lng_field'])
            
            # Gérer les coordonnées au format texte
            if isinstance(lat, str):
                lat = float(lat.replace(',', '.'))
            if isinstance(lng, str):
                lng = float(lng.replace(',', '.'))
            
            if not lat or not lng:
                continue
            
            # Vérifier les coordonnées valides (France métropolitaine)
            if not (41 <= lat <= 51 and -5 <= lng <= 10):
                continue
            
            # Description
            description = item.get(config['description_field'], '')
            if not description or description == 'None':
                description = item.get('adresse', item.get('adresse_complete', ''))
            
            # Ville
            city = item.get(config['city_field'], item.get('ville', 'Non spécifiée'))
            
            # Images (souvent absentes dans data.gouv.fr)
            images = []
            image_url = item.get('image', item.get('illustration', ''))
            if image_url and image_url != 'None':
                images.append(image_url)
            
            # Construction du POI
            poi = {
                'name': str(name).strip(),
                'description': str(description).strip(),
                'location': {
                    '_latitude': float(lat),
                    '_longitude': float(lng)
                },
                'category': config['category'],
                'city': str(city).strip(),
                'images': images,
                'rating': 0.0,
                'website': item.get('url', item.get('site_internet', '')),
                'phone': item.get('telephone', ''),
                'isPublic': True,
                'isValidated': True,
                'source': f'datagouv_{dataset_type}',
                'createdAt': {'_seconds': int(time.time()), '_nanoseconds': 0}
            }
            
            # Champs spécifiques aux monuments
            if dataset_type == 'monuments':
                poi['protection_type'] = item.get('protection', '')
                poi['historical_period'] = item.get('siecle', '')
            
            # Champs spécifiques aux musées
            if dataset_type == 'musees':
                poi['museum_type'] = item.get('type_musee', '')
                poi['collection'] = item.get('themes', '')
            
            firestore_pois.append(poi)
            
        except Exception as e:
            print(f"  ⚠️  Erreur ligne {idx}: {e}")
            continue
    
    return firestore_pois

def main():
    parser = argparse.ArgumentParser(
        description='Importer des POIs depuis Data.gouv.fr (datasets publics)'
    )
    parser.add_argument('--dataset', required=True, 
                        choices=['monuments', 'musees', 'equipements', 'all'],
                        help='Type de dataset à importer')
    parser.add_argument('--department', help='Code département (ex: 75 pour Paris)')
    parser.add_argument('--output', default='pois_datagouv_import.json',
                        help='Fichier de sortie JSON')
    
    args = parser.parse_args()
    
    print(f"🇫🇷 Import Data.gouv.fr")
    print(f"📂 Dataset: {args.dataset}")
    if args.department:
        print(f"📍 Département: {args.department}")
    print()
    
    all_pois = []
    
    # Déterminer quels datasets importer
    datasets_to_import = DATASETS.keys() if args.dataset == 'all' else [args.dataset]
    
    for dataset_type in datasets_to_import:
        print(f"\n📊 Traitement: {dataset_type}")
        print("=" * 50)
        
        # Télécharger les données
        data = fetch_dataset(dataset_type, args.department)
        
        if not data:
            print(f"⚠️  Aucune donnée pour {dataset_type}")
            continue
        
        # Filtrer par département si nécessaire
        if args.department:
            config = DATASETS[dataset_type]
            data = filter_by_department(data, args.department, config['city_field'])
        
        # Convertir au format Firestore
        print(f"🔄 Conversion au format Firestore...")
        pois = convert_to_firestore_format(data, dataset_type)
        print(f"   ✅ {len(pois)} POIs convertis")
        
        all_pois.extend(pois)
    
    # Sauvegarde
    print(f"\n💾 Sauvegarde de {len(all_pois)} POIs dans {args.output}...")
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(all_pois, f, ensure_ascii=False, indent=2)
    
    print(f"\n✅ Terminé ! {len(all_pois)} POIs exportés")
    print(f"📄 Fichier: {args.output}")
    print(f"💰 Coût: GRATUIT (données publiques)")
    print("\n🔥 Import dans Firestore:")
    print(f"   firebase firestore:import {args.output} --project allspots")
    
    # Statistiques par catégorie
    print("\n📊 Répartition par catégorie:")
    categories = {}
    for poi in all_pois:
        cat = poi.get('category', 'unknown')
        categories[cat] = categories.get(cat, 0) + 1
    
    for cat, count in sorted(categories.items()):
        print(f"   {cat}: {count} POIs")

if __name__ == '__main__':
    main()
