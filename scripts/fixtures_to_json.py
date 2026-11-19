#!/usr/bin/env python3
"""Build Kabelmeter/Resources/fixtures.json and copy the 3D models into the app.

Usage: python3 -I scripts/fixtures_to_json.py

Reads (all in assets/):
  sku_mapping.csv   one row per placeable product (model file, line, colour, parts, price)
  sku_parts.csv     one row per elektramat.nl part (sku, description, price, url)
  busch-jaeger-usdz/out/manifest.json   product names per model file
  busch-jaeger-usdz/out/usdz/*.usdz     the models

Writes:
  Kabelmeter/Resources/fixtures.json
  Kabelmeter/Resources/Models/<model>.usdz   (only the models that are used)

Both CSVs use ";" as separator and "." for decimals. A mapping row whose model file does
not exist falls back to the model with the last part of the colour (the insert colour),
e.g. carat "witglas-studiowit" uses busch-jaeger_carat_studiowit_*.usdz.
"""
import csv
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
MODELS_IN = ASSETS / "busch-jaeger-usdz" / "out" / "usdz"
MANIFEST = ASSETS / "busch-jaeger-usdz" / "out" / "manifest.json"
RESOURCES = ROOT / "Kabelmeter" / "Resources"
MODELS_OUT = RESOURCES / "Models"
ROLES = ["opbouwbak", "afdekraam", "basiselement", "wip", "stopcontact"]


def read_csv(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f, delimiter=";"))


def number(value):
    value = (value or "").strip().replace(",", ".")
    return float(value) if value else None


def resolve_model(row):
    wanted = row["model_file"].strip()
    if (MODELS_IN / wanted).exists():
        return wanted
    stem = wanted.removesuffix(".usdz")
    brand, line, colour, *rest = stem.split("_")
    fallback = "_".join([brand, line, colour.split("-")[-1], *rest]) + ".usdz"
    if (MODELS_IN / fallback).exists():
        print(f"note: {wanted} not found, using {fallback}", file=sys.stderr)
        return fallback
    return None


def main():
    parts = {p["sku"].strip(): p for p in read_csv(ASSETS / "sku_parts.csv")}
    names = {m["file"]: m for m in json.loads(MANIFEST.read_text(encoding="utf-8"))}
    fixtures, used = [], set()

    for n, row in enumerate(read_csv(ASSETS / "sku_mapping.csv"), start=2):
        model = resolve_model(row)
        if model is None:
            print(f"skip row {n}: no model for {row['model_file']}", file=sys.stderr)
            continue
        fixture_parts = []
        for role in ROLES:
            sku = (row.get(f"{role}_sku") or "").strip()
            if not sku or sku == "n/a":
                continue
            part = parts.get(sku)
            if part is None:
                sys.exit(f"row {n}: part {sku} ({role}) is missing from sku_parts.csv")
            fixture_parts.append({
                "role": role,
                "sku": sku,
                "description": part["description"].strip(),
                "price": number(part["price_incl_btw"]),
                "productUrl": part["url"].strip(),
            })
        complete = row["complete"].strip().lower() == "ja"
        manifest = names.get(model, {})
        fixtures.append({
            "id": row["model_file"].strip().removesuffix(".usdz"),
            "brand": manifest.get("brand", "Busch-Jaeger"),
            "line": row["line"].strip(),
            "colour": row["colour"].strip(),
            "product": row["product"].strip(),
            "productName": manifest.get("product", row["product"].strip().capitalize()),
            "mounting": row["mounting"].strip(),
            "model": model.removesuffix(".usdz"),
            "complete": complete,
            "price": number(row["total_incl_btw"]) if complete else None,
            "parts": fixture_parts,
            "note": (row.get("notes") or "").strip() or None,
            "frameMM": manifest.get("frame_mm", [80, 80]),
            "depthMM": manifest.get("depth_from_wall_mm", 12),
        })
        used.add(model)

    fixtures.sort(key=lambda f: (f["line"].lower(), f["colour"], f["product"], f["mounting"]))
    (RESOURCES / "fixtures.json").write_text(
        json.dumps(fixtures, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    MODELS_OUT.mkdir(exist_ok=True)
    for old in MODELS_OUT.glob("*.usdz"):
        if old.name not in used:
            old.unlink()
    for model in sorted(used):
        shutil.copy2(MODELS_IN / model, MODELS_OUT / model)
    print(f"{len(fixtures)} fixtures, {len(used)} models", file=sys.stderr)


if __name__ == "__main__":
    main()
