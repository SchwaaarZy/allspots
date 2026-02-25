#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Découpe un gros JSON de POIs en plusieurs fichiers plus petits."
    )
    parser.add_argument("input", help="Chemin du fichier JSON source (liste de POIs)")
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=15000,
        help="Nombre de POIs par fichier (défaut: 15000)",
    )
    parser.add_argument(
        "--out-dir",
        default="scripts/out/chunks",
        help="Dossier de sortie des chunks (défaut: scripts/out/chunks)",
    )
    parser.add_argument(
        "--prefix",
        default="pois_chunk",
        help="Préfixe des fichiers chunks (défaut: pois_chunk)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    input_path = Path(args.input)
    if not input_path.exists():
        raise FileNotFoundError(f"Fichier introuvable: {input_path}")

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    data = json.loads(input_path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError("Le JSON source doit contenir une liste")

    total = len(data)
    chunk_size = max(1, int(args.chunk_size))

    count = 0
    start = 0
    while start < total:
        end = min(start + chunk_size, total)
        part = data[start:end]
        index = count + 1
        out_file = out_dir / f"{args.prefix}_{index:03d}_{start}_{end-1}.json"
        out_file.write_text(json.dumps(part, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"chunk={index:03d} range={start}-{end-1} size={len(part)} file={out_file}")
        count += 1
        start = end

    print(f"✅ Chunks générés: {count} | total={total} | out={out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
