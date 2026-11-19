import glob, os, sys, json
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
from pxr import Usd, UsdGeom, UsdShade

def lin2srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)

def load(path):
    st = Usd.Stage.Open(path)
    tris, cols = [], []
    for p in st.Traverse():
        if not p.IsA(UsdGeom.Mesh):
            continue
        m = UsdGeom.Mesh(p)
        V = np.array(m.GetPointsAttr().Get()) * 1000
        cnt = m.GetFaceVertexCountsAttr().Get(); idx = m.GetFaceVertexIndicesAttr().Get()
        mat, _ = UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()
        sh = UsdShade.Shader(st.GetPrimAtPath(str(mat.GetPath()) + "/PreviewSurface"))
        base = lin2srgb(np.array(sh.GetInput("diffuseColor").Get()))
        rough = sh.GetInput("roughness").Get()
        k = 0
        for c in cnt:
            f = idx[k:k + c]; k += c
            for j in range(1, c - 1):
                tris.append(V[[f[0], f[j], f[j + 1]]]); cols.append((base, rough))
    return tris, cols

def render(ax, path, title):
    tris, cols = load(path)
    light = np.array([-0.4, 0.6, 0.75]); light /= np.linalg.norm(light)
    view = np.array([-0.45, 0.25, 0.86]); view /= np.linalg.norm(view)
    polys, fc = [], []
    for t, (base, rough) in zip(tris, cols):
        n = np.cross(t[1] - t[0], t[2] - t[0]); ln = np.linalg.norm(n)
        if ln < 1e-9: continue
        n /= ln
        if np.dot(n, view) < -0.05: continue  # back-face cull
        d = max(np.dot(n, light), 0)
        h = light + view; h /= np.linalg.norm(h)
        spec = (max(np.dot(n, h), 0) ** (8 + 120 * (1 - rough))) * (1 - rough) * 0.6
        c = np.clip(base * (0.32 + 0.68 * d) + spec, 0, 1)
        polys.append(t[:, [0, 2, 1]] * np.array([1, -1, 1]))  # (x, -z, y): z out of wall -> towards camera
        fc.append(c)
    pc = Poly3DCollection(polys, facecolors=fc, edgecolors="none")
    ax.add_collection3d(pc)
    lim = 58
    ax.set_xlim(-lim, lim); ax.set_ylim(-lim, lim); ax.set_zlim(-lim, lim)
    ax.view_init(elev=14, azim=-62)
    ax.set_box_aspect((1, 1, 1)); ax.set_axis_off()
    ax.set_title(title, fontsize=7.5, pad=-4)

if __name__ == "__main__":
    out = sys.argv[1]
    files = sorted(glob.glob(os.path.join(out, "usdz", "*.usdz")))
    man = {m["file"]: m for m in json.load(open(os.path.join(out, "manifest.json")))}
    order = list(dict.fromkeys(m["file"] for m in json.load(open(os.path.join(out, "manifest.json")))))
    cols_n = 6
    rows = int(np.ceil(len(order) / cols_n))
    fig = plt.figure(figsize=(cols_n * 2.3, rows * 2.4), dpi=110)
    fig.patch.set_facecolor("#9a9c9f")
    for i, f in enumerate(order):
        m = man[f]
        ax = fig.add_subplot(rows, cols_n, i + 1, projection="3d")
        ax.set_facecolor("#9a9c9f")
        t = f"{m['line']} · {m['colour']}\n{m['product_id']}" + (" (opbouw)" if m["mounting"] == "opbouw" else "")
        render(ax, os.path.join(out, "usdz", f), t)
    plt.subplots_adjust(wspace=0, hspace=0.12, left=0, right=1, top=0.98, bottom=0)
    fig.savefig(os.path.join(out, "preview_contact_sheet.png"), facecolor=fig.get_facecolor())
    print("ok")
