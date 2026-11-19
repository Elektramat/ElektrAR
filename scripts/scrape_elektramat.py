#!/usr/bin/env python3
"""Fetch cable data and photos from elektramat.nl product pages into the app.

Usage (from the repo root):
  python3 -I scripts/scrape_elektramat.py            # everything: cables per meter and per roll
  python3 -I scripts/scrape_elektramat.py --rolls    # only the roll cables; merged into cables.json

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

# Cables sold as separate roll products, one app cable with the roll sizes as options. Each roll is
# its own shop product with its own price (a shorter roll costs more per meter), so the app picks
# the cheapest combination of rolls that covers the length and posts each roll size separately.
# `rolls` is (product page slug, length in m); the first one gives the photo and the cable id.
# Name and cross-section are written here, because the shop names every roll "... per rol N meter".
ROLL_CABLES = [
    {
        "name": "Snelflex buis VD draad 3x2,5 mm² - 16 mm",
        "crossSection": "3x2,5 mm²",
        "use": "Inbouw, voorbedraad",
        "rolls": [
            ("snelflex-flexibele-buis-vd-draad-3x2-5mm2-16mm-per-rol-100-meter-sf3g25", 100),
            ("snelflex-flexibele-buis-vd-draad-3x2-5mm2-16mm-per-rol-50-meter-sf3g25m", 50),
            ("snelflex-flexibele-buis-vd-draad-3g2-5mm2-16mm-per-rol-25-meter-sf3g25k", 25),
        ],
    },
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


def fetch_product(slug):
    """Reads one product page: schema.org data and the shop's add-to-cart product id."""
    url = f"{BASE}{slug}/"
    page = fetch(url).decode("utf-8")
    data = product_data(page, url)
    # The add-to-cart form posts the shop's internal product id, which differs from
    # schema.org productID. The app posts it directly, without loading the page.
    form_id = re.search(r'action="[^"]*/checkout/cart/add/[^"]*/product/(\d+)/"\s*id="product_addtocart_form"', page)
    if not form_id:
        sys.exit(f"{url}: no add-to-cart form on the page")
    offer = data.get("offers") or {}
    sku, shop_name, price, image = data.get("sku"), data.get("name"), offer.get("price"), data.get("image")
    if not sku or not shop_name or price is None or not image:
        sys.exit(f"{url}: missing sku, name, price or image")
    if float(price) <= 0:
        sys.exit(f"{url}: price must be > 0, got {price}")
    return {
        "sku": sku, "name": html.unescape(shop_name), "price": float(price), "image": image,
        "stock": STOCK.get(offer.get("availability", ""), "Levertijd onbekend"),
        "url": offer.get("url") or url, "shopProductId": int(form_id.group(1)),
    }


def save_photo(sku, image):
    time.sleep(DELAY_S)
    photo = IMAGE_DIR / f"{sku}.jpg"
    photo.write_bytes(fetch(image))
    # The site serves some photos as PNG. Convert to JPEG, 300 px: the picker shows 52 pt.
    subprocess.run(["sips", "-s", "format", "jpeg", "-Z", "300", str(photo)], check=True, capture_output=True, timeout=TIMEOUT_S)


def scrape(slug, use):
    """A cable sold per meter."""
    product = fetch_product(slug)
    save_photo(product["sku"], product["image"])
    display = re.sub(r"\s+per meter$", "", product["name"], flags=re.I)
    display = re.sub(r"(\d)\.(\d)", r"\1,\2", display)
    print(f"{product['sku']}  {display}  € {product['price']}", file=sys.stderr)
    return {
        "id": product["sku"],
        "sku": product["sku"],
        "name": display,
        "crossSection": cross_section(display, f"{BASE}{slug}/"),
        "use": use,
        "pricePerMeter": round(product["price"], 2),
        "sales": {"type": "perMeter", "step": 1, "minimum": 1},
        "stock": product["stock"],
        "imageUrl": product["image"],
        "productUrl": product["url"],
        "isSample": False,
        "shopProductId": product["shopProductId"],
    }


def scrape_roll_cable(spec):
    """A cable sold as rolls of several lengths, each a separate shop product."""
    rolls = []
    for index, (slug, length) in enumerate(spec["rolls"]):
        if index:
            time.sleep(DELAY_S)
        product = fetch_product(slug)
        if index == 0:
            save_photo(product["sku"], product["image"])
            main = product
        rolls.append({
            "lengthM": float(length), "sku": product["sku"], "price": product["price"],
            "productUrl": product["url"], "shopProductId": product["shopProductId"], "stock": product["stock"],
        })
        print(f"{product['sku']}  {spec['name']}  rol {length} m  € {product['price']}", file=sys.stderr)
    rolls.sort(key=lambda r: -r["lengthM"])
    stocks = {r["stock"] for r in rolls}
    return {
        "id": main["sku"],
        "sku": main["sku"],
        "name": spec["name"],
        "crossSection": spec["crossSection"],
        "use": spec["use"],
        # Cheapest per meter (the longest roll); the real price depends on the rolls picked.
        "pricePerMeter": round(min(r["price"] / r["lengthM"] for r in rolls), 6),
        "sales": {"type": "fixedLengths", "lengthsM": [r["lengthM"] for r in rolls]},
        "rolls": rolls,
        "stock": "Op voorraad" if stocks == {"Op voorraad"} else "Niet alle rollen op voorraad",
        "imageUrl": main["image"],
        "productUrl": rolls[0]["productUrl"],
        "isSample": False,
        "shopProductId": rolls[0]["shopProductId"],
    }


def main():
    only_rolls = "--rolls" in sys.argv[1:]
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    cables = []
    if not only_rolls:
        for index, (slug, use) in enumerate(PRODUCTS):
            if index:
                time.sleep(DELAY_S)
            cables.append(scrape(slug, use))
    for spec in ROLL_CABLES:
        if cables:
            time.sleep(DELAY_S)
        cables.append(scrape_roll_cable(spec))

    ids = [c["id"] for c in cables]
    if len(set(ids)) != len(ids):
        sys.exit("duplicate sku in the product lists")
    if only_rolls:
        # Keep the cables already in the file; replace entries with the same sku, add new ones.
        existing = json.loads(JSON_OUT.read_text(encoding="utf-8")) if JSON_OUT.exists() else []
        fresh = {c["id"]: c for c in cables}
        cables = [fresh.pop(c["id"], c) for c in existing] + list(fresh.values())
    JSON_OUT.write_text(json.dumps(cables, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(cables)} cables to {JSON_OUT.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    main()
