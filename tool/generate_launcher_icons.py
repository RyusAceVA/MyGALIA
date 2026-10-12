#!/usr/bin/env python3
"""Génère les icônes Android de MyGalia à partir de branding/logo.png.

* Icône adaptative (Android 8+) : fond blanc (couleur @color/ic_launcher_background)
  et premier plan PNG transparent. Le dessin est centré et dimensionné pour tenir
  entièrement dans la zone sûre de 66 dp (sur un calque de 108 dp) : il n'est
  jamais rogné, quel que soit le masque du lanceur (cercle, squircle, goutte…).
* Icône classique (lanceurs sans icônes adaptatives) : carré arrondi blanc.

Usage (Python 3 + Pillow) :
    python tool/generate_launcher_icons.py [chemin/vers/logo.png]
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"
DEFAULT_SOURCE = ROOT / "branding" / "logo.png"

DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}

# Un pixel dont un canal passe sous ce seuil appartient au dessin ; au-dessus,
# c'est le fond quasi blanc de l'image source.
INK_THRESHOLD = 240
# Tolérance (somme des écarts RVB) du remplissage du fond depuis les bords.
FLOOD_TOLERANCE = 36

ADAPTIVE_CANVAS_DP = 108
SAFE_RADIUS_DP = 33  # zone sûre : cercle de 66 dp centré

LEGACY_CANVAS_DP = 48
LEGACY_INSET_DP = 2
LEGACY_CORNER_DP = 8
LEGACY_RADIUS_DP = 19

SENTINEL = (255, 0, 254)  # couleur temporaire marquant le fond


def load_artwork(path: Path):
    """Dessin détouré (fond → transparent), son centre et son rayon maximal."""
    rgb = Image.open(path).convert("RGB")
    w, h = rgb.size

    # Fond = pixels quasi blancs reliés aux bords (le blanc intérieur du dessin,
    # comme le « M », n'est pas touché).
    filled = rgb.copy()
    for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        if filled.getpixel(seed) != SENTINEL:
            ImageDraw.floodfill(filled, seed, SENTINEL, thresh=FLOOD_TOLERANCE)

    rgba = rgb.convert("RGBA")
    src_px, fill_px, out_px = rgb.load(), filled.load(), rgba.load()
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            if fill_px[x, y] == SENTINEL:
                # Transparent, mais RVB blanc : aucun liseré sombre au redimensionnement.
                out_px[x, y] = (255, 255, 255, 0)
            elif min(src_px[x, y]) < INK_THRESHOLD:
                xs.append(x)
                ys.append(y)
    if not xs:
        sys.exit("Aucun dessin détecté dans l'image source.")

    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    radius = max(math.hypot(x - cx, y - cy) for x, y in zip(xs, ys))
    return rgba, (cx, cy), radius


def place(artwork, center, radius, canvas_px, target_radius_px, background=None):
    """Dessin redimensionné (rayon max = target_radius_px), centré sur le canevas."""
    scale = target_radius_px / radius
    resized = artwork.resize(
        (max(1, round(artwork.width * scale)), max(1, round(artwork.height * scale))),
        Image.LANCZOS,
    )
    offset = (
        round(canvas_px / 2 - center[0] * scale),
        round(canvas_px / 2 - center[1] * scale),
    )
    # Copie brute (alpha compris), découpée aux limites du canevas.
    layer = Image.new("RGBA", (canvas_px, canvas_px), (255, 255, 255, 0))
    layer.paste(resized, offset)
    base = background or Image.new("RGBA", (canvas_px, canvas_px), (255, 255, 255, 0))
    return Image.alpha_composite(base, layer)


def legacy_background(size_px, density):
    """Carré arrondi blanc (icône classique)."""
    bg = Image.new("RGBA", (size_px, size_px), (255, 255, 255, 0))
    inset = round(LEGACY_INSET_DP * density)
    ImageDraw.Draw(bg).rounded_rectangle(
        (inset, inset, size_px - 1 - inset, size_px - 1 - inset),
        radius=round(LEGACY_CORNER_DP * density),
        fill=(255, 255, 255, 255),
    )
    return bg


def main():
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SOURCE
    artwork, center, radius = load_artwork(source)
    print(f"Dessin : centre {center}, rayon max {radius:.1f} px")

    for name, density in DENSITIES.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)

        size = round(ADAPTIVE_CANVAS_DP * density)
        fg = place(artwork, center, radius, size, SAFE_RADIUS_DP * density)
        fg.save(folder / "ic_launcher_foreground.png", optimize=True)

        size = round(LEGACY_CANVAS_DP * density)
        legacy = place(
            artwork, center, radius, size, LEGACY_RADIUS_DP * density,
            background=legacy_background(size, density),
        )
        legacy.save(folder / "ic_launcher.png", optimize=True)
        print(f"mipmap-{name} : premier plan {fg.size}, classique {legacy.size}")

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Généré par tool/generate_launcher_icons.py -->\n"
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )
    (RES / "values" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        '    <color name="ic_launcher_background">#FFFFFF</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )
    print("Icône adaptative : mipmap-anydpi-v26/ic_launcher.xml (fond #FFFFFF)")


if __name__ == "__main__":
    main()
