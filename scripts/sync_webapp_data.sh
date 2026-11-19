#!/bin/sh
# Copies the app's data into webapp/data, so the web app uses the same cables,
# photos, switches and 3D models. Run after changing Kabelmeter/Resources.
# Only the models and previews of fixtures.json are copied (not the lights).
set -eu
cd "$(dirname "$0")/.."
src=Kabelmeter/Resources
dst=webapp/data
rm -rf "$dst"
mkdir -p "$dst/Models" "$dst/FixtureImages"
cp "$src/cables.json" "$src/fixtures.json" "$dst/"
cp -R "$src/CableImages" "$dst/CableImages"
python3 -I -c 'import json,sys; print("\n".join(sorted({f["model"] for f in json.load(open(sys.argv[1]))})))' "$src/fixtures.json" |
while read -r model; do
  cp "$src/Models/$model.usdz" "$dst/Models/"
  cp "$src/FixtureImages/$model.png" "$dst/FixtureImages/"
done
echo "Copied to $dst: $(ls "$dst/Models" | wc -l | tr -d ' ') models, $(ls "$dst/CableImages" | wc -l | tr -d ' ') photos"
