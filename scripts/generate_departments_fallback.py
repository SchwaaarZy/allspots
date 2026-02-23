#!/usr/bin/env python3
import json
import urllib.parse
import urllib.request
import time
from pathlib import Path

BASE = "https://geo.api.gouv.fr"
OUT = Path("scripts/departments_fr.json")


def main() -> None:
    with urllib.request.urlopen(f"{BASE}/departements?format=json", timeout=30) as response:
        departments = json.load(response)

    out = {}
    for index, department in enumerate(departments, start=1):
        code = department["code"]
        name = department["nom"]

        params = urllib.parse.urlencode(
            {
                "codeDepartement": code,
                "fields": "code,nom,centre,population",
                "format": "json",
            }
        )
        url = f"{BASE}/communes?{params}"

        lat = None
        lng = None
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                communes = json.load(response)

            best_center = None
            best_population = -1
            for commune in communes:
                center = (commune.get("centre") or {}).get("coordinates") or []
                population = commune.get("population") or 0
                if len(center) == 2 and population >= best_population:
                    best_population = population
                    best_center = center

            if best_center:
                lng, lat = best_center
        except Exception:
            pass

        if lat is None or lng is None:
            lat, lng = 46.603354, 1.888334

        zone = "outre-mer" if code.startswith("97") else "metro"
        out[code] = {
            "name": name,
            "lat": lat,
            "lng": lng,
            "zone": zone,
        }

        if index % 20 == 0:
            print(f"processed {index}/{len(departments)}")
        time.sleep(0.05)

    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"saved {len(out)} departments to {OUT}")


if __name__ == "__main__":
    main()
