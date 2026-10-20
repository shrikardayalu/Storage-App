#!/usr/bin/env python3
"""Generates the app's hand-inked illustrations as SVG image sets.

Every icon is described with a few primitives (rounded rects, ellipses,
polylines). The generator adds a small, seeded wobble to each outline, offsets
the mint fill from the ink like a slightly misregistered print, and writes a
light and a dark variant into the asset catalog. Output is deterministic, so
re-running only changes icons whose definitions changed.

Usage (from the repository root, any OS with Python 3.9+):
    python ios/Tools/illustrations/generate.py            # write the asset catalog
    python ios/Tools/illustrations/generate.py --preview  # also write preview.html

To add an icon: write a function decorated with @icon("ill-name") below and run
the script. Reference it in Swift as `Illustration.name` (see Illustration.swift).
"""

from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "StorageApp" / "Resources" / "Assets.xcassets" / "Illustrations"

# Palette. Light: near-black ink on light surfaces. Dark: cream ink on dark surfaces.
PALETTES = {
    "light": {"ink": "#1A1A17", "mint": "#5ED49B", "paper": "#FBF8F1", "shade": "#3DAE77"},
    "dark": {"ink": "#EFEADF", "mint": "#5ED49B", "paper": "#23231F", "shade": "#2F9563"},
}

SIZE = 96
STROKE = 3.4

# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------


class Pen:
    """Collects SVG elements for one icon, with a seeded wobble."""

    def __init__(self, seed: int):
        self.rng = random.Random(seed)
        self.layers: list[tuple[str, str]] = []  # (role, svg fragment with {color} slots)

    # -- jitter --------------------------------------------------------------
    def j(self, amount: float = 0.7) -> float:
        return self.rng.uniform(-amount, amount)

    def jitter_points(self, pts, amount=0.7):
        return [(x + self.j(amount), y + self.j(amount)) for x, y in pts]

    # -- path builders -------------------------------------------------------
    @staticmethod
    def smooth_closed(pts) -> str:
        """Catmull-Rom spline through pts as a closed cubic Bezier path."""
        n = len(pts)
        d = [f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"]
        for i in range(n):
            p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
            c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
            c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
            d.append(f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}")
        return " ".join(d) + "Z"

    def wobbly_segments(self, pts, closed=False, bow=0.9) -> str:
        """Straight-ish segments, each bowed slightly, keeping sharp corners."""
        pts = self.jitter_points(pts, 0.5)
        if closed:
            pts = pts + [pts[0]]
        d = [f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"]
        for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
            mx, my = (x1 + x2) / 2, (y1 + y2) / 2
            length = math.hypot(x2 - x1, y2 - y1) or 1
            nx, ny = -(y2 - y1) / length, (x2 - x1) / length
            k = self.j(bow) * min(1.0, length / 20)
            d.append(f"Q{mx + nx * k:.1f},{my + ny * k:.1f} {x2:.1f},{y2:.1f}")
        if closed:
            d.append("Z")
        return " ".join(d)

    @staticmethod
    def rounded_rect_points(x, y, w, h, r, step=9.0):
        pts = []
        corners = [
            (x + w - r, y + r, -90),  # top-right
            (x + w - r, y + h - r, 0),  # bottom-right
            (x + r, y + h - r, 90),  # bottom-left
            (x + r, y + r, 180),  # top-left
        ]
        for i, (cx, cy, start) in enumerate(corners):
            for k in range(3):
                a = math.radians(start + k * 45)
                pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
            # straight edge to next corner
            ncx, ncy, nstart = corners[(i + 1) % 4]
            a_end = math.radians(start + 90)
            sx, sy = cx + r * math.cos(a_end), cy + r * math.sin(a_end)
            ex, ey = ncx + r * math.cos(math.radians(nstart)), ncy + r * math.sin(math.radians(nstart))
            length = math.hypot(ex - sx, ey - sy)
            segments = max(1, int(length // step))
            for s in range(segments):
                t = s / segments
                pts.append((sx + (ex - sx) * t, sy + (ey - sy) * t))
        return pts

    @staticmethod
    def ellipse_points(cx, cy, rx, ry, count=None):
        count = count or max(8, int((rx + ry) / 2.2))
        return [
            (cx + rx * math.cos(2 * math.pi * i / count), cy + ry * math.sin(2 * math.pi * i / count))
            for i in range(count)
        ]

    def blob(self, pts, wobble=0.7) -> str:
        return self.smooth_closed(self.jitter_points(pts, wobble))

    # -- layers ---------------------------------------------------------------
    def fill(self, d: str, role: str = "mint"):
        self.layers.append((role, f'<path d="{d}" fill="{{{role}}}"/>'))

    def stroke(self, d: str, width: float = STROKE, role: str = "ink"):
        self.layers.append(
            (role, f'<path d="{d}" fill="none" stroke="{{{role}}}" stroke-width="{width}" '
                   f'stroke-linecap="round" stroke-linejoin="round"/>')
        )

    def shape(self, pts, *, fill="mint", offset=(2.6, -2.2), outline=True, smooth=True, width=STROKE, shadow=None):
        """A filled region with an ink outline; the fill is shifted like a misprint.

        Mint shapes also get a solid ink shadow nudged down-left, like the
        heavy edge in hand-printed spot illustrations. Pass shadow=False to skip.
        """
        if shadow is None:
            shadow = fill == "mint" and outline
        if shadow:
            shifted = [(x - 2.4, y + 2.6) for x, y in pts]
            self.fill(self.blob(shifted, 0.5) if smooth else self.wobbly_segments(shifted, closed=True), "ink")
        if fill:
            shifted = [(x + offset[0], y + offset[1]) for x, y in pts]
            self.fill(self.blob(shifted, 0.6) if smooth else self.wobbly_segments(shifted, closed=True), fill)
        if outline:
            self.stroke(self.blob(pts, 0.5) if smooth else self.wobbly_segments(pts, closed=True), width)

    def rrect(self, x, y, w, h, r, **kw):
        self.shape(self.rounded_rect_points(x, y, w, h, r), **kw)

    def ellipse(self, cx, cy, rx, ry=None, **kw):
        self.shape(self.ellipse_points(cx, cy, rx, ry or rx), **kw)

    def poly(self, pts, **kw):
        kw.setdefault("smooth", False)
        self.shape(pts, **kw)

    def line(self, *pts, width=STROKE, role="ink"):
        self.stroke(self.wobbly_segments(list(pts)), width, role)

    def solid(self, pts, role="ink", smooth=False):
        """An area filled with ink (or another role) and no separate outline."""
        self.fill(self.blob(pts, 0.4) if smooth else self.wobbly_segments(pts, closed=True), role)

    def dots(self, *pts, r=1.15, role="ink"):
        for x, y in pts:
            self.layers.append((role, f'<circle cx="{x + self.j(0.3):.1f}" cy="{y + self.j(0.3):.1f}" r="{r}" fill="{{{role}}}"/>'))

    def ticks(self, cx, cy, radius, angles, length=6.0, width=2.6):
        """Short radiating marks, like the 'sparkle' lines in the reference art."""
        for a in angles:
            rad = math.radians(a + self.j(4))
            x1, y1 = cx + radius * math.cos(rad), cy + radius * math.sin(rad)
            x2, y2 = cx + (radius + length) * math.cos(rad), cy + (radius + length) * math.sin(rad)
            self.line((x1, y1), (x2, y2), width=width)

    def sparkle(self, cx, cy, s=5.0, width=2.4):
        self.line((cx - s, cy), (cx + s, cy), width=width)
        self.line((cx, cy - s), (cx, cy + s), width=width)

    def svg(self, palette: dict[str, str]) -> str:
        body = "\n  ".join(fragment.format(**palette) for _, fragment in self.layers)
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" '
            f'viewBox="0 0 {SIZE} {SIZE}">\n  {body}\n</svg>\n'
        )


ICONS: dict[str, callable] = {}


def icon(name: str):
    def register(fn):
        ICONS[name] = fn
        return fn

    return register


def check(p: Pen, x, y, s=1.0, width=4.2):
    p.line((x - 8 * s, y), (x - 2.5 * s, y + 6 * s), (x + 9 * s, y - 8 * s), width=width)


# ---------------------------------------------------------------------------
# Icons (96 x 96 canvas)
# ---------------------------------------------------------------------------


@icon("ill-photo")
def photo(p: Pen):
    p.rrect(12, 22, 70, 54, 7)
    # mountains, filled with ink
    p.solid([(19, 69), (36, 46), (46, 58), (56, 47), (75, 69)])
    p.ellipse(62, 36, 6.5, fill="paper", offset=(0, 0))
    p.ticks(62, 36, 9.5, [-150, -95, -40], length=4.5, width=2.2)
    p.dots((22, 32), (27, 29), (24, 37))


@icon("ill-video")
def video(p: Pen):
    p.ellipse(25, 25, 8.5, fill="paper", offset=(0, 0))
    p.ellipse(47, 25, 8.5, fill="paper", offset=(0, 0))
    p.dots((25, 25), (47, 25), r=1.8)
    p.rrect(10, 35, 54, 38, 7)
    p.poly([(64, 48), (85, 38), (85, 71), (64, 61)], fill="ink", offset=(0, 0))
    p.line((18, 45), (30, 45), width=3)
    p.dots((52, 63), (56, 59), (48, 66))


@icon("ill-screenshot")
def screenshot(p: Pen):
    p.rrect(31, 14, 34, 68, 8)
    p.line((43, 21), (53, 21), width=3)
    p.solid([(38, 32), (58, 32), (58, 50), (38, 50)])
    p.line((38, 58), (58, 58), width=2.6)
    p.line((38, 65), (51, 65), width=2.6)
    # crop brackets
    for (x, y, dx, dy) in [(22, 10, 1, 1), (74, 10, -1, 1), (22, 86, 1, -1), (74, 86, -1, -1)]:
        p.line((x, y + 9 * dy), (x, y), (x + 9 * dx, y), width=3.6)


@icon("ill-compress")
def compress(p: Pen):
    p.rrect(32, 20, 32, 56, 6)
    p.line((40, 34), (56, 34), width=2.6)
    p.line((40, 42), (52, 42), width=2.6)
    p.solid([(40, 52), (56, 52), (56, 66), (40, 66)])
    for side in (-1, 1):
        x_out, x_in = 48 + side * 40, 48 + side * 22
        p.line((x_out, 48), (x_in, 48), width=3.6)
        p.line((x_in + side * 6, 41), (x_in, 48), (x_in + side * 6, 55), width=3.6)
    p.ticks(48, 48, 34, [-120, -60, 60, 120], length=4, width=2.2)


@icon("ill-trash")
def trash(p: Pen):
    p.poly([(27, 38), (69, 38), (64, 84), (32, 84)], smooth=False)
    for x in (39, 48, 57):
        p.line((x, 47), (x - (x - 48) * 0.1, 76), width=2.8)
    # tilted lid with handle
    p.poly([(22, 31), (68, 22), (70, 29), (24, 38)], fill="ink", offset=(0, 0))
    p.line((40, 26), (39, 20), (51, 18), (53, 23), width=3)
    p.ticks(70, 22, 8, [-60, -20, 20], length=5, width=2.3)
    p.dots((34, 56), (60, 70), (36, 74))


@icon("ill-shield-check")
def shield_check(p: Pen):
    pts = [(48, 10), (62, 16), (77, 18), (76, 44), (70, 62), (58, 76), (48, 83), (38, 76), (26, 62), (20, 44), (19, 18), (34, 16)]
    p.shape(pts)
    check(p, 47, 47, 1.25, 5)
    p.ticks(48, 48, 40, [190, 210, 330, 350], length=5)


@icon("ill-empty-box")
def empty_box(p: Pen):
    p.poly([(18, 44), (78, 44), (74, 82), (22, 82)])
    p.poly([(18, 44), (6, 33), (28, 27), (38, 44)], fill="paper", offset=(0, 0))
    p.poly([(78, 44), (90, 33), (68, 27), (58, 44)], fill="paper", offset=(0, 0))
    p.line((34, 62), (62, 62), width=2.6)
    p.dots((30, 72), (66, 72), (48, 74))
    p.ticks(48, 30, 8, [-130, -90, -50], length=6)


@icon("ill-beaker")
def beaker(p: Pen):
    p.solid([(33, 60), (63, 60), (70, 76), (67, 80), (29, 80), (26, 76)], role="mint")
    p.stroke(p.wobbly_segments([(41, 18), (41, 40), (24, 76), (28, 82), (68, 82), (72, 76), (55, 40), (55, 18)]))
    p.line((36, 18), (60, 18), width=3.6)
    p.ellipse(44, 70, 2.6, fill="paper", offset=(0, 0), width=2.2)
    p.ellipse(54, 64, 1.8, fill="paper", offset=(0, 0), width=2)
    p.ellipse(52, 48, 2, fill=None, width=2)
    p.ticks(48, 18, 14, [-150, -90, -30], length=5, width=2.2)


@icon("ill-umbrella")
def umbrella(p: Pen):
    canopy = [(14, 46), (20, 30), (34, 19), (48, 15), (62, 19), (76, 30), (82, 46), (73, 42), (65, 46), (56, 42), (48, 46), (40, 42), (31, 46), (23, 42)]
    p.shape(canopy, smooth=False)
    p.line((48, 15), (48, 10), width=3.4)
    p.line((48, 46), (48, 74), width=3.4)
    p.stroke("M48,74 Q48,82 41,82 Q35,82 35,76", width=3.4)
    # little photo sheltered under it
    p.rrect(56, 58, 22, 18, 3, fill="paper", offset=(0, 0), width=3)
    p.solid([(59, 73), (65, 65), (69, 70), (72, 67), (76, 73)])
    for x, y in [(16, 58), (24, 66), (12, 72)]:
        p.line((x, y), (x - 2, y + 6), width=2.4)


@icon("ill-stack-small")
def stack_small(p: Pen):
    p.rrect(22, 22, 48, 38, 5, fill="paper", offset=(0, 0))
    p.rrect(16, 32, 52, 40, 5, fill="paper", offset=(0, 0))
    p.rrect(28, 40, 56, 42, 6)
    p.solid([(34, 77), (46, 61), (54, 70), (61, 64), (78, 77)])
    p.dots((36, 50), (41, 47))


@icon("ill-stack-large")
def stack_large(p: Pen):
    for i, (x, y) in enumerate([(30, 10), (24, 20), (18, 30), (12, 40)]):
        p.rrect(x, y, 52, 30, 5, fill="paper", offset=(0, 0), width=3)
    p.rrect(8, 50, 62, 36, 6)
    p.solid([(14, 81), (28, 64), (37, 73), (45, 66), (64, 81)])
    p.sparkle(82, 22, 5)
    p.sparkle(86, 46, 3.5, width=2)


@icon("ill-reset")
def reset(p: Pen):
    p.ellipse(48, 48, 18, fill="mint", offset=(3, -3), outline=False)
    arc1 = [(48 + 26 * math.cos(math.radians(a)), 48 + 26 * math.sin(math.radians(a))) for a in range(200, 340, 20)]
    arc2 = [(48 + 26 * math.cos(math.radians(a)), 48 + 26 * math.sin(math.radians(a))) for a in range(20, 160, 20)]
    for arc in (arc1, arc2):
        p.line(*arc, width=3.8)
    # arrowheads
    p.line((66, 22), (70, 30.5), (61, 32), width=3.8)
    p.line((30, 74), (26, 65.5), (35, 64), width=3.8)
    p.ellipse(48, 48, 5, fill="ink", offset=(0, 0), outline=False)


@icon("ill-lock")
def lock(p: Pen):
    p.stroke("M33,44 L33,32 Q33,17 48,17 Q63,17 63,32 L63,44", width=4.2)
    p.rrect(22, 42, 52, 40, 8)
    p.ellipse(48, 58, 4.5, fill="ink", offset=(0, 0), outline=False)
    p.line((48, 61), (48, 70), width=4)
    p.dots((30, 50), (34, 47), (66, 74))


@icon("ill-piggy")
def piggy(p: Pen):
    body = Pen.ellipse_points(48, 54, 31, 22, 16)
    p.shape(body)
    p.poly([(29, 40), (30, 26), (42, 34)], fill="mint", shadow=False)  # ear
    p.rrect(73, 46, 11, 14, 4, fill="paper", offset=(0, 0), width=3)  # snout
    p.dots((77, 53), (80.5, 53), r=1.3)
    for x in (31, 61):
        p.rrect(x, 70, 9, 12, 3, fill="mint", offset=(0, 0), width=3, shadow=False)
    p.stroke("M17,52 Q9,50 11,44 Q13,39 17,43", width=3)  # tail
    p.line((42, 33), (56, 33), width=3.2)  # coin slot
    p.dots((63, 46), r=1.8)  # eye
    check(p, 46, 56, 0.95, 4.2)


@icon("ill-phone-sparkle")
def phone_sparkle(p: Pen):
    p.rrect(28, 12, 40, 74, 9)
    p.line((42, 19), (54, 19), width=3)
    # storage bars, shortest to tallest
    for i, (h, role) in enumerate([(12, "ink"), (20, "paper"), (30, "ink")]):
        x = 35 + i * 10
        if role == "paper":
            p.rrect(x, 74 - h, 7, h, 1.5, fill="paper", offset=(0, 0), width=2.6)
        else:
            p.solid([(x, 74), (x + 7, 74), (x + 7, 74 - h), (x, 74 - h)])
    p.sparkle(80, 22, 6)
    p.sparkle(16, 44, 4.5, width=2.2)
    p.ticks(74, 70, 6, [-30, 10, 50], length=5, width=2.2)


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------


def contents_json(name: str) -> dict:
    return {
        "images": [
            {"filename": f"{name}.svg", "idiom": "universal"},
            {
                "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "filename": f"{name}-dark.svg",
                "idiom": "universal",
            },
        ],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True},
    }


def render_all() -> dict[str, dict[str, str]]:
    out = {}
    for index, (name, draw) in enumerate(sorted(ICONS.items())):
        variants = {}
        for mode, palette in PALETTES.items():
            pen = Pen(seed=1000 + sum(map(ord, name)))  # same wobble in both modes
            draw(pen)
            variants[mode] = pen.svg(palette)
        out[name] = variants
    return out


def write_catalog(rendered):
    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}}, indent=2) + "\n"
    )
    for name, variants in rendered.items():
        folder = CATALOG / f"{name}.imageset"
        folder.mkdir(exist_ok=True)
        (folder / f"{name}.svg").write_text(variants["light"])
        (folder / f"{name}-dark.svg").write_text(variants["dark"])
        (folder / "Contents.json").write_text(json.dumps(contents_json(name), indent=2) + "\n")


def write_preview(rendered, path: Path):
    cells = []
    for name, variants in rendered.items():
        cells.append(
            f'<figure><div class="pair"><div class="light">{variants["light"]}</div>'
            f'<div class="dark">{variants["dark"]}</div></div><figcaption>{name}</figcaption></figure>'
        )
    path.write_text(
        "<!doctype html><meta charset=utf-8><title>Illustrations</title><style>"
        "body{font:13px -apple-system,system-ui,sans-serif;background:#ece7db;margin:24px}"
        "main{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:16px}"
        "figure{margin:0}.pair{display:flex}.pair>div{padding:14px;flex:1;display:grid;place-items:center}"
        ".light{background:#F4F1EA}.dark{background:#141413}svg{width:110px;height:110px}"
        "figcaption{padding-top:6px;color:#555}</style><main>" + "".join(cells) + "</main>"
    )


if __name__ == "__main__":
    rendered = render_all()
    write_catalog(rendered)
    if "--preview" in sys.argv:
        target = Path(sys.argv[sys.argv.index("--preview") + 1]) if len(sys.argv) > sys.argv.index("--preview") + 1 else Path(__file__).with_name("preview.html")
        write_preview(rendered, target)
        print(f"Preview: {target}")
    print(f"Wrote {len(rendered)} illustrations to {CATALOG}")
