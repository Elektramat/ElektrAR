#!/usr/bin/env python3
"""Render one preview image per switch/socket model for the product pickers.

Usage (needs usd-core, matplotlib and numpy, e.g. in a virtualenv):
  pip install usd-core matplotlib numpy
  python scripts/render_fixture_previews.py

Reads Kabelmeter/Resources/Models/*.usdz and writes Kabelmeter/Resources/FixtureImages/<model>.png
(transparent background, 200 x 200 px). Uses the renderer of assets/busch-jaeger-usdz/preview.py,
so the images match the team's contact sheet. Run scripts/sync_webapp_data.sh afterwards to
update the web app.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "assets" / "busch-jaeger-usdz"))

import matplotlib.pyplot as plt  # noqa: E402
import preview  # noqa: E402  (sets the Agg backend)

MODELS = ROOT / "Kabelmeter" / "Resources" / "Models"
OUT = ROOT / "Kabelmeter" / "Resources" / "FixtureImages"
SIZE_PX = 200
DPI = 100


def main():
    OUT.mkdir(exist_ok=True)
    models = sorted(MODELS.glob("*.usdz"))
    for old in OUT.glob("*.png"):
        if not (MODELS / f"{old.stem}.usdz").exists():
            old.unlink()
    for path in models:
        fig = plt.figure(figsize=(SIZE_PX / DPI, SIZE_PX / DPI), dpi=DPI)
        fig.patch.set_alpha(0)
        ax = fig.add_axes([0, 0, 1, 1], projection="3d")
        ax.patch.set_alpha(0)
        preview.render(ax, str(path), "")
        ax.view_init(elev=12, azim=-72)
        # Zoom to the model: half its largest size in mm, plus a margin for the 3D projection.
        tris, _ = preview.load(str(path))
        lim = max(abs(v) for tri in tris for point in tri for v in point) * 0.95
        ax.set_xlim(-lim, lim); ax.set_ylim(-lim, lim); ax.set_zlim(-lim, lim)
        fig.savefig(OUT / f"{path.stem}.png", transparent=True)
        plt.close(fig)
    print(f"{len(models)} previews in {OUT.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    main()
