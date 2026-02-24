#!/usr/bin/env python3
"""
Script d'orchestration pour import public de POIs
Stratégie: OpenStreetMap + Data.gouv.fr + UNESCO (sans Google)
"""

import argparse
import json
import os
import subprocess
import time
from datetime import datetime
from typing import Dict, List, Optional

MAJOR_CITIES = {
    "paris": {"department": "75", "radius": 25000},
    "marseille": {"department": "13", "radius": 20000},
    "lyon": {"department": "69", "radius": 20000},
    "toulouse": {"department": "31", "radius": 18000},
    "nice": {"department": "06", "radius": 15000},
    "nantes": {"department": "44", "radius": 15000},
    "strasbourg": {"department": "67", "radius": 15000},
    "montpellier": {"department": "34", "radius": 15000},
    "bordeaux": {"department": "33", "radius": 18000},
    "lille": {"department": "59", "radius": 15000},
}

CATEGORIES = ["culture", "nature", "experienceGustative", "histoire", "activites"]
UNESCO_CATEGORIES = ["tous", "culture", "nature", "experienceGustative", "histoire", "activites"]
REGION_DEPARTMENTS = {
    "ile_de_france": ["75", "77", "78", "91", "92", "93", "94", "95"],
    "auvergne_rhone_alpes": ["01", "03", "07", "15", "26", "38", "42", "43", "63", "69", "73", "74"],
    "provence_alpes_cote_dazur": ["04", "05", "06", "13", "83", "84"],
    "occitanie": ["09", "11", "12", "30", "31", "32", "34", "46", "48", "65", "66", "81", "82"],
    "nouvelle_aquitaine": ["16", "17", "19", "23", "24", "33", "40", "47", "64", "79", "86", "87"],
    "bretagne": ["22", "29", "35", "56"],
    "pays_de_la_loire": ["44", "49", "53", "72", "85"],
    "hauts_de_france": ["02", "59", "60", "62", "80"],
    "grand_est": ["08", "10", "51", "52", "54", "55", "57", "67", "68", "88"],
    "normandie": ["14", "27", "50", "61", "76"],
    "centre_val_de_loire": ["18", "28", "36", "37", "41", "45"],
    "bourgogne_franche_comte": ["21", "25", "39", "58", "70", "71", "89", "90"],
    "corse": ["2A", "2B"],
    "dom_tom": ["971", "972", "973", "974", "976"],
}


def run_command(cmd: List[str], label: str) -> bool:
    print(f"\n▶️ {label}")
    print(" ".join(cmd))
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        if result.stdout.strip():
            print(result.stdout.strip())
        if result.stderr.strip():
            print(result.stderr.strip())
        return True
    except subprocess.CalledProcessError as error:
        print(f"❌ Échec: {label}")
        if error.stdout:
            print(error.stdout)
        if error.stderr:
            print(error.stderr)
        return False


def run_osm_all_departments(
    python_bin: str,
    categories: List[str],
    temp_dir: str,
    radius: int,
    sleep_seconds: float,
    use_communes: bool,
    communes_limit: int,
    min_population: int,
    no_domtom: bool,
    max_requests: int,
    departments: Optional[List[str]],
) -> List[str]:
    files: List[str] = []

    for category in categories:
        output_file = os.path.join(temp_dir, f"pois_osm_all_departments_{category}.json")
        cmd = [
            python_bin,
            "scripts/import_osm_france.py",
            "--category",
            category,
            "--radius",
            str(radius),
            "--sleep-seconds",
            str(sleep_seconds),
            "--output",
            output_file,
        ]

        if departments:
            cmd.extend(["--departments", ",".join(departments)])
        else:
            cmd.append("--all-departments")

        if use_communes:
            cmd.extend([
                "--use-communes",
                "--communes-limit",
                str(communes_limit),
                "--min-population",
                str(min_population),
            ])

        if no_domtom:
            cmd.append("--no-domtom")

        if max_requests > 0:
            cmd.extend(["--max-requests", str(max_requests)])

        if run_command(cmd, f"OSM all-departments / {category}"):
            files.append(output_file)

    return files


def run_osm_cities(
    python_bin: str,
    cities: List[str],
    categories: List[str],
    temp_dir: str,
    override_radius: Optional[int],
    sleep_seconds: float,
) -> List[str]:
    files: List[str] = []

    for city in cities:
        config = MAJOR_CITIES[city]
        radius = override_radius if override_radius is not None else config["radius"]

        for category in categories:
            output_file = os.path.join(temp_dir, f"pois_osm_{city}_{category}.json")
            cmd = [
                python_bin,
                "scripts/import_osm_france.py",
                "--department",
                config["department"],
                "--category",
                category,
                "--radius",
                str(radius),
                "--sleep-seconds",
                str(sleep_seconds),
                "--output",
                output_file,
            ]

            if run_command(cmd, f"OSM city {city} / {category}"):
                files.append(output_file)

    return files


def run_datagouv(python_bin: str, temp_dir: str, department: Optional[str]) -> Optional[str]:
    output_file = os.path.join(temp_dir, "pois_datagouv_all.json")
    cmd = [
        python_bin,
        "scripts/import_datagouv.py",
        "--dataset",
        "all",
        "--output",
        output_file,
    ]
    if department:
        cmd.extend(["--department", department])

    if run_command(cmd, "Data.gouv.fr"):
        return output_file

    return None


def run_unesco(python_bin: str, temp_dir: str, unesco_category: str) -> Optional[str]:
    output_file = os.path.join(temp_dir, "pois_unesco_france.json")
    cmd = [
        python_bin,
        "scripts/import_unesco.py",
        "--category",
        unesco_category,
        "--output",
        output_file,
    ]

    if run_command(cmd, "UNESCO"):
        return output_file

    return None


def build_dedupe_key(poi: Dict) -> Optional[str]:
    source = str(poi.get("source", "")).strip().lower()

    if source == "openstreetmap" and poi.get("osmId"):
        return f"osm:{poi['osmId']}"

    if source == "unesco" and poi.get("unescoId"):
        return f"unesco:{poi['unescoId']}"

    name = str(poi.get("name", "")).strip().lower()
    location = poi.get("location", {})
    lat = location.get("_latitude")
    lng = location.get("_longitude")

    try:
        if name and lat is not None and lng is not None:
            return f"name:{name}:{round(float(lat), 5)}:{round(float(lng), 5)}"
    except (TypeError, ValueError):
        return None

    return None


def merge_json_files(files: List[str], output: str) -> int:
    merged: Dict[str, Dict] = {}

    for file_path in files:
        if not file_path or not os.path.exists(file_path):
            continue

        try:
            with open(file_path, "r", encoding="utf-8") as handle:
                pois = json.load(handle)

            for poi in pois:
                key = build_dedupe_key(poi)
                if not key:
                    continue
                merged[key] = poi
        except Exception as error:
            print(f"⚠️ Erreur lecture {file_path}: {error}")

    final_pois = list(merged.values())
    with open(output, "w", encoding="utf-8") as handle:
        json.dump(final_pois, handle, ensure_ascii=False, indent=2)

    return len(final_pois)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import public rapide: OSM + Data.gouv.fr + UNESCO (sans Google)"
    )
    parser.add_argument(
        "--osm-mode",
        choices=["all-departments", "cities"],
        default="all-departments",
        help="Mode OSM: couverture nationale ou grandes villes",
    )
    parser.add_argument(
        "--cities",
        nargs="+",
        choices=list(MAJOR_CITIES.keys()) + ["all"],
        default=["all"],
        help="Villes à importer si --osm-mode=cities",
    )
    parser.add_argument(
        "--categories",
        nargs="+",
        choices=CATEGORIES + ["all"],
        default=["all"],
        help="Catégories à importer pour OSM",
    )
    parser.add_argument(
        "--regions",
        nargs="+",
        choices=list(REGION_DEPARTMENTS.keys()) + ["all"],
        default=["all"],
        help="Régions à importer pour --osm-mode=all-departments",
    )
    parser.add_argument(
        "--unesco-category",
        choices=UNESCO_CATEGORIES,
        default="tous",
        help="Filtre de catégorie UNESCO",
    )
    parser.add_argument("--radius", type=int, default=12000, help="Rayon OSM en mètres")
    parser.add_argument(
        "--sleep-seconds",
        type=float,
        default=1.0,
        help="Pause OSM entre requêtes Overpass",
    )
    parser.add_argument(
        "--max-requests",
        type=int,
        default=0,
        help="Limiter OSM (0 = sans limite)",
    )
    parser.add_argument("--use-communes", action="store_true", help="OSM maillage communes")
    parser.add_argument(
        "--communes-limit",
        type=int,
        default=0,
        help="Max communes / département (0 = toutes)",
    )
    parser.add_argument(
        "--min-population",
        type=int,
        default=0,
        help="Population mini pour filtrer les communes",
    )
    parser.add_argument("--no-domtom", action="store_true", help="Exclure les DOM-TOM pour OSM")
    parser.add_argument("--skip-osm", action="store_true", help="Ignorer OSM")
    parser.add_argument("--skip-datagouv", action="store_true", help="Ignorer Data.gouv.fr")
    parser.add_argument("--skip-unesco", action="store_true", help="Ignorer UNESCO")
    parser.add_argument(
        "--datagouv-department",
        default="",
        help="Département Data.gouv (vide = France entière)",
    )
    parser.add_argument(
        "--output",
        default="pois_france_public.json",
        help="Fichier JSON final fusionné",
    )
    parser.add_argument(
        "--temp-dir",
        default="scripts/out",
        help="Dossier des exports intermédiaires",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    python_bin = "python3"
    venv_python = os.path.join(os.getcwd(), ".venv", "bin", "python")
    if os.path.exists(venv_python):
        python_bin = venv_python

    categories = CATEGORIES if "all" in args.categories else args.categories
    cities = list(MAJOR_CITIES.keys()) if "all" in args.cities else args.cities
    region_names = list(REGION_DEPARTMENTS.keys()) if "all" in args.regions else args.regions

    selected_departments: List[str] = []
    if args.osm_mode == "all-departments":
        selected_set = set()
        for region_name in region_names:
            selected_set.update(REGION_DEPARTMENTS[region_name])
        selected_departments = sorted(selected_set)

        if args.no_domtom:
            selected_departments = [
                dep_code
                for dep_code in selected_departments
                if dep_code not in set(REGION_DEPARTMENTS["dom_tom"])
            ]

    os.makedirs(args.temp_dir, exist_ok=True)

    print("🇫🇷 IMPORT PUBLIC RAPIDE (SANS GOOGLE)")
    print("=" * 64)
    print(f"OSM: {'OFF' if args.skip_osm else 'ON'} / mode={args.osm_mode}")
    if args.osm_mode == "all-departments" and not args.skip_osm:
        print(f"Régions OSM: {', '.join(region_names)}")
        print(f"Départements ciblés: {len(selected_departments)}")
    print(f"Data.gouv: {'OFF' if args.skip_datagouv else 'ON'}")
    print(f"UNESCO: {'OFF' if args.skip_unesco else 'ON'} / catégorie={args.unesco_category}")
    print(f"Sortie finale: {args.output}")
    print("=" * 64)

    generated_files: List[str] = []

    if not args.skip_osm:
        started = time.time()
        if args.osm_mode == "all-departments":
            generated_files.extend(
                run_osm_all_departments(
                    python_bin=python_bin,
                    categories=categories,
                    temp_dir=args.temp_dir,
                    radius=args.radius,
                    sleep_seconds=args.sleep_seconds,
                    use_communes=args.use_communes,
                    communes_limit=args.communes_limit,
                    min_population=args.min_population,
                    no_domtom=args.no_domtom,
                    max_requests=args.max_requests,
                    departments=selected_departments,
                )
            )
        else:
            generated_files.extend(
                run_osm_cities(
                    python_bin=python_bin,
                    cities=cities,
                    categories=categories,
                    temp_dir=args.temp_dir,
                    override_radius=args.radius,
                    sleep_seconds=args.sleep_seconds,
                )
            )
        print(f"\n⏱️ OSM terminé en {time.time() - started:.1f}s")

    if not args.skip_datagouv:
        started = time.time()
        datagouv_file = run_datagouv(
            python_bin=python_bin,
            temp_dir=args.temp_dir,
            department=args.datagouv_department.strip() or None,
        )
        if datagouv_file:
            generated_files.append(datagouv_file)
        print(f"\n⏱️ Data.gouv terminé en {time.time() - started:.1f}s")

    if not args.skip_unesco:
        started = time.time()
        unesco_file = run_unesco(
            python_bin=python_bin,
            temp_dir=args.temp_dir,
            unesco_category=args.unesco_category,
        )
        if unesco_file:
            generated_files.append(unesco_file)
        print(f"\n⏱️ UNESCO terminé en {time.time() - started:.1f}s")

    if not generated_files:
        print("❌ Aucun export n'a été généré.")
        return

    total = merge_json_files(generated_files, args.output)

    print("\n✅ IMPORT TERMINÉ")
    print("=" * 64)
    print(f"Fichiers intermédiaires: {len(generated_files)}")
    print(f"POIs fusionnés (dédupliqués): {total}")
    print(f"Fichier final: {args.output}")
    print("\n🔥 Import Firestore:")
    print(f"node scripts/import_to_firestore.js {args.output}")

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"\n🕒 Terminé à {timestamp}")


if __name__ == "__main__":
    main()
