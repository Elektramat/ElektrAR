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


def is_ceiling_light(path):
    from pxr import Usd
    stage = Usd.Stage.Open(str(path))  # keep the stage alive while reading its prim
    return stage.GetDefaultPrim().GetCustomData().get("surface") == "ceiling"


def render_ceiling(ax, path):
    """Ceiling lights: turn the model so its front (+Z) points down, and look from below at
    an angle, like the product photos. preview.render always looks at the front of a wall model."""
    import numpy as np
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection
    tris, cols = preview.load(str(path))
    elev, azim = np.radians(-28), np.radians(-60)
    view = np.array([np.cos(elev) * np.cos(azim), np.cos(elev) * np.sin(azim), np.sin(elev)])
    light = view + np.array([-0.35, 0.1, -0.25]); light /= np.linalg.norm(light)
    polys, colours = [], []
    for t, (base, rough) in zip(tris, cols):
        # model (x, y, z) -> plot (x, y, -z): the ceiling is at plot z = 0, the light hangs below it.
        q = np.column_stack([t[:, 0], t[:, 1], -t[:, 2]])
        # The mirror flips the winding, so flip the normal back to point outwards.
        n = -np.cross(q[1] - q[0], q[2] - q[0]); ln = np.linalg.norm(n)
        if ln < 1e-9:
            continue
        n /= ln
        if np.dot(n, view) < -0.05:
            continue  # back-face cull, like preview.render
        d = max(np.dot(n, light), 0)
        colours.append(np.clip(base * (0.42 + 0.58 * d), 0, 1))
        polys.append(q)
    ax.add_collection3d(Poly3DCollection(polys, facecolors=colours, edgecolors="none"))
    ax.view_init(elev=-28, azim=-60)
    ax.set_box_aspect((1, 1, 1)); ax.set_axis_off()
    return tris


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
        if is_ceiling_light(path):
            tris = render_ceiling(ax, path)
        else:
            preview.render(ax, str(path), "")
            ax.view_init(elev=12, azim=-72)
            tris, _ = preview.load(str(path))
        # Zoom to the model: half its largest size in mm, plus a margin for the 3D projection.
        lim = max(abs(v) for tri in tris for point in tri for v in point) * 0.95
        ax.set_xlim(-lim, lim); ax.set_ylim(-lim, lim); ax.set_zlim(-lim, lim)
        fig.savefig(OUT / f"{path.stem}.png", transparent=True)
        plt.close(fig)
    print(f"{len(models)} previews in {OUT.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    main()
