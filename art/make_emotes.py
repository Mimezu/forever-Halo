"""Draws Halo's emote icons: art/emotes/<token>.tga, 128 px.

Same look as Gamepad Companion's Moments icons: cream line art, a mint accent,
a dark outline, on a warm dark tile. Strokes are a bit heavier so the icons
read at slice size.

    python art/make_emotes.py            # writes the TGAs and art/emotes/sheet.png

Needs Pillow and Chrome (renders the SVG headless).
"""
import os, subprocess, sys, tempfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "emotes")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

CREAM, MINT, INK = "#fffbc8", "#7ccc8c", "#140d07"
W = 7.5           # stroke width (viewBox 128)
OUTLINE = 5       # dark border each side

F = 'class="f" '

# --- drawing helpers (viewBox 0 0 128 128) -----------------------------------
def P(*xy):
    pts = " ".join(f"{xy[i]},{xy[i + 1]}" for i in range(0, len(xy), 2))
    return f'<polyline points="{pts}"/>'

def C(cx, cy, r, fill=False):
    return f'<circle {F if fill else ""}cx="{cx}" cy="{cy}" r="{r}"/>'

def D(d, fill=False):
    return f'<path {F if fill else ""}d="{d}"/>'

def E(cx, cy, rx, ry, rot=0, fill=False):
    return (f'<ellipse {F if fill else ""}cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" '
            f'transform="rotate({rot} {cx} {cy})"/>')

def star4(cx, cy, r):
    k = r * 0.28
    return D(f"M{cx} {cy - r} Q{cx + k} {cy - k} {cx + r} {cy} Q{cx + k} {cy + k} {cx} {cy + r} "
             f"Q{cx - k} {cy + k} {cx - r} {cy} Q{cx - k} {cy - k} {cx} {cy - r} Z", fill=True)

def heart(cx, cy, s, fill=False):
    return D(f"M{cx} {cy + s} C{cx - s * 1.7} {cy - s * 0.1} {cx - s * 0.9} {cy - s * 1.35} {cx} {cy - s * 0.5} "
             f"C{cx + s * 0.9} {cy - s * 1.35} {cx + s * 1.7} {cy - s * 0.1} {cx} {cy + s} Z", fill)

def drop(cx, cy, s, fill=False):
    return D(f"M{cx} {cy - s * 1.7} C{cx + s * 0.4} {cy - s} {cx + s} {cy - s * 0.3} {cx + s} {cy + s * 0.2} "
             f"A{s} {s} 0 0 1 {cx - s} {cy + s * 0.2} C{cx - s} {cy - s * 0.3} {cx - s * 0.4} {cy - s} {cx} {cy - s * 1.7} Z", fill)

def arrowhead(x, y, dx, dy, s=8):
    # chevron at (x, y) pointing along (dx, dy)
    import math
    n = math.hypot(dx, dy); ux, uy = dx / n, dy / n
    px, py = -uy, ux
    return P(round(x - ux * s + px * s, 1), round(y - uy * s + py * s, 1), x, y,
             round(x - ux * s - px * s, 1), round(y - uy * s - py * s, 1))

def man(hx, hy, hip, feet, arms, r=10):
    """Stick figure: head centre, hip point, list of leg polylines, list of arm polylines."""
    out = [C(hx, hy, r), P(hx, hy + r + 2, *hip)]
    out += [P(*leg) for leg in feet]
    out += [P(*arm) for arm in arms]
    return "".join(out)

def face(r=34, cx=64, cy=64):
    return C(cx, cy, r)

MITTEN = ('<g transform="translate({x} {y}) rotate({r}) scale({m} 1)">'
          '<path d="M-12 26 V-14 Q-12 -26 0 -26 Q12 -26 12 -14 V26"/><path d="M-12 4 Q-24 -2 -20 -14"/></g>')
BUBBLE = D("M40 30 H88 Q102 30 102 44 V68 Q102 82 88 82 H62 L46 98 V82 H40 Q26 82 26 68 V44 Q26 30 40 30 Z")

# --- the icons: token -> (main markup, accent markup[, accent on top]) --------
I = {}

# Greet
I["wave"] = (man(54, 32, (54, 76), [(42, 106, 54, 76, 66, 106)], [(54, 52, 40, 72), (54, 52, 74, 46, 80, 24)]),
             D("M89 20 Q96 28 89 37") + D("M97 13 Q108 28 97 43"))
I["hello"] = (P(50, 62, 50, 32) + P(62, 60, 62, 25) + P(74, 60, 74, 28) + P(86, 64, 86, 38)
              + D("M86 62 V78 Q86 100 66 100 Q52 100 46 88 L36 66"),
              D("M27 30 Q20 40 27 50") + D("M101 22 Q108 32 101 42"))
I["bow"] = (C(92, 66, 10) + P(44, 104, 52, 70, 60, 104) + P(52, 70, 82, 52) + P(80, 55, 72, 80),
            D("M70 24 Q92 24 99 44") + arrowhead(99, 44, 2, 6))
I["curtsey"] = (C(64, 27, 10) + P(64, 39, 64, 56) + D("M64 56 L42 88 H86 Z") + P(64, 46, 46, 68) + P(64, 46, 82, 68)
                + P(56, 88, 53, 104) + P(72, 88, 75, 104),
                D("M40 98 Q64 108 88 98"))
I["salute"] = (man(56, 34, (56, 78), [(46, 106, 56, 78, 66, 106)], [(56, 54, 48, 78), (56, 54, 82, 52, 70, 29)]),
               star4(92, 30, 9))
I["beckon"] = (man(40, 36, (40, 80), [(30, 106, 40, 80, 50, 106)], [(40, 56, 60, 62, 66, 48)]),
               D("M104 90 Q100 66 78 70") + arrowhead(78, 70, -6, 1))
I["welcome"] = (man(64, 50, (64, 86), [(55, 106, 64, 86, 73, 106)], [(64, 68, 46, 58), (64, 68, 82, 58)]),
                D("M30 108 V60 A34 34 0 0 1 98 60 V108"))
I["bye"] = (man(66, 34, (60, 76), [(46, 104, 60, 76, 76, 104)], [(64, 54, 46, 44, 42, 24), (64, 54, 80, 66)]),
            P(84, 40, 104, 40) + arrowhead(104, 40, 1, 0))

# Joy
I["cheer"] = (man(64, 38, (64, 78), [(54, 106, 64, 78, 74, 106)], [(64, 56, 46, 42, 40, 20), (64, 56, 82, 42, 88, 20)]),
              star4(28, 50, 9) + star4(100, 50, 9) + star4(64, 14, 7))
I["applaud"] = (MITTEN.format(x=50, y=74, r=9, m=1) + MITTEN.format(x=78, y=74, r=-9, m=-1),
                P(64, 18, 64, 32) + P(42, 26, 50, 36) + P(86, 26, 78, 36))
I["dance"] = (man(58, 28, (63, 70), [(63, 70, 56, 104), (63, 70, 84, 78, 76, 98)], [(60, 48, 38, 38), (60, 48, 80, 40, 88, 20)]),
              E(29, 80, 6, 5, -20, True) + P(34, 79, 34, 56, 44, 60) + E(100, 64, 5, 4, -20, True) + P(104, 63, 104, 46))
I["laugh"] = (face() + D("M44 56 Q51 46 58 56") + D("M70 56 Q77 46 84 56") + D("M44 70 H84 Q84 92 64 92 Q44 92 44 70 Z"),
              P(22, 36, 14, 28) + P(106, 36, 114, 28) + P(18, 52, 8, 50) + P(110, 52, 120, 50))
I["rofl"] = ('<g transform="rotate(-28 64 58)">' + C(64, 58, 30) + D("M48 52 Q54 44 60 52") + D("M68 52 Q74 44 80 52")
             + D("M48 64 H80 Q80 82 64 82 Q48 82 48 64 Z") + "</g>",
             P(20, 102, 108, 102) + D("M24 64 Q20 80 30 92") + arrowhead(30, 92, 1, 1))
I["victory"] = (D("M64 34 L71 50 L88 51 L75 62 L79 79 L64 70 L49 79 L53 62 L40 51 L57 50 Z"),
                D("M48 104 Q20 84 30 44") + D("M80 104 Q108 84 98 44")
                + E(26, 58, 4, 8, -25, True) + E(29, 76, 4, 8, -55, True) + E(39, 92, 4, 8, -75, True)
                + E(102, 58, 4, 8, 25, True) + E(99, 76, 4, 8, 55, True) + E(89, 92, 4, 8, 75, True))
I["flex"] = (man(64, 30, (64, 76), [(54, 104, 64, 76, 74, 104)], [(64, 50, 40, 52, 38, 30), (64, 50, 88, 52, 90, 30)]) + C(38, 27, 5, True) + C(90, 27, 5, True),
             D("M60 47 Q50 34 41 45") + D("M68 47 Q78 34 87 45"))
I["kiss"] = (D("M28 68 Q46 48 64 58 Q82 48 100 68 Q84 92 64 92 Q44 92 28 68 Z") + D("M28 68 Q64 76 100 68"),
             heart(98, 32, 10, True))
I["flirt"] = (C(60, 68, 32) + C(48, 60, 4.5, True) + D("M65 60 Q71 53 77 60") + D("M45 78 Q60 90 74 76"),
              heart(98, 30, 10, True))

# Feel
I["cry"] = (face() + D("M45 54 Q51 60 57 54") + D("M71 54 Q77 60 83 54") + D("M48 88 Q64 76 80 88"),
            D("M51 62 V74") + D("M77 62 V74") + drop(51, 78, 4, True) + drop(77, 78, 4, True))
I["shy"] = (face() + C(51, 60, 4.5, True) + C(77, 60, 4.5, True) + D("M56 80 Q64 86 72 80"),
            E(41, 72, 8, 4.5, 0, True) + E(87, 72, 8, 4.5, 0, True))
I["angry"] = (face(cy=68) + P(44, 50, 58, 58) + P(84, 50, 70, 58) + C(52, 66, 4.5, True) + C(76, 66, 4.5, True) + D("M50 90 Q64 80 78 90"),
              D("M48 26 Q42 19 48 12") + D("M64 24 Q58 17 64 10") + D("M80 26 Q74 19 80 12"))
I["gasp"] = (face() + C(51, 56, 6) + C(77, 56, 6) + E(64, 82, 7, 9),
             P(18, 44, 26, 50) + P(14, 62, 24, 62) + P(110, 44, 102, 50) + P(114, 62, 104, 62))
I["shrug"] = (man(64, 48, (64, 84), [(55, 108, 64, 84, 73, 108)], [(64, 64, 44, 68, 32, 54), (64, 64, 84, 68, 96, 54)]),
              D("M56 18 Q56 10 64 10 Q72 10 72 17 Q72 22 64 25 V28") + C(64, 35, 3.5, True))
I["beg"] = (man(46, 36, (50, 76), [(50, 76, 60, 100, 34, 102)], [(48, 54, 72, 58, 84, 46), (48, 58, 70, 68, 84, 60)]),
            star4(96, 32, 9))
I["cower"] = (C(64, 62, 10) + P(44, 38, 82, 58) + P(84, 38, 46, 58) + P(64, 74, 64, 86)
              + P(64, 86, 46, 90, 44, 106) + P(64, 86, 82, 90, 84, 106),
              D("M26 48 Q18 62 26 76") + D("M102 48 Q110 62 102 76"))
I["chicken"] = (C(46, 42, 12) + D("M54 52 Q36 66 44 84 Q54 100 78 96 Q98 92 98 70 Q98 58 92 50 Q86 62 72 62 Q62 62 56 52")
                + D("M60 76 Q72 86 84 76") + P(62, 98, 60, 110) + P(78, 98, 80, 110) + C(44, 40, 3, True),
                D("M34 39 L22 44 L34 49 Z", True) + D("M38 30 Q41 22 45 30 Q48 21 52 31") + drop(36, 56, 3.5, True))
I["rude"] = (face() + P(44, 52, 56, 58, 44, 62) + P(84, 52, 72, 58, 84, 62) + P(46, 74, 82, 74),
             D("M56 75 V84 Q64 96 72 84 V75"), True)
I["mourn"] = (D("M42 102 V52 Q42 30 64 30 Q86 30 86 52 V102") + P(64, 44, 64, 78) + P(53, 55, 75, 55),
              P(26, 102, 102, 102) + P(30, 100, 30, 88) + C(30, 84, 5, True) + P(98, 100, 98, 90) + C(98, 86, 4, True))

# Talk
I["talk"] = (BUBBLE, C(48, 56, 5.5, True) + C(64, 56, 5.5, True) + C(80, 56, 5.5, True))
I["question"] = (BUBBLE, D("M55 46 Q55 38 64 38 Q73 38 73 46 Q73 52 64 56 V61") + C(64, 71, 4, True))
I["yes"] = (BUBBLE, P(47, 56, 59, 68, 81, 44))
I["no"] = (BUBBLE, P(51, 44, 77, 68) + P(77, 44, 51, 68))
I["thank"] = (BUBBLE, heart(64, 58, 12, True))
I["shout"] = (D("M64 20 L72 34 L88 26 L88 42 L104 46 L92 58 L104 70 L88 74 L88 90 L72 82 L64 98 L56 82 L40 90 L40 74 L24 70 L36 58 L24 46 L40 42 L40 26 L56 34 Z"),
              P(64, 44, 64, 62) + C(64, 72, 4, True))
I["point"] = (man(36, 40, (36, 80), [(28, 106, 36, 80, 44, 106)], [(36, 58, 68, 52), (36, 58, 44, 78)]),
              P(78, 50, 102, 46) + arrowhead(102, 46, 6, -1))
I["train"] = ('<rect x="26" y="50" width="56" height="26" rx="6"/><rect x="80" y="34" width="22" height="42" rx="4"/>'
              + P(38, 50, 38, 36) + P(32, 35, 44, 35),
              C(42, 91, 9) + C(68, 91, 9) + C(94, 92, 6) + C(36, 22, 5.5, True) + C(48, 13, 4.5, True))

# Battle
I["roar"] = (face() + P(42, 46, 58, 54) + P(86, 46, 70, 54) + C(52, 60, 4, True) + C(76, 60, 4, True)
             + D("M44 70 H84 Q84 92 64 92 Q44 92 44 70 Z") + P(52, 70, 55, 78, 58, 70) + P(70, 70, 73, 78, 76, 70),
             D("M106 50 Q114 64 106 78") + D("M22 50 Q14 64 22 78"))
I["threaten"] = (man(50, 42, (50, 82), [(40, 108, 50, 82, 60, 108)], [(50, 60, 38, 78), (50, 60, 72, 56, 78, 34)]) + C(80, 28, 8, True),
                 D("M94 16 Q102 28 94 40") + D("M64 16 Q58 26 63 36"))
I["charge"] = (C(70, 32, 10) + P(66, 44, 56, 72) + P(56, 72, 74, 84, 72, 104) + P(56, 72, 44, 90, 30, 92)
               + P(63, 52, 82, 58) + P(78, 60, 104, 42) + P(80, 50, 87, 62),
               P(18, 48, 34, 48) + P(14, 62, 32, 62) + P(18, 76, 34, 76))
I["attacktarget"] = (C(64, 64, 30) + P(64, 22, 64, 40) + P(64, 88, 64, 106) + P(22, 64, 40, 64) + P(88, 64, 106, 64),
                     C(64, 64, 8, True))
I["incoming"] = (D("M64 26 L102 94 H26 Z"), P(64, 50, 64, 72) + C(64, 83, 4.5, True))
I["oom"] = (drop(64, 70, 24), P(36, 102, 94, 30), True)
I["healme"] = (heart(64, 66, 32), P(64, 54, 64, 80) + P(51, 67, 77, 67))
I["openfire"] = (D("M64 106 Q36 102 38 76 Q40 58 54 46 Q53 62 62 66 Q60 44 72 22 Q78 46 88 58 Q98 72 92 88 Q85 104 64 106 Z"),
                 D("M64 96 Q53 94 55 83 Q57 74 64 68 Q66 78 72 81 Q76 92 64 96 Z", True))
I["followme"] = (E(44, 80, 8, 12, -15) + E(41, 99, 6, 5, -15) + E(76, 46, 8, 12, -15) + E(73, 65, 6, 5, -15),
                 P(90, 32, 104, 20) + arrowhead(104, 20, 7, -6))
I["wait"] = (P(40, 26, 88, 26) + P(40, 102, 88, 102) + D("M46 26 Q46 52 64 64 Q46 76 46 102") + D("M82 26 Q82 52 64 64 Q82 76 82 102"),
             D("M53 38 H75 Q72 52 64 56 Q56 52 53 38 Z", True) + D("M52 96 Q64 80 76 96 Z", True))
I["flee"] = (C(58, 32, 10) + P(62, 44, 72, 72) + P(72, 72, 54, 84, 56, 104) + P(72, 72, 84, 90, 98, 92)
             + P(65, 52, 46, 60) + P(65, 52, 82, 44),
             drop(84, 24, 4, True) + drop(95, 36, 4, True))
I["surrender"] = (P(42, 108, 42, 24) + D("M42 28 Q58 20 70 28 Q82 36 98 28 V62 Q82 70 70 62 Q58 54 42 62"),
                  C(42, 20, 5, True))

# Rest
I["sit"] = (C(46, 38, 10) + P(46, 50, 48, 84) + P(48, 84, 72, 62, 88, 86) + P(47, 58, 68, 64),
            P(24, 94, 104, 94))
I["sleep"] = (D("M62 32 A32 32 0 1 0 96 84 A26 26 0 0 1 62 32 Z"),
              P(76, 18, 92, 18, 76, 34, 92, 34) + P(98, 42, 108, 42, 98, 52, 108, 52))
I["kneel"] = (man(56, 30, (56, 72), [(56, 72, 80, 72, 80, 96), (56, 72, 46, 96, 28, 96)], [(56, 50, 76, 68)]),
              P(22, 104, 104, 104))
I["stand"] = (man(52, 30, (52, 74), [(44, 106, 52, 74, 60, 106)], [(52, 50, 42, 74), (52, 50, 62, 74)]),
              P(90, 92, 90, 36) + arrowhead(90, 36, 0, -1))
I["laydown"] = (C(30, 70, 10) + P(42, 72, 76, 72) + P(76, 72, 90, 58, 104, 72) + P(52, 72, 62, 60),
                P(18, 84, 110, 84))
I["eat"] = (D("M58 78 Q40 64 46 44 Q54 22 76 22 Q100 24 104 46 Q106 66 84 74 Q72 78 64 84 Z") + P(60, 82, 42, 100)
            + C(35, 95, 6.5) + C(47, 107, 6.5),
            D("M70 34 Q86 32 92 46"))
I["drink"] = ('<rect x="34" y="44" width="46" height="58" rx="7"/>' + D("M80 56 H88 Q98 56 98 66 V78 Q98 88 88 88 H80")
              + P(50, 58, 50, 88) + P(64, 58, 64, 88),
              D("M32 46 Q30 32 44 32 Q50 22 60 27 Q72 22 78 32 Q88 34 84 46"))
I["pray"] = (man(52, 44, (54, 80), [(54, 80, 64, 102, 38, 102)], [(53, 62, 72, 60, 70, 42)]),
             P(100, 16, 88, 28) + P(108, 34, 94, 40) + P(84, 8, 80, 22))


def layer(markup, color, width, fill_color, fill_stroke):
    m = markup.replace('class="f"', f'fill="{fill_color}" stroke-width="{fill_stroke}"')
    return (f'<g fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" '
            f'stroke-linejoin="round">{m}</g>')

def svg(main, accent, accent_on_top=False):
    def ink(m):
        return layer(m, INK, W + 2 * OUTLINE, INK, 2 * OUTLINE)
    def paint(m, c):
        return layer(m, c, W, c, 0)
    parts = [(accent, MINT), (main, CREAM)]
    if accent_on_top: parts.reverse()
    body = "".join(f'<g filter="url(#soft)">{ink(m)}</g>{paint(m, c)}' for m, c in parts if m)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="512" height="512">'
            '<defs><radialGradient id="bg" cx="50%" cy="42%" r="70%">'
            '<stop offset="0" stop-color="#4a3826"/><stop offset="0.65" stop-color="#2a1f15"/>'
            '<stop offset="1" stop-color="#150f0a"/></radialGradient>'
            '<filter id="soft" x="-20%" y="-20%" width="140%" height="140%">'
            '<feGaussianBlur stdDeviation="0.8"/></filter></defs>'
            '<rect width="128" height="128" fill="url(#bg)"/>' + body + '</svg>')


def main():
    os.makedirs(OUT, exist_ok=True)
    tokens = sys.argv[1:] or list(I)
    cols = 8
    rows = (len(tokens) + cols - 1) // cols
    html = ('<html><body style="margin:0;background:transparent">'
            f'<div style="display:grid;grid-template-columns:repeat({cols},512px);gap:0">'
            + "".join(svg(*I[t]) for t in tokens) + "</div></body></html>")
    tmp = tempfile.mkdtemp()
    page, shot = os.path.join(tmp, "sheet.html"), os.path.join(tmp, "sheet.png")
    with open(page, "w", encoding="utf-8") as f:
        f.write(html)
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--window-size={cols * 512},{rows * 512}", f"--screenshot={shot}", "file:///" + page.replace("\\", "/")],
                   check=True, capture_output=True)
    sheet = Image.open(shot).convert("RGBA")
    preview = Image.new("RGBA", (cols * 140, rows * 140 + rows * 52), (24, 18, 12, 255))
    for i, t in enumerate(tokens):
        x, y = (i % cols) * 512, (i // cols) * 512
        icon = sheet.crop((x, y, x + 512, y + 512)).resize((128, 128), Image.LANCZOS)
        icon.save(os.path.join(OUT, t + ".tga"))
        px, py = (i % cols) * 140, (i // cols) * 192
        preview.alpha_composite(icon, (px + 6, py + 6))
        preview.alpha_composite(icon.resize((40, 40), Image.LANCZOS), (px + 50, py + 142))
    preview.save(os.path.join(OUT, "sheet.png"))
    print(len(tokens), "icons ->", OUT)


if __name__ == "__main__":
    main()
