#!/bin/sh
# Copies the app's data into webapp/data, so the web app uses the same cables,
# photos, switches and 3D models. Run after changing Kabelmeter/Resources.
set -eu
cd "$(dirname "$0")/.."
src=Kabelmeter/Resources
dst=webapp/data
rm -rf "$dst"
mkdir -p "$dst"
cp "$src/cables.json" "$src/fixtures.json" "$dst/"
cp -R "$src/CableImages" "$dst/CableImages"
cp -R "$src/Models" "$dst/Models"
cp -R "$src/FixtureImages" "$dst/FixtureImages"
echo "Copied to $dst: $(ls "$dst/Models" | wc -l | tr -d ' ') models, $(ls "$dst/CableImages" | wc -l | tr -d ' ') photos"
