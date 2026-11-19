#!/usr/bin/env python3
"""Convert the Elektramat cable export (CSV) into Kabelmeter/Resources/cables.json.

Usage: python3 scripts/csv_to_cables_json.py export.csv > Kabelmeter/Resources/cables.json

Expected columns (header row, comma separated, UTF-8):
  sku, name, cross_section, use, price_per_meter, sales_type,
  step_m, minimum_m, lengths_m, stock, image_url, product_url
Optional: shop_product_id (the id the shop's add-to-cart form posts; without it the app
reads it from the product page, which is slower).

sales_type is "perMeter" (uses step_m and minimum_m) or "fixedLengths"
(uses lengths_m, separated by ";", e.g. "10;25;50;100").
Decimals may use a comma or a dot.
"""
import csv
import json
import sys


def number(value, field, row):
    try:
        return float(value.strip().replace(",", "."))
    except ValueError:
        sys.exit(f"Row {row}: '{field}' is not a number: {value!r}")


def main(path):
    cables, seen = [], set()
    with open(path, newline="", encoding="utf-8-sig") as f:
        for row, r in enumerate(csv.DictReader(f), start=2):
            sku = r["sku"].strip()
            if not sku or sku in seen:
                sys.exit(f"Row {row}: missing or duplicate sku {sku!r}")
            seen.add(sku)
            kind = r["sales_type"].strip()
            if kind == "perMeter":
                sales = {"type": "perMeter",
                         "step": number(r["step_m"] or "1", "step_m", row),
                         "minimum": number(r["minimum_m"] or "0", "minimum_m", row)}
                if sales["step"] <= 0:
                    sys.exit(f"Row {row}: step_m must be > 0")
            elif kind == "fixedLengths":
                lengths = [number(x, "lengths_m", row) for x in r["lengths_m"].split(";") if x.strip()]
                if not lengths or min(lengths) <= 0:
                    sys.exit(f"Row {row}: lengths_m needs at least one length > 0")
                sales = {"type": "fixedLengths", "lengthsM": lengths}
            else:
                sys.exit(f"Row {row}: unknown sales_type {kind!r}")
            cables.append({
                "id": sku, "sku": sku, "name": r["name"].strip(),
                "crossSection": r["cross_section"].strip(), "use": r["use"].strip(),
                "pricePerMeter": number(r["price_per_meter"], "price_per_meter", row),
                "sales": sales, "stock": r["stock"].strip(),
                "imageUrl": r["image_url"].strip() or None,
                "productUrl": r["product_url"].strip() or "https://www.elektramat.nl",
                "isSample": False,
            })
            shop_id = (r.get("shop_product_id") or "").strip()
            if shop_id:
                if not shop_id.isdigit():
                    sys.exit(f"Row {row}: shop_product_id must be a whole number, got {shop_id!r}")
                cables[-1]["shopProductId"] = int(shop_id)
    if not cables:
        sys.exit("No cables in the export")
    json.dump(cables, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
