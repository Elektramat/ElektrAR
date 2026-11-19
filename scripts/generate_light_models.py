#!/usr/bin/env python3
"""Generate an indicative 3D model (USDZ) for every scraped light in lights.json.

Usage (needs usd-core, numpy and matplotlib, e.g. in a virtualenv):
  pip install usd-core numpy matplotlib
  python scripts/generate_light_models.py
  python scripts/render_fixture_previews.py      # previews for the pickers

Writes Kabelmeter/Resources/Models/light-<sku>.usdz with the same conventions as the
Busch-Jaeger switches (assets/busch-jaeger-usdz/README.md): real size in metres, Y up,
pivot in the centre of the back, the back on the wall or ceiling at z = 0, +Z out of the
surface. Materials: Body, Diffuser (emissive, so it reads as light in AR), Glow, Reflector.

These are not CAD models of the products. The shape family and size come from lights.json
(scraped from elektramat.nl), the colour from the product name or else from the product
photo, the number of spot heads from the name ("3L"). Good enough to judge size and look on
a wall or ceiling; not a replacement for the product photo.
"""
import json
import math
import re
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "assets" / "busch-jaeger-usdz"))

import matplotlib.image as mpimg  # noqa: E402
from pxr import Gf, Sdf, Usd, UsdGeom, UsdUtils  # noqa: E402

import generate as g  # noqa: E402  (mesh helpers and USD export of the switch models)

RESOURCES = ROOT / "Kabelmeter" / "Resources"
MODELS = RESOURCES / "Models"
PHOTOS = RESOURCES / "LightImages"
TMP = ROOT / "assets" / "light-usd-tmp"

BLACK = (28, 28, 30)
ANTHRACITE = (58, 60, 64)
WHITE = (244, 244, 240)
DIFFUSER = (252, 250, 244)
GLOW = (255, 238, 205)
REFLECTOR = (198, 198, 196)
WARM_LIGHT = (1.0, 0.92, 0.78)


# --------------------------------------------------------------------------- colour
def body_colour(light):
    """Colour of the housing: from the name when it says so, else from the photo."""
    name = light["name"].lower()
    if "zwart" in name or "black" in name:
        return BLACK
    if re.search(r"\bwit\b|white", name):
        return WHITE
    photo = PHOTOS / f"{light['sku']}.jpg"
    if not photo.exists():
        return WHITE
    img = mpimg.imread(photo).astype(float)
    if img.max() <= 1.0:
        img *= 255
    rgb = img[..., :3].reshape(-1, 3)
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722])
    sat = rgb.max(1) - rgb.min(1)
    # The product: not the white background, not the coloured RGB glow in the marketing shots.
    product = lum[(lum < 232) & (sat < 40)]
    if len(product) < 200:
        return WHITE
    median = float(np.median(product))
    if median < 80:
        return BLACK
    if median < 150:
        return ANTHRACITE
    return WHITE


# --------------------------------------------------------------------------- shapes (mm)
def cylinder(radius, z0, z1, n=96, edge=0.0):
    """Closed cylinder along Z, optionally with a rounded front edge."""
    c = g.circle(radius, n)
    rings = [g.ring(c, z0)]
    if edge > 0:
        for k in range(1, 7):
            phi = (math.pi / 2) * k / 6
            inset = edge * (1 - math.cos(phi))
            rings.append(g.ring(g.circle(radius - inset, n), z1 - edge + edge * math.sin(phi)))
    else:
        rings.append(g.ring(c, z1))
    return g.Mesh().loft(rings, cap_start=z0, cap_end=z1)


def rounded_box(half_w, half_h, z0, z1, corner, edge):
    """Box along Z with rounded corners and a rounded front edge (like the opbouw housing)."""
    corner = min(corner, half_w, half_h)
    edge = min(edge, (z1 - z0) / 2, corner)
    rings = [g.ring(g.rrect(half_w, half_h, corner), z0)]
    rings += g.bevel_rings(half_w, half_h, corner, z1, edge, steps=5)
    return g.Mesh().loft(rings, cap_start=z0, cap_end=z1)


def disc(radius, z, n=96):
    """Flat disc facing +Z (a lens or diffuser face)."""
    c = g.circle(radius, n)
    return g.Mesh().loft([g.ring(c, z - 0.3), g.ring(c, z)], cap_start=z - 0.3, cap_end=z)


def annulus(r_in, r_out, z, n=96):
    """Flat ring facing +Z, slightly proud (the RGB halo ring)."""
    outer = g.circle(r_out, n)
    inner = g.circle(r_in, n)
    return g.Mesh().loft([g.ring(inner, z), g.ring(outer, z), g.ring(outer, z - 0.4), g.ring(inner, z - 0.4)],
                         closed=True)


def transformed(mesh, rotation=None, offset=(0.0, 0.0, 0.0)):
    """Rotate (3x3) and move every vertex of a mesh."""
    r = np.eye(3) if rotation is None else rotation
    mesh.v = [np.asarray(v) @ r.T + np.asarray(offset) for v in mesh.v]
    return mesh


def rot_x(deg):
    a = math.radians(deg)
    return np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])


def rot_y(deg):
    a = math.radians(deg)
    return np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])


# --------------------------------------------------------------------------- product families
def recessed(w, depth, halo):
    """Inbouwspot: a bezel on the ceiling, a reflector cone into the ceiling, the lens deep inside."""
    r_out, r_in = w / 2, w * 0.33
    bezel_h = 3.5
    rings = [g.ring(g.circle(r_out), 0.0)]
    for k in range(1, 6):
        phi = (math.pi / 2) * k / 5
        rings.append(g.ring(g.circle(r_out - 2.0 * (1 - math.cos(phi))), bezel_h - 2.0 + 2.0 * math.sin(phi)))
    rings.append(g.ring(g.circle(r_in + 1.0), bezel_h))
    rings.append(g.ring(g.circle(r_in), bezel_h - 1.0))
    cone_floor = -min(depth * 0.5, 16.0)
    rings.append(g.ring(g.circle(r_in * 0.62), cone_floor))
    parts = [("Body", g.Mesh().loft(rings, cap_start=0.0, cap_end=cone_floor))]
    parts.append(("Diffuser", disc(r_in * 0.55, cone_floor + 0.6)))
    if halo:
        parts.append(("Glow", annulus(r_in + 2.0, r_in + 5.0, bezel_h + 0.15)))
    return parts


def ceiling_disc(w, depth, halo):
    """Plafondlamp: a drum housing with a slightly domed diffuser."""
    r = w / 2
    side = depth * 0.72
    parts = [("Body", cylinder(r, 0.0, side, edge=4.0))]
    dome = [g.ring(g.circle(r - 7.0), side - 0.5)]
    for t in (0.35, 0.65, 0.88, 1.0):
        dome.append(g.ring(g.circle((r - 7.0) * math.cos(t * math.pi / 2.6)), side + (depth - side) * math.sin(t * math.pi / 2)))
    parts.append(("Diffuser", g.Mesh().loft(dome, cap_start=side - 0.5, cap_end=depth)))
    if halo:
        parts.append(("Glow", annulus(r - 7.0, r - 3.0, side + 0.3)))
    return parts


def spot_heads(length, width, depth, count, round_base):
    """Opbouwspot: a base on the ceiling with 1 to 4 tilted cylindrical heads."""
    base_h = 14.0
    parts = []
    if round_base or count == 1:
        base_r = 42.0 if count == 1 else min(length / 2, 95.0)
        parts.append(("Body", cylinder(base_r, 0.0, base_h, edge=3.0)))
        if count == 1:
            centres = [(0.0, 0.0)]
        else:
            centres = [(base_r * 0.55 * math.cos(2 * math.pi * i / count + math.pi / 2),
                        base_r * 0.55 * math.sin(2 * math.pi * i / count + math.pi / 2)) for i in range(count)]
    else:
        parts.append(("Body", rounded_box(length / 2, 22.0, 0.0, base_h, 20.0, 3.0)))
        step = (length - 70.0) / max(count - 1, 1)
        centres = [(-(length - 70.0) / 2 + i * step, 0.0) for i in range(count)]

    head_r = 27.0
    head_len = max(depth * 1.4, 70.0)
    for i, (x, y) in enumerate(centres):
        # Short stem from the base, then a head tilted 40 degrees towards the room.
        parts.append(("Body", transformed(cylinder(5.0, 0.0, 16.0), offset=(x, y, base_h - 1.0))))
        tilt = rot_x(40 if i % 2 == 0 else -40) if count > 1 else rot_x(0)
        head = cylinder(head_r, -head_len / 2, head_len / 2, edge=3.0)
        lens = disc(head_r * 0.72, head_len / 2 + 0.4)
        centre = (x, y, base_h + 16.0 + head_r)
        parts.append(("Body", transformed(head, tilt, centre)))
        parts.append(("Diffuser", transformed(lens, tilt, centre)))
    return parts


def surface_cylinder(w, depth):
    """A single ceiling-mounted cylinder (opbouw downlight)."""
    r = w * 0.4
    length = max(depth, w)
    return [("Body", cylinder(r, 0.0, length, edge=2.5)),
            ("Reflector", disc(r - 3.0, length + 0.3)),
            ("Diffuser", disc(r * 0.45, length + 0.7))]


def wall_up_down(w, h, depth):
    """Wandlamp up & down: a cube off a back plate, with light slits on top and bottom."""
    parts = [("Body", rounded_box(w * 0.32, h * 0.32, 0.0, 8.0, 4.0, 1.0)),
             ("Body", rounded_box(w / 2, h / 2, 8.0, depth, 2.0, 1.2))]
    for sign in (1, -1):
        # A flat slit lying on the top and bottom face (thin in Y, long in X, along the depth).
        slit = rounded_box(w * 0.38, 1.2, -(depth - 8.0) * 0.3, (depth - 8.0) * 0.3, 1.0, 0.4)
        parts.append(("Diffuser", transformed(slit, offset=(0, sign * (h / 2 + 0.6), 8.0 + (depth - 8.0) / 2))))
    return parts


def wall_cylinder(w, h, depth):
    """Wandlamp: a back plate and a vertical cylinder that lights up and down."""
    r = w / 2
    plate = rounded_box(w * 0.32, h * 0.3, 0.0, 10.0, 5.0, 1.5)
    centre_z = depth - r
    body = transformed(cylinder(r, -h / 2, h / 2, edge=2.0), rot_x(-90), (0, 0, centre_z))
    arm = rounded_box(10.0, 14.0, 10.0, centre_z, 3.0, 0.5)
    parts = [("Body", plate), ("Body", arm), ("Body", body)]
    for sign in (1, -1):
        parts.append(("Glow", transformed(annulus(r - 6.0, r - 2.0, 0.0), rot_x(-90 * sign), (0, sign * (h / 2 + 0.5), centre_z))))
    return parts


def floodlight(w, h, depth, panels, sensor):
    """Schijnwerper: a wall bracket with one or two tilted LED panels and an optional sensor."""
    parts = [("Body", rounded_box(32.0, 24.0, 0.0, 34.0, 6.0, 2.0))]
    panel_w = w / panels - (6.0 if panels > 1 else 0.0)
    panel_h = h * 0.7
    for i in range(panels):
        x = 0.0 if panels == 1 else (i - 0.5) * (panel_w + 12.0)
        rotation = rot_x(-22) @ (rot_y(14 * (1 if i else -1)) if panels > 1 else np.eye(3))
        centre = (x, h * 0.18, depth * 0.62)
        parts.append(("Body", transformed(rounded_box(panel_w / 2, panel_h / 2, -14.0, 14.0, 6.0, 2.0), rotation, centre)))
        parts.append(("Diffuser", transformed(rounded_box(panel_w / 2 - 7.0, panel_h / 2 - 7.0, 13.0, 14.6, 3.0, 0.5),
                                              rotation, centre)))
    if sensor:
        parts.append(("Body", rounded_box(26.0, 14.0, 0.0, 40.0, 6.0, 2.0)))
        dome = cylinder(13.0, 0.0, 10.0, edge=6.0)
        parts.append(("Reflector", transformed(dome, rot_x(90), (0, -h * 0.32, 26.0))))
    return parts


def wall_box(w, h, depth, oval):
    """Wandlamp (bulkhead): a housing with a framed diffuser on the front."""
    corner = min(w, h) / 2 - 1 if oval else 8.0
    return [("Body", rounded_box(w / 2, h / 2, 0.0, depth * 0.75, corner, 4.0)),
            ("Diffuser", rounded_box(w / 2 - 12.0, h / 2 - 12.0, depth * 0.75 - 1.0, depth,
                                     max(corner - 12.0, 2.0), 3.0))]


def parts_for(light):
    name = light["name"].lower()
    w, h, depth = (float(v) for v in light["sizeMM"])
    halo = "halo" in name
    shape = light["shape"]
    if shape == "recessed":
        return recessed(w, depth, halo)
    if shape == "disc":
        return ceiling_disc(w, depth, halo)
    if shape == "surface":
        count_match = re.search(r"\b(\d)l\b", name)
        if count_match:
            return spot_heads(w, h, depth, int(count_match.group(1)), "rond" in name)
        return surface_cylinder(w, depth)
    if shape == "cylinder":
        return wall_cylinder(w, h, depth)
    if "up & down" in name or "up&down" in name:
        return wall_up_down(w, h, depth)
    if "schijnwerper" in name or "sensor" in name:
        return floodlight(w, h, depth, 2 if "duo" in name else 1, "sensor" in name)
    return wall_box(w, h, depth, "ovaal" in name)


# --------------------------------------------------------------------------- export
def material(stage, key, rgb, finish, emissive=None):
    mat = g.make_material(stage, f"/Root/Materials/{key}", rgb, finish)
    if emissive is not None:
        shader = stage.GetPrimAtPath(f"/Root/Materials/{key}/PreviewSurface")
        from pxr import UsdShade
        UsdShade.Shader(shader).CreateInput("emissiveColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*emissive))
    return mat


def build(light):
    slug = f"light-{light['sku']}"
    TMP.mkdir(parents=True, exist_ok=True)
    usdc = TMP / f"{slug}.usdc"
    stage = Usd.Stage.CreateNew(str(usdc))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, "/Root")
    stage.SetDefaultPrim(root.GetPrim())
    prim = root.GetPrim()
    # AR Quick Look: wall lights snap to walls. Ceiling lights get no Quick Look anchoring;
    # the app places them on the ceiling itself.
    if light["surface"] == "wall":
        prim.AddAppliedSchema("Preliminary_AnchoringAPI")
        prim.CreateAttribute("preliminary:anchoring:type", Sdf.ValueTypeNames.Token).Set("plane")
        prim.CreateAttribute("preliminary:planeAnchoring:alignment", Sdf.ValueTypeNames.Token).Set("vertical")
    UsdGeom.ModelAPI.Apply(prim)
    Usd.ModelAPI(prim).SetKind("component")

    colour = body_colour(light)
    materials = {
        "Body": material(stage, "Body", colour, "satin"),
        "Diffuser": material(stage, "Diffuser", DIFFUSER, "matte", emissive=WARM_LIGHT),
        "Glow": material(stage, "Glow", GLOW, "matte", emissive=WARM_LIGHT),
        "Reflector": material(stage, "Reflector", REFLECTOR, "metallic"),
    }
    for index, (key, mesh) in enumerate(parts_for(light)):
        g.add_mesh(stage, f"/Root/Geom/{key}{index}", mesh, materials[key])

    prim.SetCustomData(dict(sku=light["sku"], name=light["name"], shape=light["shape"],
                            surface=light["surface"], size_mm=light["sizeMM"], indicative=True,
                            colour="zwart" if colour == BLACK else "antraciet" if colour == ANTHRACITE else "wit"))
    stage.GetRootLayer().Save()

    usdz = MODELS / f"{slug}.usdz"
    if usdz.exists():
        usdz.unlink()
    assert UsdUtils.CreateNewARKitUsdzPackage(Sdf.AssetPath(str(usdc)), str(usdz)), slug
    return usdz


def main():
    lights = json.loads((RESOURCES / "lights.json").read_text())
    for light in lights:
        path = build(light)
        print("✓", path.name, light["shape"], light["name"][:60])
    for leftover in TMP.glob("*.usdc"):
        leftover.unlink()
    TMP.rmdir()
    print(len(lights), "light models in", MODELS.relative_to(ROOT), file=sys.stderr)


if __name__ == "__main__":
    main()
