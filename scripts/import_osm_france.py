#!/usr/bin/env python3
"""
Script pour importer les POIs d'OpenStreetMap dans Firestore
Usage: python import_osm_france.py --department 75 --category culture
"""

import requests
import time
import argparse
from datetime import datetime

# Départements français avec leurs coordonnées (centre)
DEPARTMENTS = {
    "75": {"name": "Paris", "lat": 48.8566, "lng": 2.3522},
    "13": {"name": "Bouches-du-Rhône", "lat": 43.2965, "lng": 5.3698},
    "69": {"name": "Rhône", "lat": 45.7640, "lng": 4.8357},
    "33": {"name": "Gironde", "lat": 44.8378, "lng": -0.5792},
    "06": {"name": "Alpes-Maritimes", "lat": 43.7102, "lng": 7.2620},
    # Ajoutez d'autres départements...
}

# Mapping des catégories vers les tags OSM
CATEGORY_TAGS = {
    "culture": [
        'tourism="museum"',
        'tourism="gallery"',
        'tourism="artwork"',
        'amenity="theatre"',
        'amenity="cinema"',
    ],
    "nature": [
        'leisure="park"',
        'tourism="viewpoint"',
        'natural="beach"',
        'leisure="garden"',
    ],
    "experienceGustative": [
        'amenity="restaurant"',
        'amenity="cafe"',
        'shop="bakery"',
        'tourism="wine_cellar"',
    ],
    "histoire": [
        'historic="monument"',
        'historic="castle"',
        'historic="memorial"',
        'tourism="attraction"',
    ],
    "activites": [
        'leisure="sports_centre"',
        'tourism="theme_park"',
        'leisure="water_park"',
    ],
}


def build_overpass_query(lat, lng, radius, tags):
    """Construit une requête Overpass API"""
    tag_union = "".join([f"  node[{tag}](around:{radius},{lat},{lng});\n" for tag in tags])
    
    query = f"""
[out:json][timeout:60];
(
{tag_union}
);
out body;
>;
out skel qt;
"""
    return query


def query_overpass(lat, lng, radius, tags):
    """Interroge l'API Overpass"""
    query = build_overpass_query(lat, lng, radius, tags)
    
    print(f"📍 Requête OSM autour de ({lat}, {lng}) rayon {radius}m...")
    
    try:
        response = requests.post(
            "https://overpass-api.de/api/interpreter",
            data=query,
            headers={"Content-Type": "text/plain"},
            timeout=120,
        )
        response.raise_for_status()
        data = response.json()
        return data.get("elements", [])
    except Exception as e:
        print(f"❌ Erreur Overpass: {e}")
        return []


def clean_poi_data(element):
    """Nettoie et formate les données POI"""
    tags = element.get("tags", {})
    
    # Nom
    name = (
        tags.get("name:fr")
        or tags.get("name")
        or tags.get("operator")
        or "POI sans nom"
    )
    
    # Description
    description = (
        tags.get("description")
        or tags.get("note")
        or f"Point d'intérêt: {name}"
    )
    
    # Image
    image = tags.get("image") or tags.get("wikimedia_commons")
    images = [image] if image else []
    
    # Website
    website = tags.get("website") or tags.get("contact:website")
    
    return {
        "id": f"osm_{element['id']}",
        "name": name[:100],  # Limite 100 caractères
        "lat": element["lat"],
        "lng": element["lon"],
        "description": description[:500],  # Limite 500 caractères
        "categoryGroup": "culture",  # À adapter selon les tags
        "categoryItem": tags.get("tourism") or tags.get("amenity") or "other",
        "imageUrls": images,
        "websiteUrl": website,
        "source": "openstreetmap",
        "osmId": element["id"],
        "isPublic": True,
        "isFree": None,
        "pmrAccessible": tags.get("wheelchair") == "yes",
        "kidsFriendly": None,
        "updatedAt": datetime.now().isoformat(),
    }


def save_to_firestore_format(pois, output_file):
    """Sauvegarde au format importable dans Firestore"""
    import json
    
    with open(output_file, "w", encoding="utf-8") as f:
        for poi in pois:
            json.dump(poi, f, ensure_ascii=False)
            f.write("\n")
    
    print(f"✅ {len(pois)} POIs sauvegardés dans {output_file}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--department", required=True, help="Code département (ex: 75)")
    parser.add_argument(
        "--category",
        default="culture",
        choices=list(CATEGORY_TAGS.keys()),
        help="Catégorie de POIs",
    )
    parser.add_argument("--radius", type=int, default=20000, help="Rayon en mètres")
    parser.add_argument("--output", default="pois_import.json", help="Fichier de sortie")
    
    args = parser.parse_args()
    
    if args.department not in DEPARTMENTS:
        print(f"❌ Département {args.department} non supporté")
        return
    
    dept = DEPARTMENTS[args.department]
    tags = CATEGORY_TAGS[args.category]
    
    print(f"\n🗺️  Import OSM pour {dept['name']} ({args.department})")
    print(f"📂 Catégorie: {args.category}")
    print(f"📏 Rayon: {args.radius}m\n")
    
    # Requête Overpass
    elements = query_overpass(dept["lat"], dept["lng"], args.radius, tags)
    
    if not elements:
        print("⚠️  Aucun POI trouvé")
        return
    
    # Nettoyer les données
    pois = []
    for elem in elements:
        if elem.get("type") == "node" and "lat" in elem and "lon" in elem:
            poi = clean_poi_data(elem)
            pois.append(poi)
    
    print(f"📝 {len(pois)} POIs extraits")
    
    # Sauvegarder
    save_to_firestore_format(pois, args.output)
    
    print(f"\n✅ Import terminé!")
    print(f"\n💡 Pour importer dans Firestore:")
    print(f"   firebase firestore:delete spots --all-collections")
    print(f"   firebase firestore:import {args.output}")
    print(f"\n⏱️  Attendez 60s avant la prochaine requête (rate limit OSM)")


if __name__ == "__main__":
    main()
