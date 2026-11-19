"""
Parametric USDZ generator for Busch-Jaeger schakelmateriaal (1-gang light switch + socket).

Conventions (ARKit / RealityKit / AR Quick Look):
  * Units: metres (metersPerUnit = 1), Y-up.
  * Origin: centre of the back face, which sits flat on the wall at z = 0.
  * +Z points out of the wall (towards the viewer), +Y is up, +X is right.

Geometry is built in millimetres and scaled to metres on export.
Dimensions come from Busch-Jaeger datasheets / product listings (see LINES).
"""
import json, math, os, sys
import numpy as np
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, Vt, UsdUtils

MM = 0.001
N = 160  # points per contour

# --------------------------------------------------------------------------- colours
def srgb_to_linear(c):
    c = np.asarray(c, float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

FINISH = {
    "gloss":    dict(roughness=0.28, metallic=0.0, clearcoat=0.6, clearcoatRoughness=0.08),
    "satin":    dict(roughness=0.48, metallic=0.0, clearcoat=0.0, clearcoatRoughness=0.0),
    "matte":    dict(roughness=0.72, metallic=0.0, clearcoat=0.0, clearcoatRoughness=0.0),
    "metallic": dict(roughness=0.38, metallic=0.85, clearcoat=0.3, clearcoatRoughness=0.15),
}

C = {  # sRGB approximations of the RAL references Busch-Jaeger quotes
    "creme":        (234, 228, 206),  # RAL 1013-ish (Duro 2000 SI)
    "alpinwit":     (241, 238, 228),  # RAL 9010
    "studiowit":    (246, 246, 241),  # RAL 9016
    "zwart":        (22, 22, 24),     # RAL 9005
    "antraciet":    (64, 67, 71),
    "antraciet_c":  (48, 51, 54),     # RAL 7021 (carat)
    "aluzilver":    (178, 180, 183),
    "ivoorwit":     (233, 224, 200),
    "metal":        (200, 200, 198),
    "hole":         (8, 8, 8),
}

def cw(frame, ffin, insert=None, ifin=None):
    return dict(frame=(frame, ffin), insert=(insert or frame, ifin or ffin))

# --------------------------------------------------------------------------- product lines
# frame: outer size (mm), T: frame thickness, r: corner radius, e: top-edge rounding radius
# ins: rocker / centre plate size, ir: its corner radius, ie: its edge radius, crown: dome height
# h_sw / h_so: build height from wall for switch / socket (datasheet "Aufbauhöhe")
LINES = {
    "busch-duro-2000-si": dict(
        name="Busch-Duro 2000 SI", frame=81, T=11, r=11, e=4.5, ins=54, ir=7, ie=3.0, crown=1.4,
        h_sw=18, h_so=14,
        colours={"creme": cw("creme", "gloss")}),
    "reflex-si": dict(
        name="Reflex SI", frame=81, T=11, r=11, e=4.5, ins=54, ir=7, ie=3.0, crown=1.4,
        h_sw=18, h_so=14,
        colours={"alpinwit": cw("alpinwit", "gloss")}),
    "art-linear": dict(
        name="Busch-art linear", frame=85, T=8.6, r=3, e=1.0, ins=69.5, ir=2.5, ie=0.8, crown=0.25,
        h_sw=16.2, h_so=14.1,
        colours={"zwart-mat": cw("zwart", "matte"), "studiowit": cw("studiowit", "matte")}),
    "future-linear": dict(
        name="future linear", frame=80, T=11, r=2.5, e=1.6, ins=63, ir=2.2, ie=1.0, crown=0.5,
        h_sw=17, h_so=14,
        colours={
            "zwart-mat": cw("zwart", "matte"),
            "antraciet": cw("antraciet", "satin"),
            "aluzilver": cw("aluzilver", "metallic"),
            "studiowit": cw("studiowit", "gloss"),
            "studiowit-mat": cw("studiowit", "matte"),
        }),
    "busch-balance-si": dict(
        name="Busch-balance SI", frame=81, T=12, r=6, e=3.0, ins=55, ir=4, ie=2.0, crown=0.9,
        h_sw=18, h_so=14,
        colours={"zuiver-wit": cw("alpinwit", "gloss"), "mat-zwart": cw("zwart", "matte")}),
    "solo": dict(
        name="solo", frame=87, T=11, r=2.5, e=1.2, ins=63, ir=2.0, ie=0.9, crown=0.3,
        h_sw=17, h_so=14, shadow_gap=True,
        colours={"studiowit": cw("studiowit", "gloss")}),
    "carat": dict(
        name="carat", frame=107, T=7, r=3, e=0.8, ins=63, ir=2.0, ie=0.9, crown=0.3,
        h_sw=17, h_so=14,
        colours={
            "ivoorwit": cw("ivoorwit", "gloss"),
            "studiowit": cw("studiowit", "gloss"),
            "antraciet": cw("antraciet_c", "satin"),
        }),
    "busch-axcent": dict(
        name="Busch-axcent", frame=91, T=11, r=4, e=2.0, ins=63, ir=2.0, ie=1.0, crown=0.4,
        h_sw=17, h_so=14,
        colours={"studiowit": cw("studiowit", "gloss")}),
    "alpha": dict(
        name="alpha", frame=81, T=11, r=10, e=5.0, ins=55, ir=5, ie=2.5, crown=1.2,
        h_sw=18, h_so=14, approx=True,
        colours={"studiowit": cw("studiowit", "gloss")}),
}

# Surface-mount ("opbouw") variants: housing behind the frame.
OPBOUW = [("reflex-si", "alpinwit", 81, 85, 32), ("future-linear", "studiowit", 80, 85, 32)]

PRODUCTS = {"schakelaar": "Wipschakelaar 1-voudig", "stopcontact": "Wandcontactdoos 1-voudig met randaarde"}

# --------------------------------------------------------------------------- 2D contours
def resample(P, n):
    Q = np.vstack([P, P[:1]])
    seg = np.linalg.norm(np.diff(Q, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    t = np.linspace(0, cum[-1], n, endpoint=False)
    return np.stack([np.interp(t, cum, Q[:, 0]), np.interp(t, cum, Q[:, 1])], 1)

def rrect(a, b, r, n=N):
    """Rounded rectangle, half extents a,b, corner radius r, arc-length sampled from (+a,0) CCW."""
    r = float(np.clip(r, 0.05, min(a, b)))
    th = np.linspace(0, 2 * np.pi, 24000, endpoint=False)
    c, s = np.abs(np.cos(th)), np.abs(np.sin(th))
    with np.errstate(divide="ignore", invalid="ignore"):
        t = np.minimum(np.where(c > 1e-12, a / c, np.inf), np.where(s > 1e-12, b / s, np.inf))
    x, y = t * c, t * s
    cx, cy = a - r, b - r
    corner = (x > cx) & (y > cy)
    B = -2 * (c * cx + s * cy)
    Cc = cx * cx + cy * cy - r * r
    tc = (-B + np.sqrt(np.maximum(B * B - 4 * Cc, 0))) / 2
    t = np.where(corner, tc, t)
    return resample(np.stack([t * np.cos(th), t * np.sin(th)], 1), n)

def circle(R, n=N):
    th = np.linspace(0, 2 * np.pi, n, endpoint=False)
    return np.stack([R * np.cos(th), R * np.sin(th)], 1)

def ring(c2, z, dx=0.0, dy=0.0):
    return np.column_stack([c2[:, 0] + dx, c2[:, 1] + dy, np.full(len(c2), z)])

# --------------------------------------------------------------------------- mesh building
class Mesh:
    def __init__(self):
        self.v, self.f = [], []
        self.nv = 0

    def loft(self, rings, closed=False, cap_start=None, cap_end=None):
        """Connect consecutive rings with quads. caps: z height of fan centre (or None)."""
        base = self.nv
        n = len(rings[0])
        for r in rings:
            self.v.append(np.asarray(r, float))
        self.nv += n * len(rings)
        m = len(rings)
        for i in range(m - 1 + (1 if closed else 0)):
            i0, i1 = base + i * n, base + ((i + 1) % m) * n
            for j in range(n):
                j1 = (j + 1) % n
                self.f.append([i0 + j, i0 + j1, i1 + j1, i1 + j])
        if cap_start is not None:
            c = rings[0][:, :2].mean(0)
            self.v.append(np.array([[c[0], c[1], cap_start]])); ci = self.nv; self.nv += 1
            for j in range(n):
                self.f.append([ci, base + (j + 1) % n, base + j])
        if cap_end is not None:
            c = rings[-1][:, :2].mean(0)
            self.v.append(np.array([[c[0], c[1], cap_end]])); ci = self.nv; self.nv += 1
            e = base + (m - 1) * n
            for j in range(n):
                self.f.append([ci, e + j, e + (j + 1) % n])
        return self

    def arrays(self):
        V = np.vstack(self.v)
        F = self.f
        # make orientation outward (positive signed volume)
        vol = 0.0
        for f in F:
            for k in range(1, len(f) - 1):
                vol += np.dot(V[f[0]], np.cross(V[f[k]], V[f[k + 1]]))
        if vol < 0:
            F = [list(reversed(f)) for f in F]
        return V, F

def face_normals(V, F):
    out = []
    for f in F:
        p = V[f]
        n = np.zeros(3)
        for i in range(len(f)):  # Newell
            a, b = p[i], p[(i + 1) % len(f)]
            n += np.array([(a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])])
        out.append(n)
    out = np.array(out)
    area = np.linalg.norm(out, axis=1, keepdims=True)
    return out / np.maximum(area, 1e-12), area[:, 0]

def crease_normals(V, F, angle_deg=38):
    fn, fa = face_normals(V, F)
    cos_t = math.cos(math.radians(angle_deg))
    adj = [[] for _ in range(len(V))]
    for fi, f in enumerate(F):
        for vi in f:
            adj[vi].append(fi)
    out = []
    for fi, f in enumerate(F):
        for vi in f:
            acc = np.zeros(3)
            for fj in adj[vi]:
                if np.dot(fn[fi], fn[fj]) >= cos_t:
                    acc += fn[fj] * fa[fj]
            nrm = np.linalg.norm(acc)
            out.append(acc / nrm if nrm > 1e-12 else fn[fi])
    return np.array(out)

# --------------------------------------------------------------------------- parts
def bevel_rings(a, b, r, z_top, e, steps=6, dx=0.0, dy=0.0):
    """Quarter-round edge from vertical wall (at z_top-e) to top face (inset e)."""
    rings = []
    for k in range(steps + 1):
        phi = (math.pi / 2) * k / steps
        inset = e * (1 - math.cos(phi))
        z = z_top - e + e * math.sin(phi)
        rings.append(ring(rrect(a - inset, b - inset, r - inset), z, dx, dy))
    return rings

def frame_mesh(L, z0=0.0, wide=None):
    A = L["frame"] / 2
    Bh = (wide or L["frame"]) / 2
    T, r, e = L["T"], L["r"], L["e"]
    inner = L["ins"] / 2 + 0.6
    ir = L["ir"] + 0.6
    rings = []
    if L.get("shadow_gap"):
        g = 3.0
        rings.append(ring(rrect(A - g, Bh - g, max(r - g, 0.5)), z0))
        rings.append(ring(rrect(A - g, Bh - g, max(r - g, 0.5)), z0 + 1.8))
        rings.append(ring(rrect(A, Bh, r), z0 + 1.8))
    else:
        rings.append(ring(rrect(A, Bh, r), z0))
    rings += bevel_rings(A, Bh, r, z0 + T, e)
    # top face towards the opening, then a small chamfer and the inner wall
    rings.append(ring(rrect(inner + 0.7, inner + 0.7, ir + 0.7), z0 + T))
    rings.append(ring(rrect(inner, inner, ir), z0 + T - 0.7))
    rings.append(ring(rrect(inner, inner, ir), z0 + 1.0))
    return Mesh().loft(rings, closed=True)

def rocker_mesh(L, z_top, z0):
    a = L["ins"] / 2
    r, e, crown = L["ir"], L["ie"], L["crown"]
    z_bottom = z0 + L["T"] - 3.0
    rings = [ring(rrect(a, a, r), z_bottom)]
    rings += bevel_rings(a, a, r, z_top, e)
    ai = a - e
    for s in (0.8, 0.6, 0.4, 0.2):
        rings.append(ring(rrect(ai * s, ai * s, max((r - e) * s, 0.3)), z_top + crown * (1 - s * s)))
    return Mesh().loft(rings, cap_start=z_bottom, cap_end=z_top + crown)

RECESS_R = 19.5      # Schuko recess Ø 39 mm
RECESS_DEPTH = 17.5  # from centre-plate face
PIN_SPACING = 19.0
PIN_D = 4.8

def socket_plate_mesh(L, z_top, z0):
    a = L["ins"] / 2
    r, e, crown = L["ir"], L["ie"], L["crown"] * 0.6
    z_bottom = z0 + L["T"] - 3.0
    rings = [ring(rrect(a, a, r), z_bottom)]
    rings += bevel_rings(a, a, r, z_top, e)
    sq = rrect(a - e, a - e, max(r - e, 0.3))
    ci = circle(RECESS_R + 1.2)
    for t in (0.33, 0.66, 1.0):  # morph rounded square -> circle across the face (slight dome)
        c2 = sq * (1 - t) + ci * t
        rings.append(ring(c2, z_top + crown * math.sin(math.pi * t / 2)))
    zt = z_top + crown
    rings.append(ring(circle(RECESS_R), zt - 1.2))
    z_floor = zt - RECESS_DEPTH
    rings.append(ring(circle(RECESS_R), z_floor))
    return Mesh().loft(rings, cap_start=z_bottom, cap_end=z_floor), z_floor

def socket_details(z_floor, z_top):
    holes = Mesh()
    for sx in (-1, 1):
        c = circle(PIN_D / 2, 48)
        holes.loft([ring(c, z_floor + 0.02, sx * PIN_SPACING / 2), ring(c, z_floor + 0.35, sx * PIN_SPACING / 2)],
                   cap_start=z_floor + 0.02, cap_end=z_floor + 0.35)
    clips = Mesh()
    for sy in (-1, 1):  # earthing clips on the recess wall, top and bottom
        w, d = 6.0, 1.2
        y0 = sy * (RECESS_R - d / 2 - 0.05)
        box = rrect(w / 2, d / 2, 0.3, 32)
        clips.loft([ring(box, z_floor + 2.0, 0, y0), ring(box, z_top - 3.0, 0, y0)],
                   cap_start=z_floor + 2.0, cap_end=z_top - 3.0)
    return holes, clips

def opbouw_mesh(w, h, depth):
    a, b = w / 2, h / 2
    rings = [ring(rrect(a, b, 6), 0.0)]
    rings += bevel_rings(a, b, 6, depth, 1.5, steps=4)
    return Mesh().loft(rings, cap_start=0.0, cap_end=depth)

# --------------------------------------------------------------------------- USD export
def make_material(stage, path, rgb, finish):
    mat = UsdShade.Material.Define(stage, path)
    sh = UsdShade.Shader.Define(stage, path + "/PreviewSurface")
    sh.CreateIdAttr("UsdPreviewSurface")
    sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*map(float, srgb_to_linear(rgb))))
    for k, v in FINISH[finish].items():
        sh.CreateInput(k, Sdf.ValueTypeNames.Float).Set(float(v))
    mat.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), "surface")
    return mat

def add_mesh(stage, path, mesh, material):
    V, F = mesh.arrays()
    nrm = crease_normals(V, F)
    m = UsdGeom.Mesh.Define(stage, path)
    pts = (V * MM).astype(np.float32)
    m.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(pts))
    m.CreateFaceVertexCountsAttr(Vt.IntArray([len(f) for f in F]))
    m.CreateFaceVertexIndicesAttr(Vt.IntArray([i for f in F for i in f]))
    m.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(nrm.astype(np.float32)))
    m.SetNormalsInterpolation(UsdGeom.Tokens.faceVarying)
    m.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
    m.CreateDoubleSidedAttr(False)
    m.CreateExtentAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, pts.min(0))), Gf.Vec3f(*map(float, pts.max(0)))]))
    UsdShade.MaterialBindingAPI.Apply(m.GetPrim()).Bind(material)
    return V, F

def build(line_id, colour_id, product, opbouw=None, outdir="out"):
    L = LINES[line_id]
    col = L["colours"][colour_id]
    slug = f"busch-jaeger_{line_id}_{colour_id}_{product}" + ("_opbouw" if opbouw else "")
    usdc = os.path.join(outdir, "_tmp", slug + ".usdc")
    os.makedirs(os.path.dirname(usdc), exist_ok=True)

    stage = Usd.Stage.CreateNew(usdc)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, "/Root")
    stage.SetDefaultPrim(root.GetPrim())
    rp = root.GetPrim()
    # AR Quick Look: place on vertical planes
    rp.AddAppliedSchema("Preliminary_AnchoringAPI")
    rp.CreateAttribute("preliminary:anchoring:type", Sdf.ValueTypeNames.Token).Set("plane")
    rp.CreateAttribute("preliminary:planeAnchoring:alignment", Sdf.ValueTypeNames.Token).Set("vertical")
    UsdGeom.ModelAPI.Apply(rp)
    Usd.ModelAPI(rp).SetKind("component")

    mats = {}
    def mat(key, rgb, fin):
        if key not in mats:
            mats[key] = make_material(stage, f"/Root/Materials/{key}", C[rgb], fin)
        return mats[key]

    frame_m = mat("Frame", *col["frame"])
    ins_m = mat("Insert", *col["insert"])

    z0 = 0.0
    parts = []
    if opbouw:
        w, h, depth = opbouw
        parts.append(add_mesh(stage, "/Root/Geom/Housing", opbouw_mesh(w, h, depth), frame_m) + (col["frame"],))
        z0 = depth
    parts.append(add_mesh(stage, "/Root/Geom/Frame", frame_mesh(L, z0), frame_m) + (col["frame"],))
    if product == "schakelaar":
        z_top = z0 + L["h_sw"] - L["crown"] - 1.0  # rocker rests tilted; keep the mean face just under build height
        parts.append(add_mesh(stage, "/Root/Geom/Rocker", rocker_mesh(L, z_top, z0), ins_m) + (col["insert"],))
    else:
        z_top = z0 + L["h_so"] - L["crown"] * 0.6
        plate, z_floor = socket_plate_mesh(L, z_top, z0)
        parts.append(add_mesh(stage, "/Root/Geom/CentrePlate", plate, ins_m) + (col["insert"],))
        holes, clips = socket_details(z_floor, z_top + L["crown"] * 0.6)
        parts.append(add_mesh(stage, "/Root/Geom/PinHoles", holes, mat("PinHole", "hole", "matte")) + (("hole", "matte"),))
        parts.append(add_mesh(stage, "/Root/Geom/EarthClips", clips, mat("Metal", "metal", "metallic")) + (("metal", "metallic"),))

    info = dict(
        brand="Busch-Jaeger", line=L["name"], line_id=line_id, colour=colour_id,
        product=PRODUCTS[product], product_id=product, mounting="opbouw" if opbouw else "inbouw",
        frame_mm=[L["frame"], L["frame"]] if not opbouw else [opbouw[0], opbouw[1]],
        depth_from_wall_mm=round((z0 + (L["h_sw"] if product == "schakelaar" else L["h_so"])), 1),
        dimensions_approximate=bool(L.get("approx")),
    )
    rp.SetCustomData(info)
    stage.GetRootLayer().Save()

    usdz = os.path.join(outdir, "usdz", slug + ".usdz")
    os.makedirs(os.path.dirname(usdz), exist_ok=True)
    if os.path.exists(usdz):
        os.remove(usdz)
    ok = UsdUtils.CreateNewARKitUsdzPackage(Sdf.AssetPath(usdc), usdz)
    assert ok, slug
    info["file"] = os.path.basename(usdz)
    return info, parts

def all_jobs():
    for lid, L in LINES.items():
        for cid in L["colours"]:
            for p in PRODUCTS:
                yield (lid, cid, p, None)
    for lid, cid, w, h, d in OPBOUW:
        for p in PRODUCTS:
            yield (lid, cid, p, (w, h, d))

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "out"
    manifest = []
    for job in all_jobs():
        info, _ = build(*job, outdir=out)
        manifest.append(info)
        print("✓", info["file"])
    with open(os.path.join(out, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=2, ensure_ascii=False)
    print(len(manifest), "models")
