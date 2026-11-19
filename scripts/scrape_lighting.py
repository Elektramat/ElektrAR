#!/usr/bin/env python3
"""Fetch the smart-home lighting that mounts on a wall or ceiling from elektramat.nl.

Usage (from the repo root):
  python3 -I scripts/scrape_lighting.py                       # fetch the listing pages
  python3 -I scripts/scrape_lighting.py --cache-dir DIR       # reuse pages p1.html, p2.html, ...

Reads the category listing https://www.elektramat.nl/verlichting/smart-home-verlichting/
(page 1 up to the last page), keeps the products that hang on a wall or ceiling (see
CLASSES), and writes Kabelmeter/Resources/lights.json plus one photo per product to
Kabelmeter/Resources/LightImages/<sku>.jpg (300 px, bundled, so the app needs no network).
Runs on macOS (uses sips).

Waits 10 seconds between requests (Crawl-delay in elektramat.nl/robots.txt).
Prices are the consumer price including VAT on the day of the run.
Stops with an error on any failed request or missing field. Products that are skipped
are listed on stderr with the reason, so the selection can be reviewed.
"""
import argparse
import html
import json
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

BASE = "https://www.elektramat.nl/verlichting/smart-home-verlichting/"
USER_AGENT = "Mozilla/5.0 (Macintosh) Kabelmeter-hackathon"
DELAY_S = 10
TIMEOUT_S = 60
MAX_PAGES = 12
ROOT = Path(__file__).resolve().parent.parent
JSON_OUT = ROOT / "Kabelmeter/Resources/lights.json"
IMAGE_DIR = ROOT / "Kabelmeter/Resources/LightImages"

# How a product is mounted and what it looks like in AR. The first matching rule wins, so
# the specific words come first. `surface` is where it goes ("wall" or "ceiling"); `shape`
# picks the stand-in 3D model; `sizeMM` is [width, height, depth] of that model.
# Names that match none of these are skipped: bulbs, strips, controllers, free-standing
# lamps, ground spots and pendants do not mount flat on a wall or ceiling.
CLASSES = [
    (r"\binbouwspots?\b|\bdownlight\b|\binbouw.*spot|\bspot.*inbouw", "ceiling", "recessed", [90, 90, 30]),
    (r"\bopbouwspot\b|\bspot\s*1l\b", "ceiling", "surface", [100, 100, 60]),
    (r"\bspot\s*2l\b", "ceiling", "surface", [200, 100, 60]),
    (r"\bspot\s*3l\b", "ceiling", "surface", [300, 100, 60]),
    (r"\bspot\s*4l\b", "ceiling", "surface", [400, 100, 60]),
    (r"\bplafondlamp\b|\bplafonni[eè]re\b|\bplafondarmatuur\b|\bplafond\b|\bpaneel\b|\bpanel\b",
     "ceiling", "disc", [400, 400, 80]),
    (r"\bwandlamp\b|\bwandspot\b|\bwandarmatuur\b|\bbuitenlamp\b|\bbuitenspot\b|\bschijnwerper\b",
     "wall", "box", [180, 120, 100]),
]
# Shape and size for single products whose photo shows something else than the default.
OVERRIDES = {
    # Calex Smart Outdoor wandlamp up & down 760lm: a cylinder on a back plate.
    "401328664": ("cylinder", [80, 160, 110]),
    # Calex Smart Outdoor buiten wandlamp up & down 690lm: a small square box.
    "401328667": ("box", [100, 100, 100]),
}
# Words of products that do not mount flat on a wall or ceiling: bulbs, strips, controllers,
# free-standing lamps, ground and plinth lights, string lights.
SKIP_WORDS = (r"\b(strip|ledstrip|lichtstrip|light\s*bar|lichtslang|controller|bridge|gateway|hub|e14|e27|gu10|"
              r"led\s+lamp|kaars|filament|tuinspot|grondspots?|groundspot|prikspot|sokkellamp|party|gaming|"
              r"staande|vloerlamp|tafellamp|hanglamp|pendel|zonne)\b")


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
        if response.status != 200:
            sys.exit(f"{url}: HTTP {response.status}")
        return response.read()


def listing_pages(cache_dir):
    """Yields the HTML of every listing page, stopping after the last one."""
    page = 1
    last = 1
    while page <= last:
        cached = Path(cache_dir) / f"p{page}.html" if cache_dir else None
        if cached and cached.exists():
            text = cached.read_text(encoding="utf-8")
        else:
            if page > 1:
                time.sleep(DELAY_S)
            url = BASE if page == 1 else f"{BASE}?p={page}"
            text = fetch(url).decode("utf-8")
        numbers = [int(n) for n in re.findall(r"[?&]p=(\d+)", text)]
        last = min(max([last, *numbers]), MAX_PAGES)
        yield page, text
        page += 1


def products(text):
    """One dict per product card on a listing page."""
    cards = re.split(r'<div\s+class="h-full product-item">', text)[1:]
    for card in cards:
        link = re.search(r'<a\s+class="absolute inset-0 z-10"\s+href="([^"]+)"\s+data-sku="(\d+)"\s+'
                         r'data-title="([^"]*)"', card)
        if not link:
            sys.exit("product card without link, sku and title: the page layout changed")
        url, sku, title = link.group(1), link.group(2), html.unescape(link.group(3))
        price = re.search(r'data-price-amount="([\d.]+)"\s+data-price-type="finalPrice"', card)
        form = re.search(r'/checkout/cart/add/[^"]*/product/(\d+)/"', card)
        image = re.search(r'<img[^>]*\ssrc="([^"]+)"', card)
        yield {
            "sku": sku,
            "title": title,
            "url": url,
            "price": round(float(price.group(1)), 2) if price else None,
            "shopProductId": int(form.group(1)) if form else None,
            "image": html.unescape(image.group(1)) if image else None,
        }


def classify(title):
    """(surface, shape, sizeMM) or the reason it is skipped."""
    lowered = title.lower()
    if re.search(SKIP_WORDS, lowered):
        return None, "not a fixed wall or ceiling light"
    for pattern, surface, shape, size in CLASSES:
        if re.search(pattern, lowered):
            return (surface, shape, size), None
    return None, "no wall or ceiling keyword"


def brand_of(title):
    first = title.split()[0]
    return first.capitalize() if first.isupper() and len(first) > 4 else first


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache-dir", help="directory with p1.html, p2.html, ... from an earlier run")
    args = parser.parse_args()

    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    lights, seen, skipped = [], set(), []
    for page, text in listing_pages(args.cache_dir):
        found = list(products(text))
        print(f"page {page}: {len(found)} products", file=sys.stderr)
        for item in found:
            if item["sku"] in seen:
                continue
            seen.add(item["sku"])
            kind, reason = classify(item["title"])
            if kind is None:
                skipped.append((item["sku"], item["title"], reason))
                continue
            if item["price"] is None or item["shopProductId"] is None or item["image"] is None:
                skipped.append((item["sku"], item["title"], "not orderable: no price, cart form or photo"))
                continue
            if item["price"] <= 0:
                sys.exit(f"{item['sku']}: price must be > 0, got {item['price']}")
            surface, shape, size = kind
            shape, size = OVERRIDES.get(item["sku"], (shape, size))
            lights.append({"item": item, "surface": surface, "shape": shape, "size": size})

    for index, entry in enumerate(lights):
        item = entry["item"]
        photo = IMAGE_DIR / f"{item['sku']}.jpg"
        if not photo.exists():
            if index:
                time.sleep(DELAY_S)
            photo.write_bytes(fetch(item["image"]))
            # The site serves PNG; convert to JPEG, 300 px (the picker shows a small thumbnail).
            subprocess.run(["sips", "-s", "format", "jpeg", "-Z", "300", str(photo)], check=True,
                           capture_output=True, timeout=TIMEOUT_S)

    out = []
    for entry in lights:
        item = entry["item"]
        title = re.sub(r"\s*\(\d{6,}\)\s*$", "", item["title"])  # drop the trailing supplier code
        out.append({
            "id": item["sku"],
            "sku": item["sku"],
            "name": title,
            "brand": brand_of(title),
            "surface": entry["surface"],
            "shape": entry["shape"],
            "sizeMM": entry["size"],
            "price": item["price"],
            "productUrl": item["url"],
            "shopProductId": item["shopProductId"],
        })
    JSON_OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"\nKept {len(out)} lights, skipped {len(skipped)}:", file=sys.stderr)
    for sku, title, reason in skipped:
        print(f"  skipped {sku}  {title}  [{reason}]", file=sys.stderr)
    print(f"Wrote {len(out)} lights to {JSON_OUT.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    main()
