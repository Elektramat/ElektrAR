#!/usr/bin/env python3
"""Fetch cable data and photos from elektramat.nl product pages into the app.

Usage (from the repo root):
  python3 -I scripts/scrape_elektramat.py

Reads the schema.org Product data of each page in PRODUCTS, writes
Kabelmeter/Resources/cables.json and one photo per cable to
Kabelmeter/Resources/CableImages/<sku>.jpg, resized to 300 px
(bundled, so the app needs no network). Runs on macOS (uses sips).

Waits 10 seconds between requests (Crawl-delay in elektramat.nl/robots.txt).
Prices are the consumer price including VAT on the day of the run.
Stops with an error on any failed request or missing field.
"""
import html
import json
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

BASE = "https://www.elektramat.nl/"
USER_AGENT = "Mozilla/5.0 (Macintosh) Kabelmeter-hackathon"
DELAY_S = 10
TIMEOUT_S = 30
ROOT = Path(__file__).resolve().parent.parent
JSON_OUT = ROOT / "Kabelmeter/Resources/cables.json"
IMAGE_DIR = ROOT / "Kabelmeter/Resources/CableImages"

# (product page slug, use label shown in the app). All are sold per whole meter.
PRODUCTS = [
    ("ymvk-kabel-3x1-5-per-meter", "Verlichting"),
    ("ymvk-kabel-3x2-5-per-meter", "Stopcontacten"),
    ("ymvk-kabel-3x4-per-meter", "Zware groep"),
    ("ymvk-kabel-3x6-per-meter", "Zware groep"),
    ("ymvk-kabel-5x1-5-per-meter", "Krachtstroom"),
    ("ymvk-kabel-5x2-5-per-meter", "Kookgroep"),
    ("ymvk-kabel-5x4-per-meter", "Krachtstroom"),
    ("xmvk-kabel-3x1-5-per-meter", "Halogeenvrij"),
    ("xmvk-kabel-3x2-5-per-meter", "Halogeenvrij"),
    ("neopreen-kabel-h07rnf-3x1-5-per-meter", "Flexibel, buiten"),
    ("neopreen-kabel-h07rnf-3x2-5-per-meter", "Flexibel, buiten"),
    ("ymvk-as-grondkabel-3x2-5-per-meter", "Grondkabel"),
]

STOCK = {
    "https://schema.org/InStock": "Op voorraad",
    "https://schema.org/OutOfStock": "Niet op voorraad",
    "https://schema.org/BackOrder": "Nabestelling",
    "https://schema.org/PreOrder": "Pre-order",
}


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
        if response.status != 200:
            sys.exit(f"{url}: HTTP {response.status}")
        return response.read()


def product_data(page, url):
    for block in re.findall(r'<script type="application/ld\+json"[^>]*>(.*?)</script>', page, re.S):
        try:
            data = json.loads(block)
        except json.JSONDecodeError:
            continue
        if isinstance(data, dict) and data.get("@type") == "Product":
            return data
    sys.exit(f"{url}: no schema.org Product data on the page")


def cross_section(name, url):
    match = re.search(r"(\d+)\s*[xXgG]\s*(\d+(?:[.,]\d+)?)", name)
    if not match:
        sys.exit(f"{url}: no cross-section in name {name!r}")
    return f"{match.group(1)}x{match.group(2).replace('.', ',')} mm²"


def main():
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    cables, seen = [], set()
    for index, (slug, use) in enumerate(PRODUCTS):
        if index:
            time.sleep(DELAY_S)
        url = f"{BASE}{slug}/"
        data = product_data(fetch(url).decode("utf-8"), url)
        offer = data.get("offers") or {}
        sku, name, price = data.get("sku"), data.get("name"), offer.get("price")
        image = data.get("image")
        if not sku or not name or price is None or not image:
            sys.exit(f"{url}: missing sku, name, price or image")
        if sku in seen:
            sys.exit(f"{url}: duplicate sku {sku}")
        seen.add(sku)
        if float(price) <= 0:
            sys.exit(f"{url}: price must be > 0, got {price}")

        time.sleep(DELAY_S)
        photo = IMAGE_DIR / f"{sku}.jpg"
        photo.write_bytes(fetch(image))
        # The site serves some photos as PNG. Convert to JPEG, 300 px: the picker shows 52 pt.
        subprocess.run(["sips", "-s", "format", "jpeg", "-Z", "300", str(photo)], check=True, capture_output=True, timeout=TIMEOUT_S)

        display = html.unescape(name)
        display = re.sub(r"\s+per meter$", "", display, flags=re.I)
        display = re.sub(r"(\d)\.(\d)", r"\1,\2", display)
        cables.append({
            "id": sku,
            "sku": sku,
            "name": display,
            "crossSection": cross_section(display, url),
            "use": use,
            "pricePerMeter": round(float(price), 2),
            "sales": {"type": "perMeter", "step": 1, "minimum": 1},
            "stock": STOCK.get(offer.get("availability", ""), "Levertijd onbekend"),
            "imageUrl": image,
            "productUrl": offer.get("url") or url,
            "isSample": False,
        })
        print(f"{sku}  {display}  € {price}", file=sys.stderr)

    JSON_OUT.write_text(json.dumps(cables, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(cables)} cables to {JSON_OUT.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    main()
