"""Girl SPROUT: same rig as SPROUT (so every shop item fits), with
bangs + bob + pigtails, a pink bow, lashes, and a pink top.

Reads  assets/images/heroes/sprout/<tier>/<layer>.png
Writes assets/images/heroes/sprout_girl/<tier>/<layer>.png
"""
import base64, colorsys, io, os, sys
from PIL import Image
from playwright.sync_api import sync_playwright

SRC = sys.argv[1]   # .../assets/images/heroes/sprout
DST = sys.argv[2]   # .../assets/images/heroes/sprout_girl
TIERS = ['underweight', 'normal', 'overweight', 'obese']
HS = {'underweight': 0.934, 'normal': 1.0, 'overweight': 1.088, 'obese': 1.176}
K = '#1b1b1b'
HAIR = '#5a3a22'
HAIR_HI = '#7a5234'
PINK = '#ff5fa2'
PINK_D = '#c2337a'
# outer edge of the eye whites (left, right) per head-width scale
EYE = {0.934: (112, 175), 1.0: (110, 178), 1.088: (107, 181), 1.176: (104, 184)}


def hair_back(s):
    """pigtails: drawn BEHIND the head picture."""
    def tail(side):
        # side = -1 left, +1 right; anchor just outside the head at y~140
        ax = 143 + side * 92 * s
        d = (f'M{ax} 124 C{ax + side * 34} 128 {ax + side * 46} 176 {ax + side * 30} 214 '
             f'C{ax + side * 22} 232 {ax + side * 4} 236 {ax - side * 2} 222 '
             f'C{ax + side * 14} 196 {ax + side * 10} 160 {ax - side * 6} 146Z')
        return (f'<path d="{d}" fill="{HAIR}" stroke="{K}" stroke-width="6" stroke-linejoin="round"/>'
                f'<path d="M{ax + side * 14} 150 C{ax + side * 26} 170 {ax + side * 26} 192 {ax + side * 18} 210" '
                f'fill="none" stroke="{HAIR_HI}" stroke-width="4" stroke-linecap="round"/>'
                # hair tie
                f'<rect x="{ax - 9}" y="128" width="18" height="14" rx="6" fill="{PINK}" stroke="{K}" stroke-width="4" '
                f'transform="rotate({side * 30} {ax} 135)"/>')
    return tail(-1) + tail(1)


def hair_front(s):
    """bangs + bob over the head picture (covers the boy's headband)."""
    L = 143 - 93 * s   # outer left of hair
    R = 143 + 93 * s
    # dome + side locks down past the ears
    dome = (f'M{L} 214 L{L} 132 Q{L} 74 143 74 Q{R} 74 {R} 132 L{R} 214 '
            f'Q{R - 6 * s} 222 {R - 16 * s} 216 L{R - 16 * s} 150 '
            # bangs (scalloped edge above the eyes)
            f'Q{143 + 64 * s} 168 {143 + 46 * s} 152 Q{143 + 30 * s} 170 {143 + 8 * s} 154 '
            f'Q{143 - 12 * s} 172 {143 - 34 * s} 154 Q{143 - 52 * s} 170 {143 - 66 * s} 150 '
            f'L{L + 16 * s} 150 L{L + 16 * s} 216 Q{L + 6 * s} 222 {L} 214Z')
    shine = (f'<path d="M{143 - 50 * s} 92 Q{143 - 20 * s} 82 {143 + 10 * s} 86" fill="none" stroke="#ffffff" '
             f'stroke-opacity="0.35" stroke-width="7" stroke-linecap="round"/>')
    strands = (f'<path d="M{143 - 34 * s} 104 Q{143 - 40 * s} 130 {143 - 34 * s} 150 M{143 + 30 * s} 104 Q{143 + 36 * s} 128 {143 + 30 * s} 148" '
               f'fill="none" stroke="#3f2816" stroke-width="3" stroke-linecap="round"/>')
    # bow on the top right
    bx, by = 143 + 58 * s, 86
    bow = (f'<path d="M{bx} {by} L{bx - 26} {by - 16} Q{bx - 32} {by} {bx - 26} {by + 16}Z" fill="{PINK}" stroke="{K}" stroke-width="5" stroke-linejoin="round"/>'
           f'<path d="M{bx} {by} L{bx + 26} {by - 16} Q{bx + 32} {by} {bx + 26} {by + 16}Z" fill="{PINK}" stroke="{K}" stroke-width="5" stroke-linejoin="round"/>'
           f'<path d="M{bx - 22} {by - 8} L{bx - 10} {by - 2} M{bx + 22} {by - 8} L{bx + 10} {by - 2}" stroke="{PINK_D}" stroke-width="3" stroke-linecap="round"/>'
           f'<circle cx="{bx}" cy="{by}" r="8" fill="{PINK_D}" stroke="{K}" stroke-width="4"/>'
           f'<circle cx="{bx - 2}" cy="{by - 2}" r="2.5" fill="#fff" opacity="0.7"/>')
    # eyelashes at the outer top corner of each eye (measured per body size)
    lx, rx = EYE[s]
    lashes = (f'<path d="M{lx + 1} 171 l-8 -5 M{lx + 5} 167 l-4 -8" stroke="{K}" stroke-width="3.5" stroke-linecap="round"/>'
              f'<path d="M{rx - 1} 171 l8 -5 M{rx - 5} 167 l4 -8" stroke="{K}" stroke-width="3.5" stroke-linecap="round"/>')
    return (f'<path d="{dome}" fill="{HAIR}" stroke="{K}" stroke-width="6" stroke-linejoin="round"/>'
            + shine + strands + bow + lashes)


def svg(inner):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="286" height="512" viewBox="0 0 286 512">{inner}</svg>'


def render(page, inner):
    uri = 'data:image/svg+xml;base64,' + base64.b64encode(svg(inner).encode()).decode()
    page.set_content(f'<html><body style="margin:0;background:transparent"><img src="{uri}" style="width:286px;height:512px;display:block"></body></html>')
    page.wait_for_timeout(50)
    return Image.open(io.BytesIO(page.screenshot(omit_background=True, clip=dict(x=0, y=0, width=286, height=512)))).convert('RGBA')


def pinkify(im):
    """green shirt -> pink shirt (keeps shading)."""
    im = im.convert('RGBA')
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if 0.36 < h < 0.48 and s > 0.25:
                nh = 0.93
                ns = min(1, s * 0.78)
                nv = min(1, v * 1.08)
                rr, gg, bb = colorsys.hsv_to_rgb(nh, ns, nv)
                px[x, y] = (int(rr * 255), int(gg * 255), int(bb * 255), a)
    return im


def main():
    with sync_playwright() as p:
        b = p.chromium.launch()
        page = b.new_page(viewport={'width': 286, 'height': 512})
        for t in TIERS:
            s = HS[t]
            os.makedirs(f'{DST}/{t}', exist_ok=True)
            back = render(page, hair_back(s))
            front = render(page, hair_front(s))
            for layer in ['body', 'arm_back', 'arm_front', 'leg_back', 'leg_front']:
                im = Image.open(f'{SRC}/{t}/{layer}.png')
                (pinkify(im) if layer in ('body', 'arm_back', 'arm_front') else im.convert('RGBA')).save(f'{DST}/{t}/{layer}.png', optimize=True)
            head = Image.open(f'{SRC}/{t}/head.png').convert('RGBA')
            out = Image.alpha_composite(back, head)
            out = Image.alpha_composite(out, front)
            out.save(f'{DST}/{t}/head.png', optimize=True)
            full = pinkify(Image.open(f'{SRC}/{t}/full.png'))
            full = Image.alpha_composite(Image.alpha_composite(back, full), front)
            full.save(f'{DST}/{t}/full.png', optimize=True)
        b.close()


if __name__ == '__main__':
    main()
