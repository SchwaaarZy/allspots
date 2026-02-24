#!/usr/bin/env python3
"""
Script pour importer les POIs d'OpenStreetMap dans Firestore
Usage: python import_osm_france.py --department 75 --category culture
"""

import requests
import time
import argparse
import json
from datetime import datetime

# Jeu complet embarque (101 departements) pour etre autonome
_EMBEDDED_DEPARTMENTS_JSON = """
{
    "01": {
        "name": "Ain",
        "lat": 46.2027,
        "lng": 5.2469,
        "zone": "metro"
    },
    "02": {
        "name": "Aisne",
        "lat": 49.8475,
        "lng": 3.279,
        "zone": "metro"
    },
    "03": {
        "name": "Allier",
        "lat": 46.3428,
        "lng": 2.608,
        "zone": "metro"
    },
    "04": {
        "name": "Alpes-de-Haute-Provence",
        "lat": 43.8293,
        "lng": 5.7896,
        "zone": "metro"
    },
    "05": {
        "name": "Hautes-Alpes",
        "lat": 44.5797,
        "lng": 6.0616,
        "zone": "metro"
    },
    "06": {
        "name": "Alpes-Maritimes",
        "lat": 43.7032,
        "lng": 7.2528,
        "zone": "metro"
    },
    "07": {
        "name": "Ardèche",
        "lat": 45.2449,
        "lng": 4.6419,
        "zone": "metro"
    },
    "08": {
        "name": "Ardennes",
        "lat": 49.7802,
        "lng": 4.7304,
        "zone": "metro"
    },
    "09": {
        "name": "Ariège",
        "lat": 43.1278,
        "lng": 1.6168,
        "zone": "metro"
    },
    "10": {
        "name": "Aube",
        "lat": 48.2924,
        "lng": 4.0761,
        "zone": "metro"
    },
    "11": {
        "name": "Aude",
        "lat": 43.1493,
        "lng": 3.0337,
        "zone": "metro"
    },
    "12": {
        "name": "Aveyron",
        "lat": 44.3591,
        "lng": 2.5699,
        "zone": "metro"
    },
    "13": {
        "name": "Bouches-du-Rhône",
        "lat": 43.2803,
        "lng": 5.3806,
        "zone": "metro"
    },
    "14": {
        "name": "Calvados",
        "lat": 49.1846,
        "lng": -0.3722,
        "zone": "metro"
    },
    "15": {
        "name": "Cantal",
        "lat": 44.9281,
        "lng": 2.4416,
        "zone": "metro"
    },
    "16": {
        "name": "Charente",
        "lat": 45.6458,
        "lng": 0.145,
        "zone": "metro"
    },
    "17": {
        "name": "Charente-Maritime",
        "lat": 46.162,
        "lng": -1.1765,
        "zone": "metro"
    },
    "18": {
        "name": "Cher",
        "lat": 47.078,
        "lng": 2.3983,
        "zone": "metro"
    },
    "19": {
        "name": "Corrèze",
        "lat": 45.145,
        "lng": 1.5144,
        "zone": "metro"
    },
    "21": {
        "name": "Côte-d'Or",
        "lat": 47.3319,
        "lng": 5.0322,
        "zone": "metro"
    },
    "22": {
        "name": "Côtes-d'Armor",
        "lat": 48.5108,
        "lng": -2.7657,
        "zone": "metro"
    },
    "23": {
        "name": "Creuse",
        "lat": 46.1585,
        "lng": 1.8705,
        "zone": "metro"
    },
    "24": {
        "name": "Dordogne",
        "lat": 45.1939,
        "lng": 0.7105,
        "zone": "metro"
    },
    "25": {
        "name": "Doubs",
        "lat": 47.2602,
        "lng": 6.0123,
        "zone": "metro"
    },
    "26": {
        "name": "Drôme",
        "lat": 44.9234,
        "lng": 4.9164,
        "zone": "metro"
    },
    "27": {
        "name": "Eure",
        "lat": 49.018,
        "lng": 1.1406,
        "zone": "metro"
    },
    "28": {
        "name": "Eure-et-Loir",
        "lat": 48.4481,
        "lng": 1.5046,
        "zone": "metro"
    },
    "29": {
        "name": "Finistère",
        "lat": 48.4085,
        "lng": -4.4996,
        "zone": "metro"
    },
    "2A": {
        "name": "Corse-du-Sud",
        "lat": 41.9228,
        "lng": 8.7058,
        "zone": "metro"
    },
    "2B": {
        "name": "Haute-Corse",
        "lat": 42.6861,
        "lng": 9.424,
        "zone": "metro"
    },
    "30": {
        "name": "Gard",
        "lat": 43.8322,
        "lng": 4.3429,
        "zone": "metro"
    },
    "31": {
        "name": "Haute-Garonne",
        "lat": 43.6007,
        "lng": 1.4328,
        "zone": "metro"
    },
    "32": {
        "name": "Gers",
        "lat": 43.6602,
        "lng": 0.5673,
        "zone": "metro"
    },
    "33": {
        "name": "Gironde",
        "lat": 44.8624,
        "lng": -0.5848,
        "zone": "metro"
    },
    "34": {
        "name": "Hérault",
        "lat": 43.61,
        "lng": 3.8742,
        "zone": "metro"
    },
    "35": {
        "name": "Ille-et-Vilaine",
        "lat": 48.1159,
        "lng": -1.6884,
        "zone": "metro"
    },
    "36": {
        "name": "Indre",
        "lat": 46.8023,
        "lng": 1.6903,
        "zone": "metro"
    },
    "37": {
        "name": "Indre-et-Loire",
        "lat": 47.3943,
        "lng": 0.6949,
        "zone": "metro"
    },
    "38": {
        "name": "Isère",
        "lat": 45.1842,
        "lng": 5.7155,
        "zone": "metro"
    },
    "39": {
        "name": "Jura",
        "lat": 47.0739,
        "lng": 5.5024,
        "zone": "metro"
    },
    "40": {
        "name": "Landes",
        "lat": 43.8931,
        "lng": -0.5009,
        "zone": "metro"
    },
    "41": {
        "name": "Loir-et-Cher",
        "lat": 47.5813,
        "lng": 1.3049,
        "zone": "metro"
    },
    "42": {
        "name": "Loire",
        "lat": 45.4241,
        "lng": 4.3665,
        "zone": "metro"
    },
    "43": {
        "name": "Haute-Loire",
        "lat": 45.0283,
        "lng": 3.8973,
        "zone": "metro"
    },
    "44": {
        "name": "Loire-Atlantique",
        "lat": 47.2382,
        "lng": -1.5603,
        "zone": "metro"
    },
    "45": {
        "name": "Loiret",
        "lat": 47.8734,
        "lng": 1.9122,
        "zone": "metro"
    },
    "46": {
        "name": "Lot",
        "lat": 44.4565,
        "lng": 1.439,
        "zone": "metro"
    },
    "47": {
        "name": "Lot-et-Garonne",
        "lat": 44.201,
        "lng": 0.6302,
        "zone": "metro"
    },
    "48": {
        "name": "Lozère",
        "lat": 44.5349,
        "lng": 3.4909,
        "zone": "metro"
    },
    "49": {
        "name": "Maine-et-Loire",
        "lat": 47.4819,
        "lng": -0.5629,
        "zone": "metro"
    },
    "50": {
        "name": "Manche",
        "lat": 49.6277,
        "lng": -1.6356,
        "zone": "metro"
    },
    "51": {
        "name": "Marne",
        "lat": 49.2535,
        "lng": 4.0551,
        "zone": "metro"
    },
    "52": {
        "name": "Haute-Marne",
        "lat": 48.6319,
        "lng": 4.9399,
        "zone": "metro"
    },
    "53": {
        "name": "Mayenne",
        "lat": 48.0578,
        "lng": -0.7692,
        "zone": "metro"
    },
    "54": {
        "name": "Meurthe-et-Moselle",
        "lat": 48.6881,
        "lng": 6.1734,
        "zone": "metro"
    },
    "55": {
        "name": "Meuse",
        "lat": 49.144,
        "lng": 5.3609,
        "zone": "metro"
    },
    "56": {
        "name": "Morbihan",
        "lat": 47.7494,
        "lng": -3.3799,
        "zone": "metro"
    },
    "57": {
        "name": "Moselle",
        "lat": 49.1048,
        "lng": 6.1962,
        "zone": "metro"
    },
    "58": {
        "name": "Nièvre",
        "lat": 46.9852,
        "lng": 3.1598,
        "zone": "metro"
    },
    "59": {
        "name": "Nord",
        "lat": 50.6311,
        "lng": 3.0468,
        "zone": "metro"
    },
    "60": {
        "name": "Oise",
        "lat": 49.4425,
        "lng": 2.0877,
        "zone": "metro"
    },
    "61": {
        "name": "Orne",
        "lat": 48.431,
        "lng": 0.0923,
        "zone": "metro"
    },
    "62": {
        "name": "Pas-de-Calais",
        "lat": 50.9523,
        "lng": 1.869,
        "zone": "metro"
    },
    "63": {
        "name": "Puy-de-Dôme",
        "lat": 45.787,
        "lng": 3.1127,
        "zone": "metro"
    },
    "64": {
        "name": "Pyrénées-Atlantiques",
        "lat": 43.3219,
        "lng": -0.3435,
        "zone": "metro"
    },
    "65": {
        "name": "Hautes-Pyrénées",
        "lat": 43.2387,
        "lng": 0.0653,
        "zone": "metro"
    },
    "66": {
        "name": "Pyrénées-Orientales",
        "lat": 42.699,
        "lng": 2.9045,
        "zone": "metro"
    },
    "67": {
        "name": "Bas-Rhin",
        "lat": 48.5691,
        "lng": 7.7621,
        "zone": "metro"
    },
    "68": {
        "name": "Haut-Rhin",
        "lat": 47.7526,
        "lng": 7.3255,
        "zone": "metro"
    },
    "69": {
        "name": "Rhône",
        "lat": 45.758,
        "lng": 4.8351,
        "zone": "metro"
    },
    "70": {
        "name": "Haute-Saône",
        "lat": 47.6323,
        "lng": 6.1523,
        "zone": "metro"
    },
    "71": {
        "name": "Saône-et-Loire",
        "lat": 46.7896,
        "lng": 4.8509,
        "zone": "metro"
    },
    "72": {
        "name": "Sarthe",
        "lat": 47.9819,
        "lng": 0.1957,
        "zone": "metro"
    },
    "73": {
        "name": "Savoie",
        "lat": 45.5822,
        "lng": 5.9064,
        "zone": "metro"
    },
    "74": {
        "name": "Haute-Savoie",
        "lat": 45.9024,
        "lng": 6.1264,
        "zone": "metro"
    },
    "75": {
        "name": "Paris",
        "lat": 48.8589,
        "lng": 2.347,
        "zone": "metro"
    },
    "76": {
        "name": "Seine-Maritime",
        "lat": 49.4958,
        "lng": 0.1312,
        "zone": "metro"
    },
    "77": {
        "name": "Seine-et-Marne",
        "lat": 48.9573,
        "lng": 2.9035,
        "zone": "metro"
    },
    "78": {
        "name": "Yvelines",
        "lat": 48.8039,
        "lng": 2.1191,
        "zone": "metro"
    },
    "79": {
        "name": "Deux-Sèvres",
        "lat": 46.3274,
        "lng": -0.4613,
        "zone": "metro"
    },
    "80": {
        "name": "Somme",
        "lat": 49.8987,
        "lng": 2.2847,
        "zone": "metro"
    },
    "81": {
        "name": "Tarn",
        "lat": 43.929,
        "lng": 2.1323,
        "zone": "metro"
    },
    "82": {
        "name": "Tarn-et-Garonne",
        "lat": 44.0217,
        "lng": 1.3646,
        "zone": "metro"
    },
    "83": {
        "name": "Var",
        "lat": 43.1364,
        "lng": 5.9334,
        "zone": "metro"
    },
    "84": {
        "name": "Vaucluse",
        "lat": 43.9416,
        "lng": 4.8333,
        "zone": "metro"
    },
    "85": {
        "name": "Vendée",
        "lat": 46.6659,
        "lng": -1.4162,
        "zone": "metro"
    },
    "86": {
        "name": "Vienne",
        "lat": 46.5846,
        "lng": 0.3715,
        "zone": "metro"
    },
    "87": {
        "name": "Haute-Vienne",
        "lat": 45.8567,
        "lng": 1.226,
        "zone": "metro"
    },
    "88": {
        "name": "Vosges",
        "lat": 48.1637,
        "lng": 6.4867,
        "zone": "metro"
    },
    "89": {
        "name": "Yonne",
        "lat": 47.7939,
        "lng": 3.5821,
        "zone": "metro"
    },
    "90": {
        "name": "Territoire de Belfort",
        "lat": 47.6458,
        "lng": 6.841,
        "zone": "metro"
    },
    "91": {
        "name": "Essonne",
        "lat": 48.6287,
        "lng": 2.4313,
        "zone": "metro"
    },
    "92": {
        "name": "Hauts-de-Seine",
        "lat": 48.8375,
        "lng": 2.2429,
        "zone": "metro"
    },
    "93": {
        "name": "Seine-Saint-Denis",
        "lat": 48.9378,
        "lng": 2.3657,
        "zone": "metro"
    },
    "94": {
        "name": "Val-de-Marne",
        "lat": 48.7893,
        "lng": 2.3951,
        "zone": "metro"
    },
    "95": {
        "name": "Val-d'Oise",
        "lat": 48.9501,
        "lng": 2.2478,
        "zone": "metro"
    },
    "971": {
        "name": "Guadeloupe",
        "lat": 16.2678,
        "lng": -61.4967,
        "zone": "outre-mer"
    },
    "972": {
        "name": "Martinique",
        "lat": 14.6492,
        "lng": -61.0686,
        "zone": "outre-mer"
    },
    "973": {
        "name": "Guyane",
        "lat": 4.9464,
        "lng": -52.3319,
        "zone": "outre-mer"
    },
    "974": {
        "name": "La Réunion",
        "lat": -20.9434,
        "lng": 55.4444,
        "zone": "outre-mer"
    },
    "976": {
        "name": "Mayotte",
        "lat": -12.7875,
        "lng": 45.1964,
        "zone": "outre-mer"
    }
}
"""

DEPARTMENTS = json.loads(_EMBEDDED_DEPARTMENTS_JSON)

GEO_API_BASE = "https://geo.api.gouv.fr"
OVERPASS_API_URL = "https://overpass-api.de/api/interpreter"
OVERPASS_API_FALLBACKS = [
    OVERPASS_API_URL,
    "https://overpass.kumi.systems/api/interpreter",
]
CATEGORY_TO_GROUP = {
    "culture": "Culture",
    "nature": "Nature",
    "experienceGustative": "Experience gustative",
    "histoire": "Patrimoine et Histoire",
    "activites": "Activites plein air",
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
    
    for endpoint in OVERPASS_API_FALLBACKS:
        for attempt in range(1, 4):
            try:
                response = requests.post(
                    endpoint,
                    data=query,
                    headers={"Content-Type": "text/plain"},
                    timeout=120,
                )
                response.raise_for_status()
                data = response.json()
                return data.get("elements", [])
            except Exception as e:
                wait_seconds = attempt * 2
                print(
                    f"⚠️ Overpass erreur (endpoint={endpoint}, tentative={attempt}/3): {e}"
                )
                if attempt < 3:
                    time.sleep(wait_seconds)

    print("❌ Overpass indisponible après retries")
    return []


def fetch_departments(include_domtom=True):
    """Récupère tous les départements (métropole + DOM-TOM) via API officielle"""
    try:
        response = requests.get(
            f"{GEO_API_BASE}/departements",
            params={"fields": "code,nom,centre,zone", "format": "json"},
            timeout=30,
        )
        response.raise_for_status()
        data = response.json()

        departments = {}
        for item in data:
            code = str(item.get("code", "")).strip()
            zone = "outre-mer" if code.startswith("97") else "metro"
            if not include_domtom and zone == "outre-mer":
                continue

            center = item.get("centre", {})
            coords = center.get("coordinates") or []
            if len(coords) != 2:
                continue

            lng, lat = coords[0], coords[1]
            name = str(item.get("nom", "")).strip()
            if not code or not name:
                continue

            departments[code] = {"name": name, "lat": lat, "lng": lng, "zone": zone}

        if departments:
            return departments
    except Exception as e:
        print(f"⚠️ Impossible de charger la liste officielle des départements: {e}")

    if include_domtom:
        print("↩️ Fallback embarqué: départements métropole + DOM")
        return DEPARTMENTS

    filtered = {
        code: value
        for code, value in DEPARTMENTS.items()
        if not str(code).startswith("97")
    }
    print("↩️ Fallback embarqué: départements métropole")
    return filtered


def fetch_communes(department_code, communes_limit=0, min_population=0):
    """Récupère les villes/villages d'un département"""
    try:
        response = requests.get(
            f"{GEO_API_BASE}/departements/{department_code}/communes",
            params={"fields": "code,nom,centre,population", "format": "json"},
            timeout=45,
        )
        response.raise_for_status()
        data = response.json()

        communes = []
        for item in data:
            center = item.get("centre", {})
            coords = center.get("coordinates") or []
            if len(coords) != 2:
                continue

            population = item.get("population") or 0
            if population < min_population:
                continue

            lng, lat = coords[0], coords[1]
            communes.append(
                {
                    "code": str(item.get("code", "")).strip(),
                    "name": str(item.get("nom", "")).strip() or "Commune",
                    "lat": lat,
                    "lng": lng,
                    "population": population,
                }
            )

        communes.sort(key=lambda c: c.get("population", 0), reverse=True)
        if communes_limit > 0:
            communes = communes[:communes_limit]

        return communes
    except Exception as e:
        print(f"⚠️ Impossible de charger les communes du département {department_code}: {e}")
        return []


def clean_poi_data(element, category, scope_name="", department_code=""):
    """Nettoie et formate les données POI"""
    tags = element.get("tags", {})

    def _normalize_image_url(raw_value):
        if not raw_value:
            return None
        value = str(raw_value).strip()
        if not value:
            return None

        if value.startswith("//"):
            return f"https:{value}"
        if value.startswith("http://") or value.startswith("https://"):
            return value

        if value.lower().startswith("file:"):
            filename = value.split(":", 1)[1].strip().replace(" ", "_")
            if not filename:
                return None
            return f"https://commons.wikimedia.org/wiki/Special:FilePath/{filename}"

        if value.lower().startswith("wikimedia_commons:"):
            filename = value.split(":", 1)[1].strip().replace(" ", "_")
            if not filename:
                return None
            return f"https://commons.wikimedia.org/wiki/Special:FilePath/{filename}"

        if value.startswith("Q") and value[1:].isdigit():
            return f"https://www.wikidata.org/wiki/{value}"

        if "/" not in value and "." in value:
            filename = value.replace(" ", "_")
            return f"https://commons.wikimedia.org/wiki/Special:FilePath/{filename}"

        return None
    
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
    image_candidates = [
        tags.get("image"),
        tags.get("wikimedia_commons"),
        tags.get("wikidata"),
    ]
    images = []
    for candidate in image_candidates:
        normalized = _normalize_image_url(candidate)
        if normalized and normalized not in images:
            images.append(normalized)
    images = images[:5]
    
    # Website
    website = tags.get("website") or tags.get("contact:website")

    lat = element["lat"]
    lng = element["lon"]
    category_group = CATEGORY_TO_GROUP.get(category, "Culture")
    category_item = tags.get("tourism") or tags.get("amenity") or tags.get("shop") or "other"
    
    return {
        "id": f"osm_{element['id']}",
        "name": name[:100],  # Limite 100 caractères
        "lat": lat,
        "lng": lng,
        "location": {
            "_latitude": lat,
            "_longitude": lng,
        },
        "description": description[:500],  # Limite 500 caractères
        "category": category,
        "categoryGroup": category_group,
        "categoryItem": category_item,
        "city": scope_name,
        "departmentCode": department_code,
        "imageUrls": images,
        "images": images,
        "websiteUrl": website,
        "website": website,
        "source": "openstreetmap",
        "osmId": element["id"],
        "isPublic": True,
        "isValidated": True,
        "isFree": None,
        "pmrAccessible": tags.get("wheelchair") == "yes",
        "kidsFriendly": None,
        "createdAt": {"_seconds": int(time.time()), "_nanoseconds": 0},
        "updatedAt": datetime.now().isoformat(),
    }


def save_to_firestore_format(pois, output_file):
    """Sauvegarde au format importable dans Firestore"""
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(pois, f, ensure_ascii=False, indent=2)
    
    print(f"✅ {len(pois)} POIs sauvegardés dans {output_file}")


def export_catalog(departments, output_path, include_communes=True, communes_limit=0, min_population=0):
    """Exporte l'inventaire des départements + villes/villages"""
    catalog = []

    for code in sorted(departments.keys()):
        dept = departments[code]
        entry = {
            "departmentCode": code,
            "departmentName": dept["name"],
            "zone": dept.get("zone", ""),
            "center": {"lat": dept["lat"], "lng": dept["lng"]},
            "communes": [],
        }

        if include_communes:
            entry["communes"] = fetch_communes(
                code,
                communes_limit=communes_limit,
                min_population=min_population,
            )

        catalog.append(entry)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)

    total_communes = sum(len(e["communes"]) for e in catalog)
    print(f"✅ Catalogue exporté: {output_path}")
    print(f"   Départements: {len(catalog)}")
    print(f"   Villes/Villages: {total_communes}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--department", help="Code département (ex: 75)")
    parser.add_argument(
        "--departments",
        help="Liste de départements séparés par des virgules (ex: 75,77,78,2A,2B)",
    )
    parser.add_argument("--all-departments", action="store_true", help="Importer tous les départements")
    parser.add_argument("--no-domtom", action="store_true", help="Exclure les DOM-TOM")
    parser.add_argument("--use-communes", action="store_true", help="Importer par centres de communes (villes/villages)")
    parser.add_argument("--communes-limit", type=int, default=0, help="Nombre max de communes par département (0=toutes)")
    parser.add_argument("--min-population", type=int, default=0, help="Population minimale pour filtrer les communes")
    parser.add_argument("--catalog-output", help="Exporter l'inventaire départements+communes en JSON")
    parser.add_argument("--catalog-only", action="store_true", help="Ne faire que l'export de catalogue")
    parser.add_argument("--sleep-seconds", type=float, default=1.0, help="Pause entre requêtes Overpass")
    parser.add_argument("--max-requests", type=int, default=0, help="Limiter le nombre total de requêtes Overpass (0=sans limite)")
    parser.add_argument(
        "--category",
        default="culture",
        choices=list(CATEGORY_TAGS.keys()),
        help="Catégorie de POIs",
    )
    parser.add_argument("--radius", type=int, default=20000, help="Rayon en mètres")
    parser.add_argument("--output", default="pois_import.json", help="Fichier de sortie")
    
    args = parser.parse_args()

    include_domtom = not args.no_domtom
    departments = fetch_departments(include_domtom=include_domtom)

    if args.catalog_output:
        export_catalog(
            departments,
            output_path=args.catalog_output,
            include_communes=True,
            communes_limit=args.communes_limit,
            min_population=args.min_population,
        )

    if args.catalog_only:
        return

    selected_departments = []
    if args.departments:
        selected_departments = [
            dep.strip().upper() for dep in args.departments.split(",") if dep.strip()
        ]

    if not args.all_departments and not args.department and not selected_departments:
        print("❌ Spécifiez --department XX, --departments X,Y,Z ou --all-departments")
        return

    if args.department and args.department not in departments:
        print(f"❌ Département {args.department} non supporté")
        return

    for dep_code in selected_departments:
        if dep_code not in departments:
            print(f"❌ Département {dep_code} non supporté")
            return

    if args.all_departments:
        target_department_codes = sorted(departments.keys())
    elif args.department:
        target_department_codes = [args.department]
    else:
        target_department_codes = sorted(set(selected_departments))

    tags = CATEGORY_TAGS[args.category]
    pois = []
    seen_osm_ids = set()
    request_count = 0
    
    if args.all_departments:
        scope_label = "Tous départements"
    elif args.department:
        scope_label = f"Département {args.department}"
    else:
        scope_label = f"Départements: {', '.join(target_department_codes)}"
    print(f"\n🗺️  Import OSM: {scope_label}")
    print(f"📂 Catégorie: {args.category}")
    print(f"📏 Rayon: {args.radius}m\n")

    for dept_code in target_department_codes:
        dept = departments[dept_code]
        print(f"\n➡️ {dept['name']} ({dept_code})")

        scopes = []
        if args.use_communes:
            communes = fetch_communes(
                dept_code,
                communes_limit=args.communes_limit,
                min_population=args.min_population,
            )
            if not communes:
                scopes = [{"name": dept["name"], "lat": dept["lat"], "lng": dept["lng"]}]
            else:
                scopes = communes
        else:
            scopes = [{"name": dept["name"], "lat": dept["lat"], "lng": dept["lng"]}]

        for scope in scopes:
            if args.max_requests > 0 and request_count >= args.max_requests:
                print("⏹️ Limite de requêtes atteinte (--max-requests)")
                break

            request_count += 1
            elements = query_overpass(scope["lat"], scope["lng"], args.radius, tags)

            for elem in elements:
                if elem.get("type") != "node" or "lat" not in elem or "lon" not in elem:
                    continue

                osm_id = elem.get("id")
                if osm_id in seen_osm_ids:
                    continue

                seen_osm_ids.add(osm_id)
                poi = clean_poi_data(
                    elem,
                    category=args.category,
                    scope_name=scope.get("name", dept["name"]),
                    department_code=dept_code,
                )
                pois.append(poi)

            if args.sleep_seconds > 0:
                time.sleep(args.sleep_seconds)

        if args.max_requests > 0 and request_count >= args.max_requests:
            break

    if not pois:
        print("⚠️  Aucun POI trouvé")
        return

    print(f"\n📝 {len(pois)} POIs extraits (dédupliqués)")
    
    # Sauvegarder
    save_to_firestore_format(pois, args.output)
    
    print(f"\n✅ Import terminé!")
    print(f"\n💡 Pour importer dans Firestore:")
    print(f"   firebase firestore:delete spots --all-collections")
    print(f"   node scripts/import_to_firestore.js {args.output}")
    print(f"\n⏱️  Pause actuelle entre requêtes: {args.sleep_seconds}s")


if __name__ == "__main__":
    main()
