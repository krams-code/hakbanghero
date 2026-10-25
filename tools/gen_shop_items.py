"""HakbangHero shop item generator (new items).

Produces SVG layers in the same format as lib/models/hero_item_art.dart:
full 286x512 canvas, content inside <g transform="translate(3,64) scale(1.4)">,
key '<itemId>/<tier>/<layer>'.

Visual language: thick #1b1b1b outlines, flat fills, white 35% shine strips.
Pricier items get more detail: trims, gems, metal gradients, sparkles, glow.
"""
import json
import sys

K = '#1b1b1b'
TIERS = ['underweight', 'normal', 'overweight', 'obese']
HS = [0.93, 1.0, 1.08, 1.17]                       # head width scale
TORSO = [(75, 50, 84, 14), (66, 68, 86, 16), (57, 86, 90, 24), (47, 106, 96, 36)]
BELLY = [None, None, (43, 32, 224), (59, 38, 230)]  # rx, ry, cy
BELT_Y = [208, 210, 214, 220]
HL_H = [60, 62, 66, 72]
SH = [9, 0, -9, -19]                                # back-item x shift
LEGB = [(82, 218, 17, 62, 8.5), (75, 220, 24, 60, 10), (70, 224, 29, 56, 10), (65, 230, 34, 50, 10)]
SHOE_BX = [77, 70, 65, 60]
SHOE_W = [25, 32, 37, 42]
STRAP_BOT = [224, 226, 230, 236]
PACK_H = [88, 90, 94, 100]

_uid = [0]


def uid(p='nx'):
    _uid[0] += 1
    return f'{p}{_uid[0]}'


def wrap(inner):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="286" height="512" '
            'viewBox="0 0 286 512"><g transform="translate(3,64) scale(1.4)">'
            + inner + '</g></svg>')


def headwrap(i, inner):
    return f'<g transform="translate(100,0) scale({HS[i]},1) translate(-100,0)">{inner}</g>'


def f(v):
    return ('%.1f' % v).rstrip('0').rstrip('.') if isinstance(v, float) else str(v)


def R(x, y, w, h, rx, fill, sw=6, extra=''):
    s = f' stroke="{K}" stroke-width="{sw}" stroke-linejoin="round"' if sw else ''
    return f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="{f(rx)}" fill="{fill}"{s}{extra}/>'


def P(d, fill, sw=6, extra=''):
    s = f' stroke="{K}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round"' if sw else ''
    return f'<path d="{d}" fill="{fill}"{s}{extra}/>'


def L(d, color, w):
    return f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}" stroke-linejoin="round" stroke-linecap="round"/>'


def C(cx, cy, r, fill, sw=4, extra=''):
    s = f' stroke="{K}" stroke-width="{sw}"' if sw else ''
    return f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}" fill="{fill}"{s}{extra}/>'


def E(cx, cy, rx, ry, fill, sw=4, extra=''):
    s = f' stroke="{K}" stroke-width="{sw}"' if sw else ''
    return f'<ellipse cx="{f(cx)}" cy="{f(cy)}" rx="{f(rx)}" ry="{f(ry)}" fill="{fill}"{s}{extra}/>'


def shine(x, y, w, h, op=0.35):
    return f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="{f(min(w, h) / 2)}" fill="#fff" opacity="{op}"/>'


def sparkle(cx, cy, s, fill='#ffffff', sw=2):
    d = (f'M{f(cx)} {f(cy - s)} Q{f(cx)} {f(cy)} {f(cx + s)} {f(cy)} Q{f(cx)} {f(cy)} {f(cx)} {f(cy + s)} '
         f'Q{f(cx)} {f(cy)} {f(cx - s)} {f(cy)} Q{f(cx)} {f(cy)} {f(cx)} {f(cy - s)}Z')
    return P(d, fill, sw)


def star(cx, cy, r, fill, sw=2.5):
    import math
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = r if k % 2 == 0 else r * 0.45
        pts.append(f'{f(cx + rr * math.cos(a))} {f(cy + rr * math.sin(a))}')
    return P('M' + ' L'.join(pts) + 'Z', fill, sw)


def gem(cx, cy, r, fill, sw=3):
    d = f'M{f(cx)} {f(cy - r)} L{f(cx + r * 0.85)} {f(cy)} L{f(cx)} {f(cy + r)} L{f(cx - r * 0.85)} {f(cy)}Z'
    return P(d, fill, sw) + C(cx - r * 0.25, cy - r * 0.3, r * 0.22, '#fff', 0, ' opacity="0.8"')


def lingrad(gid, stops, vertical=True):
    xy = 'x1="0" y1="0" x2="0" y2="1"' if vertical else 'x1="0" y1="0" x2="1" y2="0"'
    st = ''.join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return f'<defs><linearGradient id="{gid}" {xy}>{st}</linearGradient></defs>'


GOLD = [(0, '#fff3b0'), (0.45, '#ffcc33'), (1, '#c98a00')]
SILVER = [(0, '#ffffff'), (0.5, '#c9d0da'), (1, '#7d8794')]
ICE = [(0, '#ffffff'), (0.5, '#9fe3ff'), (1, '#3aa0d8')]
FIRE = [(0, '#fff07a'), (0.45, '#ff9a1f'), (1, '#e0301e')]
PURPLE = [(0, '#b98cff'), (1, '#4b1f8f')]
GALAXY = [(0, '#3b2a8a'), (0.6, '#1a1446'), (1, '#0b0a24')]


# ─────────────────────────── builders ───────────────────────────

def torso(i, fill, inner=None, belt='#2b2f3a', after=None, defs=''):
    x, w, h, rx = TORSO[i]
    b = BELLY[i]
    cid = uid('tc')
    shapes = f'<rect x="{f(float(x))}" y="150" width="{w}" height="{h}" rx="{rx}"/>'
    if b:
        shapes += f'<ellipse cx="100" cy="{b[2]}" rx="{f(float(b[0]))}" ry="{b[1]}"/>'
    out = defs + f'<clipPath id="{cid}">{shapes}</clipPath>'
    out += shapes.replace('/>', f' fill="{fill}"/>')
    ctx = dict(x=x, w=w, r=x + w, h=h, bot=(b[2] + b[1]) if b else 150 + h, i=i)
    if inner:
        out += f'<g clip-path="url(#{cid})">{inner(ctx)}</g>'
    out += shine(x + 6, 156, 10, HL_H[i])
    out += shapes.replace('/>', f' fill="none" stroke="{K}" stroke-width="6"/>')
    if belt:
        out += R(x + 4, BELT_Y[i], w - 8, 14, 6, belt)
    if after:
        out += after(ctx)
    return {'body': out}


def legs(i, back, front, shorts=False, inner_f=None, inner_b=None, defs=''):
    x, y, w, h, rx = LEGB[i]
    fx = 101
    if shorts:
        x, fx, w = x - 1, fx - 1, w + 2
        h = 256 - y
    ctx = dict(bx=x, fx=fx, y=y, w=w, h=h, i=i)
    b = defs + R(x, y, w, h, rx, back) + (inner_b(ctx) if inner_b else '')
    fr = defs + R(fx, y, w, h, rx, front) + (inner_f(ctx) if inner_f else '')
    return {'leg_back': b, 'leg_front': fr}


def shoes(i, back, front, sole='#ffffff', boot=False, extra_b=None, extra_f=None, defs='', under=None):
    bw = SHOE_W[i]
    bx, fx = SHOE_BX[i], 98
    y, h = (268, 32) if boot else (284, 16)
    ctx = dict(bx=bx, fx=fx, w=bw, y=y, h=h, i=i)
    def one(x, fill, extra, side):
        s = defs
        if under:
            s += under(dict(ctx, x=x, side=side))
        s += R(x, y, bw, h, 8, fill)
        if sole:
            s += R(x + 3, 293, bw - 6, 5, 2, sole, 0)
        if extra:
            s += extra(dict(ctx, x=x, side=side))
        return s
    return {'leg_back': one(bx, back, extra_b or extra_f, 'b'), 'leg_front': one(fx, front, extra_f, 'f')}


def mirror(svg):
    return f'<g transform="translate(200,0) scale(-1,1)">{svg}</g>'


# ─────────────────────────── item designs ───────────────────────────
# each: (id, slot, name, emoji, rarity, coins, fn(i) -> {layer: inner})

ITEMS = []


def item(id, slot, name, emoji, rarity, coins):
    def deco(fn):
        ITEMS.append(dict(id=id, slot=slot, name=name, emoji=emoji, rarity=rarity, coins=coins, fn=fn))
        return fn
    return deco


# ════════════════ HEAD ════════════════

@item('sweatband', 'head', 'Sweatband', '\U0001F3BD', 0, 60)
def _(i):
    return {'head': headwrap(i, R(44, 40, 112, 16, 8, '#2f6bff') + R(60, 44, 40, 8, 4, '#ffffff', 0)
                             + shine(52, 43, 6, 6))}


@item('bucket_hat', 'head', 'Bucket Hat', '\U0001F452', 0, 150)
def _(i):
    return {'head': headwrap(i,
        P('M52 46 Q54 2 100 2 Q146 2 148 46 Z', '#d9b77a')
        + P('M26 56 Q30 40 52 42 L148 42 Q170 40 174 56 Q100 66 26 56Z', '#c49a55')
        + R(52, 34, 96, 9, 4, '#7a5a2b', 4)
        + shine(66, 12, 12, 18))}


@item('beret', 'head', 'Painter Beret', '\U0001F3A8', 0, 180)
def _(i):
    return {'head': headwrap(i,
        P('M40 44 Q36 6 100 4 Q170 4 162 36 Q156 50 100 50 Q56 52 40 44Z', '#e5484d')
        + P('M98 4 Q98 -8 108 -10', 'none', 5)
        + R(48, 40, 104, 10, 5, '#a31f26', 5)
        + shine(62, 12, 22, 8))}


@item('tophat', 'head', 'Top Hat', '\U0001F3A9', 1, 350)
def _(i):
    return {'head': headwrap(i,
        R(30, 40, 140, 14, 7, '#1d1d24')
        + R(62, -34, 76, 78, 8, '#26262e')
        + R(62, 20, 76, 14, 0, '#e5484d', 5)
        + shine(70, -26, 8, 40, 0.25)
        + C(122, 27, 4, '#ffd23f', 2.5))}


@item('viking', 'head', 'Viking Helm', '\U0001FA96', 1, 500)
def _(i):
    horn_l = P('M48 40 Q18 30 20 -14 Q34 10 58 22Z', '#f4ead2', 5)
    horn_r = P('M152 40 Q182 30 180 -14 Q166 10 142 22Z', '#f4ead2', 5)
    return {'head': headwrap(i,
        horn_l + horn_r
        + P('M42 56 V44 Q42 2 100 2 Q158 2 158 44 V56 Z', '#b9c2ce')
        + R(40, 44, 120, 14, 6, '#8a5a2b')
        + R(94, 2, 12, 46, 4, '#8f98a6', 4)
        + ''.join(C(x, 51, 2.5, '#ffd23f', 0) for x in (56, 76, 124, 144))
        + shine(56, 12, 10, 26))}


@item('pirate_hat', 'head', 'Captain Hat', '\U0001F3F4', 2, 800)
def _(i):
    gid = uid('g')
    return {'head': headwrap(i,
        lingrad(gid, [(0, '#2b2b33'), (1, '#111116')])
        + P('M20 50 Q36 -4 100 -10 Q164 -4 180 50 Q140 36 100 40 Q60 36 20 50Z', f'url(#{gid})')
        + L('M24 47 Q60 33 100 37 Q140 33 176 47', '#ffcc33', 5)
        + C(100, 14, 11, '#f4f4f4', 4)
        + C(96, 12, 2.6, K, 0) + C(104, 12, 2.6, K, 0)
        + L('M88 26 L112 34 M112 26 L88 34', '#f4f4f4', 4)
        + sparkle(150, 10, 6, '#ffd23f'))}


@item('crown_ice', 'head', 'Frost Crown', '❄️', 2, 1200)
def _(i):
    gid = uid('g')
    spikes = P('M46 46 L40 4 L60 26 L72 -14 L86 22 L100 -26 L114 22 L128 -14 L140 26 L160 4 L154 46Z',
               f'url(#{gid})')
    return {'head': headwrap(i,
        lingrad(gid, ICE)
        + L('M46 46 L40 4 L60 26 L72 -14 L86 22 L100 -26 L114 22 L128 -14 L140 26 L160 4 L154 46', '#bff0ff', 14).replace('stroke="#bff0ff"', 'stroke="#bff0ff" opacity="0.35"')
        + spikes
        + R(44, 38, 112, 14, 6, '#e8f8ff')
        + gem(100, 10, 9, '#4aa3ff') + gem(72, 18, 5, '#9fe3ff') + gem(128, 18, 5, '#9fe3ff')
        + sparkle(30, 0, 7) + sparkle(170, 20, 5) + sparkle(118, -24, 4))}


@item('crown_royal', 'head', 'Royal Crown', '\U0001F451', 3, 2800)
def _(i):
    gid = uid('g')
    return {'head': headwrap(i,
        lingrad(gid, GOLD)
        + E(100, 18, 70, 34, '#ffe27a', 0, ' opacity="0.35"')
        + P('M58 40 Q60 -6 100 -10 Q140 -6 142 40Z', '#7b2fbf', 5)
        + P('M44 46 L38 -2 L64 22 L80 -22 L100 10 L120 -22 L136 22 L162 -2 L156 46Z', f'url(#{gid})')
        + C(80, -22, 5, '#ffffff', 3) + C(120, -22, 5, '#ffffff', 3)
        + C(38, -2, 4.5, '#ffffff', 3) + C(162, -2, 4.5, '#ffffff', 3)
        + R(40, 38, 120, 16, 7, f'url(#{gid})')
        + ''.join(C(x, 46, 2.4, '#fff', 0) for x in (52, 60, 140, 148))
        + gem(100, 46, 9, '#e5484d') + gem(76, 46, 6, '#2f6bff') + gem(124, 46, 6, '#2fd27a')
        + gem(100, 14, 7, '#2f6bff')
        + sparkle(26, 18, 8, '#fff6b0') + sparkle(176, 6, 7, '#fff6b0') + sparkle(100, -30, 5, '#fff6b0'))}


# ════════════════ FACE ════════════════

@item('freckles', 'face', 'Freckles', '\U0001F33E', 0, 50)
def _(i):
    dots = ''.join(C(x, y, 2.8, '#8a4a22', 0) for x, y in
                   ((62, 97), (69, 103), (74, 96), (59, 104), (126, 96), (131, 103), (138, 97), (141, 104)))
    return {'head': headwrap(i, dots)}


@item('blush', 'face', 'Rosy Blush', '\U0001F60A', 0, 60)
def _(i):
    return {'head': headwrap(i, E(66, 100, 10, 6, '#ff7aa2', 0, ' opacity="0.75"')
                             + E(134, 100, 10, 6, '#ff7aa2', 0, ' opacity="0.75"')
                             + C(62, 98, 1.8, '#fff', 0, ' opacity="0.8"') + C(130, 98, 1.8, '#fff', 0, ' opacity="0.8"'))}


@item('bandage', 'face', 'Bandage', '\U0001FA79', 0, 70)
def _(i):
    return {'head': headwrap(i,
        f'<g transform="rotate(-20 132 98)">' + R(118, 92, 28, 12, 5, '#f2c58a', 3.5)
        + R(127, 94, 10, 8, 2, '#e0a96a', 0)
        + ''.join(C(x, y, 0.9, '#b07a3a', 0) for x, y in ((129, 96), (134, 96), (129, 100), (134, 100)))
        + '</g>')}


@item('glasses_nerd', 'face', 'Nerd Glasses', '\U0001F913', 0, 120)
def _(i):
    return {'head': headwrap(i,
        R(64, 72, 34, 26, 5, '#ffffff', 5, ' fill-opacity=".18"')
        + R(102, 72, 34, 26, 5, '#ffffff', 5, ' fill-opacity=".18"')
        + L('M98 82 H102', K, 5) + R(64, 72, 34, 6, 3, K, 0) + R(102, 72, 34, 6, 3, K, 0))}


@item('goggles_swim', 'face', 'Swim Goggles', '\U0001F97D', 0, 160)
def _(i):
    return {'head': headwrap(i,
        R(42, 78, 116, 10, 5, '#2f6bff', 4)
        + E(82, 84, 17, 13, '#7fd6ff', 5, ' fill-opacity=".8"')
        + E(118, 84, 17, 13, '#7fd6ff', 5, ' fill-opacity=".8"')
        + R(96, 80, 8, 7, 3, '#2f6bff', 3)
        + C(76, 79, 4, '#fff', 0, ' opacity="0.8"') + C(112, 79, 4, '#fff', 0, ' opacity="0.8"'))}


@item('eyepatch', 'face', 'Pirate Patch', '\U0001F3F4‍☠️', 1, 280)
def _(i):
    return {'head': headwrap(i,
        L('M44 62 L150 104', K, 5)
        + P('M66 74 Q82 66 98 74 Q100 92 82 100 Q64 92 66 74Z', '#1d1d24', 5)
        + L('M74 80 Q82 76 90 80', '#3c3c48', 3))}


@item('beard', 'face', 'Bushy Beard', '\U0001F9D4', 1, 350)
def _(i):
    return {'head': headwrap(i,
        P('M50 88 Q50 132 100 136 Q150 132 150 88 Q144 108 126 108 Q114 116 100 112 Q86 116 74 108 Q56 108 50 88Z',
          '#6b4226', 5)
        + P('M82 102 Q91 96 100 101 Q109 96 118 102 Q109 108 100 105 Q91 108 82 102Z', '#4e2f1a', 3.5)
        + L('M70 118 q4 6 8 2 M92 124 q4 6 8 2 M114 118 q4 6 8 2', '#4e2f1a', 3))}


@item('visor_cyber', 'face', 'Cyber Visor', '\U0001F576️', 1, 500)
def _(i):
    return {'head': headwrap(i,
        R(48, 70, 104, 26, 13, '#00e5ff', 0, ' opacity="0.3"')
        + R(52, 72, 96, 22, 11, '#0f1a2a', 5)
        + R(58, 78, 84, 10, 5, '#00e5ff', 0)
        + R(62, 80, 30, 3, 1.5, '#ffffff', 0, ' opacity="0.9"')
        + C(146, 83, 3, '#ff3b8d', 0))}


@item('shades_star', 'face', 'Star Shades', '⭐', 2, 700)
def _(i):
    return {'head': headwrap(i,
        star(81, 84, 20, '#ff5fb0', 4.5) + star(119, 84, 20, '#ff5fb0', 4.5)
        + L('M99 82 H101', K, 5)
        + C(76, 78, 3.2, '#fff', 0, ' opacity="0.85"') + C(114, 78, 3.2, '#fff', 0, ' opacity="0.85"')
        + sparkle(146, 66, 6, '#fff6b0'))}


@item('mask_masq', 'face', 'Masquerade Mask', '\U0001F3AD', 2, 1000)
def _(i):
    gid = uid('g')
    return {'head': headwrap(i,
        lingrad(gid, PURPLE)
        + P('M150 70 Q170 40 162 20 Q160 46 146 60Z', '#2fd27a', 4)
        + P('M152 72 Q182 56 184 34 Q172 56 150 64Z', '#ffcc33', 4)
        + P('M46 76 Q60 62 84 70 Q100 76 116 70 Q140 62 154 76 Q150 98 124 98 Q108 98 100 88 Q92 98 76 98 Q50 98 46 76Z',
            f'url(#{gid})', 5)
        + E(80, 82, 11, 7, K, 0) + E(120, 82, 11, 7, K, 0)
        + L('M50 78 Q62 68 82 74 M150 78 Q138 68 118 74', '#ffcc33', 3)
        + gem(100, 80, 5, '#ffcc33', 2.5))}


@item('shades_diamond', 'face', 'Diamond Shades', '\U0001F48E', 3, 2200)
def _(i):
    gid, lg = uid('g'), uid('g')
    return {'head': headwrap(i,
        lingrad(gid, GOLD) + lingrad(lg, [(0, '#e9fbff'), (0.5, '#7fd6ff'), (1, '#b48cff')])
        + R(56, 64, 88, 40, 20, '#fff6b0', 0, ' opacity="0.35"')
        + P('M62 74 L98 74 L94 96 L68 96Z', f'url(#{lg})', 5)
        + P('M102 74 L138 74 L132 96 L106 96Z', f'url(#{lg})', 5)
        + R(58, 70, 84, 7, 3.5, f'url(#{gid})', 3.5)
        + L('M68 78 L80 92 M80 78 L92 92 M108 78 L120 92 M120 78 L132 92', '#ffffff', 1.5)
        + gem(60, 73, 4.5, '#e5484d', 2.5) + gem(140, 73, 4.5, '#e5484d', 2.5) + gem(100, 73, 4, '#2fd27a', 2.5)
        + sparkle(150, 60, 7, '#ffffff') + sparkle(52, 98, 5, '#ffffff'))}


# ════════════════ TOP ════════════════

@item('tee_lime', 'top', 'Lime Tee', '\U0001F455', 0, 80)
def _(i):
    return torso(i, '#7ee08a', inner=lambda c: R(106, 162, 16, 14, 3, '#5cc46a', 3))


@item('polo_navy', 'top', 'Navy Polo', '\U0001F454', 0, 140)
def _(i):
    return torso(i, '#25407a', inner=lambda c:
                 P('M84 150 L100 166 L116 150 L112 146 L100 158 L88 146Z', '#ffffff', 3.5)
                 + ''.join(C(100, y, 2.4, '#ffffff', 1.5) for y in (172, 182)))


@item('tank_sport', 'top', 'Sport Tank', '\U0001F3C0', 0, 180)
def _(i):
    return torso(i, '#f4f4f4', inner=lambda c:
                 R(c['x'] - 2, 150, 12, 120, 0, '#e5484d', 0) + R(c['r'] - 10, 150, 12, 120, 0, '#e5484d', 0)
                 + L('M92 168 L106 168 L97 198', '#e5484d', 6), belt='#e5484d')


@item('flannel', 'top', 'Flannel Shirt', '\U0001F332', 1, 300)
def _(i):
    def inner(c):
        s = ''
        for x in range(c['x'] - 4, c['r'] + 8, 14):
            s += R(x, 140, 6, 160, 0, '#7a1a1f', 0, ' opacity="0.7"')
        for y in range(156, 300, 14):
            s += R(c['x'] - 10, y, c['w'] + 20, 5, 0, '#2b1012', 0, ' opacity="0.55"')
        s += L('M100 150 V240', '#2b1012', 3)
        s += ''.join(C(103, y, 2, '#f4ead2', 1) for y in (166, 182, 198))
        return s
    return torso(i, '#d13a3f', inner=inner, belt='#3a2a22')


@item('varsity', 'top', 'Varsity Jacket', '\U0001F3C8', 1, 450)
def _(i):
    return torso(i, '#1e4fb4', inner=lambda c:
                 R(c['x'] - 2, 150, 10, 140, 0, '#f4f4f4', 0) + R(c['r'] - 8, 150, 10, 140, 0, '#f4f4f4', 0)
                 + L('M86 150 L100 162 L114 150', '#f4f4f4', 5)
                 + star(84, 184, 10, '#ffcc33')
                 + ''.join(C(104, y, 2.2, '#ffcc33', 1.5) for y in (172, 186, 200)),
                 belt='#f4f4f4')


@item('track_retro', 'top', 'Retro Track Jacket', '\U0001F3C3', 1, 500)
def _(i):
    return torso(i, '#7b3fe4', inner=lambda c:
                 R(c['x'] + 2, 150, 7, 140, 0, '#ffffff', 0) + R(c['x'] + 11, 150, 4, 140, 0, '#ffcc33', 0)
                 + R(c['r'] - 9, 150, 7, 140, 0, '#ffffff', 0) + R(c['r'] - 15, 150, 4, 140, 0, '#ffcc33', 0)
                 + L('M100 152 V206', '#d9d9d9', 3) + R(97, 160, 6, 9, 2, '#d9d9d9', 2)
                 + R(c['x'] - 4, 150, c['w'] + 8, 9, 0, '#2b1866', 0), belt='#2b1866')


@item('robe_star', 'top', 'Starry Robe', '\U0001F31F', 2, 900)
def _(i):
    gid = uid('g')
    return torso(i, f'url(#{gid})', defs=lingrad(gid, [(0, '#4a2a9a'), (1, '#1d1150')]), inner=lambda c:
                 L(f'M{c["x"]} 150 L100 192 L{c["r"]} 150', '#ffcc33', 6)
                 + star(c['x'] + 12, 206, 6, '#ffe27a', 2) + star(c['r'] - 12, 176, 5, '#ffe27a', 2)
                 + star(110, 218, 4, '#ffe27a', 2) + C(c['x'] + 16, 172, 2, '#fff', 0) + C(c['r'] - 16, 214, 2, '#fff', 0),
                 belt='#ffcc33', after=lambda c: sparkle(c['r'] + 6, 160, 6, '#fff6b0'))


@item('armor_crystal', 'top', 'Crystal Plate', '\U0001F48E', 2, 1200)
def _(i):
    gid = uid('g')
    return torso(i, f'url(#{gid})', defs=lingrad(gid, ICE), inner=lambda c:
                 L(f'M{c["x"]} 176 L100 196 L{c["r"]} 176', '#2a82b8', 4)
                 + L(f'M{c["x"]} 160 L100 180 L{c["r"]} 160', '#ffffff', 3)
                 + gem(100, 186, 11, '#4aa3ff') + gem(c['x'] + 14, 168, 4, '#e9fbff', 2) + gem(c['r'] - 14, 168, 4, '#e9fbff', 2),
                 belt='#2a82b8', after=lambda c: sparkle(c['x'] - 4, 170, 6) + sparkle(c['r'] + 4, 200, 5))


@item('armor_dragon', 'top', 'Dragon Scale Armor', '\U0001F409', 3, 2500)
def _(i):
    gid, gg = uid('g'), uid('g')
    def inner(c):
        s = ''
        row = 0
        for y in range(154, 290, 12):
            off = 0 if row % 2 == 0 else 8
            for x in range(c['x'] - 16 + off, c['r'] + 16, 16):
                s += P(f'M{x} {y} Q{x + 8} {y + 14} {x + 16} {y}', '#8e1420', 2.5)
            row += 1
        s += L(f'M{c["x"]} 150 L100 186 L{c["r"]} 150', f'url(#{gg})', 7)
        s += C(100, 190, 13, '#ff6a3d', 0, ' opacity="0.45"')
        s += gem(100, 190, 10, '#ff3b2f')
        return s
    return torso(i, f'url(#{gid})', defs=lingrad(gid, [(0, '#e0303f'), (1, '#7a0f1c')]) + lingrad(gg, GOLD),
                 inner=inner, belt=f'url(#{gg})',
                 after=lambda c: sparkle(c['r'] + 8, 166, 7, '#fff6b0') + sparkle(c['x'] - 8, 214, 5, '#fff6b0'))


# ════════════════ BOTTOM ════════════════

@item('shorts_denim', 'bottom', 'Denim Shorts', '\U0001FA73', 0, 70)
def _(i):
    return legs(i, '#3d6db3', '#4f86d6', shorts=True,
                inner_f=lambda c: L(f'M{c["fx"] + 4} {c["y"] + c["h"] - 6} H{c["fx"] + c["w"] - 4}', '#a9c8f0', 2.5))


@item('shorts_gym', 'bottom', 'Gym Shorts', '\U0001F3CB', 0, 90)
def _(i):
    return legs(i, '#1f8f4e', '#2fb563', shorts=True,
                inner_f=lambda c: R(c['fx'] + c['w'] - 8, c['y'] + 4, 4, c['h'] - 8, 0, '#ffffff', 0))


@item('jeans', 'bottom', 'Blue Jeans', '\U0001F456', 0, 150)
def _(i):
    return legs(i, '#2e5591', '#3d6db3',
                inner_f=lambda c: L(f'M{c["fx"] + c["w"] / 2} {c["y"] + 6} V{c["y"] + c["h"] - 10}', '#7fa6dc', 2)
                + R(c['fx'] + 1, c['y'] + c['h'] - 10, c['w'] - 2, 7, 3, '#5a86c8', 0),
                inner_b=lambda c: R(c['bx'] + 1, c['y'] + c['h'] - 10, c['w'] - 2, 7, 3, '#4a74b3', 0))


@item('pants_khaki', 'bottom', 'Khaki Pants', '\U0001F9F3', 0, 180)
def _(i):
    return legs(i, '#a88a55', '#c4a46a',
                inner_f=lambda c: L(f'M{c["fx"] + c["w"] / 2} {c["y"] + 6} V{c["y"] + c["h"] - 6}', '#8a6f3f', 2)
                + R(c['fx'] + 1, c['y'] + c['h'] - 9, c['w'] - 2, 6, 3, '#a88a55', 0))


@item('joggers', 'bottom', 'Black Joggers', '\U0001F3C3', 1, 280)
def _(i):
    cuff = lambda c, x: R(x + 1, c['y'] + c['h'] - 9, c['w'] - 2, 7, 3, '#e5e5e5', 2)
    return legs(i, '#22232a', '#2d2f38',
                inner_f=lambda c: R(c['fx'] + c['w'] - 7, c['y'] + 4, 3, c['h'] - 16, 0, '#e5484d', 0) + cuff(c, c['fx']),
                inner_b=lambda c: cuff(c, c['bx']))


@item('shorts_board', 'bottom', 'Board Shorts', '\U0001F3C4', 1, 320)
def _(i):
    flowers = lambda c, x: ''.join(C(x + dx, c['y'] + dy, 3.4, '#ffe27a', 1.5) + C(x + dx, c['y'] + dy, 1.2, '#e5484d', 0)
                                   for dx, dy in ((c['w'] * 0.3, 10), (c['w'] * 0.7, 22)))
    return legs(i, '#e86a10', '#ff8a1f', shorts=True,
                inner_f=lambda c: flowers(c, c['fx']), inner_b=lambda c: flowers(c, c['bx']))


@item('pants_plaid', 'bottom', 'Plaid Pants', '\U0001F3B8', 1, 450)
def _(i):
    def plaid(c, x):
        s = ''
        for yy in range(c['y'] + 6, c['y'] + c['h'] - 4, 12):
            s += R(x + 2, yy, c['w'] - 4, 4, 0, '#1b1b1b', 0, ' opacity="0.55"')
        s += R(x + c['w'] / 2 - 2, c['y'] + 4, 4, c['h'] - 8, 0, '#ffcc33', 0, ' opacity="0.8"')
        return s
    return legs(i, '#a3232b', '#c92f38', inner_f=lambda c: plaid(c, c['fx']), inner_b=lambda c: plaid(c, c['bx']))


@item('hakama', 'bottom', 'Shadow Hakama', '\U0001F977', 2, 750)
def _(i):
    gid = uid('g')
    band = lambda c, x: R(x + 1, c['y'] + 4, c['w'] - 2, 6, 2, '#ffcc33', 0) + R(x + 1, c['y'] + c['h'] - 12, c['w'] - 2, 4, 2, '#ffcc33', 0)
    return legs(i, '#2a1a4a', f'url(#{gid})', defs=lingrad(gid, [(0, '#5a33a8'), (1, '#24124f')]),
                inner_f=lambda c: band(c, c['fx']) + sparkle(c['fx'] + c['w'] + 6, c['y'] + 20, 5, '#fff6b0'),
                inner_b=lambda c: band(c, c['bx']))


@item('leggings_galaxy', 'bottom', 'Galaxy Leggings', '\U0001F30C', 2, 1100)
def _(i):
    gid = uid('g')
    def stars(c, x):
        return (star(x + c['w'] * 0.5, c['y'] + 14, 4.5, '#fff6b0', 1.5)
                + C(x + c['w'] * 0.3, c['y'] + 30, 1.6, '#ffffff', 0) + C(x + c['w'] * 0.7, c['y'] + 40, 1.6, '#9fe3ff', 0)
                + C(x + c['w'] * 0.4, c['y'] + 50, 1.3, '#ff9ee0', 0))
    return legs(i, f'url(#{gid})', f'url(#{gid})', defs=lingrad(gid, GALAXY),
                inner_f=lambda c: stars(c, c['fx']) + R(c['fx'] + 4, c['y'] + 6, 3, c['h'] - 14, 1.5, '#ffffff', 0, ' opacity="0.25"'),
                inner_b=lambda c: stars(c, c['bx']))


@item('greaves', 'bottom', 'Knight Greaves', '\U0001F6E1️', 2, 1300)
def _(i):
    gid = uid('g')
    plate = lambda c, x: (L(f'M{x + 2} {c["y"] + 16} H{x + c["w"] - 2} M{x + 2} {c["y"] + 46} H{x + c["w"] - 2}', '#6b7482', 3)
                          + P(f'M{x + c["w"] / 2} {c["y"] + 22} L{x + c["w"] - 2} {c["y"] + 31} L{x + c["w"] / 2} {c["y"] + 40} L{x + 2} {c["y"] + 31}Z', '#e8edf3', 3.5))
    return legs(i, '#9aa3b0', f'url(#{gid})', defs=lingrad(gid, SILVER, vertical=False),
                inner_f=lambda c: plate(c, c['fx']) + sparkle(c['fx'] + c['w'] + 5, c['y'] + 8, 5),
                inner_b=lambda c: plate(c, c['bx']))


@item('pants_royal', 'bottom', 'Royal Trousers', '\U0001F451', 3, 2200)
def _(i):
    gid, pg = uid('g'), uid('g')
    deco = lambda c, x: (R(x + c['w'] / 2 - 3, c['y'] + 2, 6, c['h'] - 4, 0, f'url(#{gid})', 0)
                         + gem(x + c['w'] / 2, c['y'] + 30, 6, '#e5484d', 2.5)
                         + R(x + 1, c['y'] + c['h'] - 10, c['w'] - 2, 7, 3, f'url(#{gid})', 2))
    return legs(i, '#4b1f8f', f'url(#{pg})', defs=lingrad(gid, GOLD) + lingrad(pg, PURPLE),
                inner_f=lambda c: deco(c, c['fx']) + sparkle(c['fx'] + c['w'] + 7, c['y'] + 14, 6, '#fff6b0'),
                inner_b=lambda c: deco(c, c['bx']))


# ════════════════ SHOES ════════════════

@item('slides', 'shoes', 'Comfy Slides', '\U0001FA74', 0, 60)
def _(i):
    w = SHOE_W[i]
    def one(x, side):
        return R(x, 293, w, 7, 3.5, '#2b2f3a', 5) + R(x + 3, 286, w - 6, 9, 4, '#2f6bff', 4)
    return {'leg_back': one(SHOE_BX[i], 'b'), 'leg_front': one(98, 'f')}


@item('sneak_blue', 'shoes', 'Blue Kicks', '\U0001F45F', 0, 70)
def _(i):
    return shoes(i, '#275ad8', '#2f6bff', extra_f=lambda c: C(c['x'] + c['w'] * 0.4, 289, 2, '#fff', 0))


@item('sneak_white', 'shoes', 'Clean Whites', '\U0001F45F', 0, 100)
def _(i):
    return shoes(i, '#e3e3e3', '#ffffff', sole='#cfcfcf',
                 extra_f=lambda c: R(c['x'] + c['w'] * 0.55, 287, c['w'] * 0.3, 4, 2, '#2fd27a', 0))


@item('hightops', 'shoes', 'Hi-Tops', '\U0001F45F', 0, 180)
def _(i):
    laces = lambda c: L(f'M{c["x"] + 6} 276 H{c["x"] + c["w"] - 8} M{c["x"] + 6} 283 H{c["x"] + c["w"] - 8}', '#ffffff', 2.5) \
        + C(c['x'] + c['w'] - 9, 290, 4.5, '#ffffff', 2.5) + C(c['x'] + c['w'] - 9, 290, 2, '#e5484d', 0)
    return shoes(i, '#202027', '#2b2b33', boot=True, extra_f=laces, extra_b=laces)


@item('boots_hiking', 'shoes', 'Hiking Boots', '\U0001F97E', 1, 300)
def _(i):
    laces = lambda c: L(f'M{c["x"] + 6} 275 L{c["x"] + c["w"] - 10} 280 M{c["x"] + 6} 282 L{c["x"] + c["w"] - 10} 287', '#ff8a1f', 2.5) \
        + R(c['x'] + 2, 268, c['w'] - 4, 6, 3, '#5a3a1e', 0)
    return shoes(i, '#7a4a22', '#8f5a2b', sole='#3a2a22', boot=True, extra_f=laces, extra_b=laces)


@item('cleats', 'shoes', 'Pro Cleats', '⚽', 1, 400)
def _(i):
    under = lambda c: ''.join(R(c['x'] + k * (c['w'] - 6) / 3, 298, 6, 6, 1.5, '#e3e3e3', 2) for k in range(4))
    return shoes(i, '#1f8f4e', '#2fd27a', sole='#ffffff', under=under,
                 extra_f=lambda c: L(f'M{c["x"] + 6} 290 Q{c["x"] + c["w"] / 2} 284 {c["x"] + c["w"] - 6} 290', '#ffffff', 2.5))


@item('sneak_flame', 'shoes', 'Flame Kicks', '\U0001F525', 1, 550)
def _(i):
    flame = lambda c: P(f'M{c["x"] + 4} 296 Q{c["x"] + 8} 284 {c["x"] + 12} 290 Q{c["x"] + 16} 282 {c["x"] + 20} 291 '
                        f'Q{c["x"] + 24} 285 {c["x"] + c["w"] - 3} 296Z', '#ff8a1f', 0) \
        + P(f'M{c["x"] + 8} 296 Q{c["x"] + 12} 289 {c["x"] + 15} 293 Q{c["x"] + 19} 288 {c["x"] + c["w"] - 6} 296Z', '#ffd23f', 0)
    return shoes(i, '#1d1d24', '#2b2b33', sole='#ff8a1f', extra_f=flame, extra_b=flame)


@item('boots_frost', 'shoes', 'Frost Boots', '❄️', 2, 900)
def _(i):
    gid = uid('g')
    fur = lambda c: P(f'M{c["x"] - 2} 272 Q{c["x"] + 4} 262 {c["x"] + c["w"] * 0.35} 268 Q{c["x"] + c["w"] * 0.6} 260 '
                      f'{c["x"] + c["w"] * 0.8} 268 Q{c["x"] + c["w"] + 4} 262 {c["x"] + c["w"] + 2} 274 L{c["x"] - 2} 276Z', '#ffffff', 4)
    return shoes(i, '#5fb7e6', f'url(#{gid})', sole='#e9fbff', boot=True, defs=lingrad(gid, ICE),
                 extra_f=lambda c: fur(c) + gem(c['x'] + c['w'] / 2, 284, 4.5, '#4aa3ff', 2) + sparkle(c['x'] + c['w'] + 6, 270, 5),
                 extra_b=fur)


@item('sneak_galaxy', 'shoes', 'Galaxy Runners', '\U0001F30C', 2, 1200)
def _(i):
    gid = uid('g')
    deco = lambda c: (star(c['x'] + c['w'] * 0.4, 289, 4, '#fff6b0', 1.5) + C(c['x'] + c['w'] * 0.75, 288, 1.5, '#9fe3ff', 0)
                      + R(c['x'] + 1, 298, c['w'] - 2, 4, 2, '#00e5ff', 0, ' opacity="0.6"'))
    return shoes(i, f'url(#{gid})', f'url(#{gid})', sole='#00e5ff', defs=lingrad(gid, GALAXY),
                 extra_f=lambda c: deco(c) + sparkle(c['x'] + c['w'] + 5, 282, 5, '#fff6b0'), extra_b=deco)


@item('boots_dragon', 'shoes', 'Dragon Boots', '\U0001F409', 3, 2400)
def _(i):
    gid, gg = uid('g'), uid('g')
    deco = lambda c: (R(c['x'] + c['w'] - 13, 286, 13, 14, 6, f'url(#{gg})', 4)
                      + R(c['x'] + 1, 268, c['w'] - 2, 7, 3, f'url(#{gg})', 3)
                      + gem(c['x'] + c['w'] * 0.38, 283, 5, '#ff3b2f', 2.5))
    flames = lambda c: (P(f'M{c["x"] + 4} 300 Q{c["x"] + 10} 320 {c["x"] + c["w"] / 2} 306 Q{c["x"] + c["w"] - 8} 322 {c["x"] + c["w"] - 3} 300Z',
                          '#ff8a1f', 3) + P(f'M{c["x"] + 10} 300 Q{c["x"] + c["w"] / 2} 314 {c["x"] + c["w"] - 9} 300Z', '#ffe27a', 0))
    return shoes(i, '#8e1420', f'url(#{gid})', sole=None, boot=True,
                 defs=lingrad(gid, [(0, '#e0303f'), (1, '#7a0f1c')]) + lingrad(gg, GOLD),
                 under=flames,
                 extra_f=lambda c: deco(c) + sparkle(c['x'] + c['w'] + 7, 272, 6, '#fff6b0'), extra_b=deco)


# ════════════════ BACK ════════════════

@item('sling_bag', 'back', 'Sling Bag', '\U0001F45C', 0, 90)
def _(i):
    s = SH[i]
    x, w, h, rx = TORSO[i]
    return {
        'back': R(x + w - 10, 196, 30, 26, 8, '#2fb5a5') + R(x + w - 6, 200, 22, 8, 3, '#1f8a7d', 0),
        'body': L(f'M{x + 10} 152 L{x + w - 4} {BELT_Y[i] - 6}', '#1b1b1b', 12) + L(f'M{x + 10} 152 L{x + w - 4} {BELT_Y[i] - 6}', '#2fb5a5', 6),
    }


@item('backpack_school', 'back', 'School Pack', '\U0001F392', 0, 150)
def _(i):
    s = SH[i]
    bw, bh = 100 - 2 * s, PACK_H[i]
    return {
        'back': R(50 + s, 146, bw, bh, 18, '#2f6bff') + R(54 + s, 146 + bh - 30, bw - 8, 24, 8, '#ffcc33')
                + shine(56 + s, 154, 5, 40),
        'body': L(f'M{78 + s} 152 L{84 + s} {STRAP_BOT[i]}', '#1f4fb4', 10) + L(f'M{122 - s} 152 L{116 - s} {STRAP_BOT[i]}', '#1f4fb4', 10),
    }


@item('quiver', 'back', 'Archer Quiver', '\U0001F3F9', 0, 200)
def _(i):
    s = SH[i]
    arrows = ''.join(L(f'M{x} 150 L{x + 6} 116', '#8a5a2b', 3) + P(f'M{x + 6} 116 l-6 4 9 -14 3 16z', '#e5e5e5', 2)
                     for x in (124 - s, 132 - s, 140 - s))
    return {'back': arrows + f'<g transform="rotate(20 {136 - s} 190)">' + R(122 - s, 140, 28, 92, 10, '#8a5a2b')
                    + R(122 - s, 150, 28, 8, 0, '#6b4226', 3) + R(122 - s, 210, 28, 8, 0, '#6b4226', 3) + '</g>',
            'body': L(f'M{70 + s} 152 L{130 - s} {BELT_Y[i]}', '#6b4226', 8)}


@item('cape_night', 'back', 'Night Cape', '\U0001F319', 1, 300)
def _(i):
    s = SH[i]
    return {'back': P(f'M{62 + s} 152 L{138 - s} 152 L{168 - s} 288 L{32 + s} 288Z', '#1d2a5a')
                    + P(f'M{36 + s} 280 L{164 - s} 280 L{168 - s} 288 L{32 + s} 288Z', '#ffcc33', 4)
                    + star(150 - s, 200, 9, '#ffe27a') + C(140 - s, 246, 3, '#ffffff', 0) + C(58 + s, 226, 2.5, '#ffffff', 0)
                    + shine(132 - s, 160, 5, 100)}


@item('surfboard', 'back', 'Surfboard', '\U0001F3C4', 1, 380)
def _(i):
    s = SH[i]
    return {'back': f'<g transform="rotate(-24 100 200)">'
                    + E(100, 200, 22, 98, '#ffcc33', 6)
                    + R(97, 106, 6, 188, 3, '#e5484d', 0)
                    + E(100, 200, 10, 70, '#ffffff', 0, ' opacity="0.25"') + '</g>'}


@item('wings_butterfly', 'back', 'Butterfly Wings', '\U0001F98B', 1, 550)
def _(i):
    s = SH[i]
    ax = 72 + s
    def wing():
        return (P(f'M{ax} 172 C{ax - 30} 120 {ax - 70} 136 {ax - 58} 180 C{ax - 54} 196 {ax - 24} 196 {ax} 184Z', '#ff7ac8', 5)
                + P(f'M{ax} 188 C{ax - 22} 196 {ax - 52} 214 {ax - 36} 234 C{ax - 22} 244 {ax - 6} 220 {ax} 196Z', '#9b59ff', 5)
                + C(ax - 38, 164, 8, '#ffe27a', 3) + C(ax - 26, 218, 5, '#ffffff', 2.5))
    k = [1, 1, 0.88, 0.76][i]
    sq = lambda w: f'<g transform="translate({ax},0) scale({k},1) translate({-ax},0)">{w}</g>'
    return {'back': sq(wing()) + mirror(sq(wing()))}


@item('shield_round', 'back', 'Knight Shield', '\U0001F6E1️', 2, 750)
def _(i):
    s = SH[i]
    gid = uid('g')
    cx = max(46 + s, 42)
    return {'back': lingrad(gid, SILVER)
                    + C(cx, 210, 40, f'url(#{gid})', 6)
                    + C(cx, 210, 30, '#2f6bff', 4)
                    + P(f'M{cx} 186 L{cx + 7} 202 L{cx + 24} 204 L{cx + 11} 215 L{cx + 15} 232 L{cx} 223 L{cx - 15} 232 L{cx - 11} 215 L{cx - 24} 204 L{cx - 7} 202Z', '#ffcc33', 3)
                    + ''.join(C(cx + dx, 210 + dy, 2.5, '#5b6472', 0) for dx, dy in ((0, -36), (0, 36), (-36, 0), (36, 0)))
                    + sparkle(cx - 34, 176, 6)}


@item('wings_fairy', 'back', 'Fairy Wings', '\U0001F9DA', 2, 900)
def _(i):
    s = SH[i]
    ax = 72 + s
    def wing():
        return (P(f'M{ax} 176 C{ax - 20} 110 {ax - 64} 112 {ax - 62} 150 C{ax - 60} 176 {ax - 24} 186 {ax} 184Z', '#9fe3ff', 4,
                  ' fill-opacity="0.75"')
                + P(f'M{ax} 190 C{ax - 30} 196 {ax - 54} 222 {ax - 40} 240 C{ax - 24} 250 {ax - 6} 220 {ax} 198Z', '#c8b6ff', 4,
                    ' fill-opacity="0.75"')
                + L(f'M{ax - 4} 180 C{ax - 22} 160 {ax - 40} 140 {ax - 54} 134', '#ffffff', 2.5)
                + sparkle(ax - 48, 150, 5) + sparkle(ax - 34, 226, 4))
    k = [1, 1, 0.88, 0.76][i]
    sq = lambda w: f'<g transform="translate({ax},0) scale({k},1) translate({-ax},0)">{w}</g>'
    return {'back': sq(wing()) + mirror(sq(wing()))}


@item('jetpack', 'back', 'Jetpack', '\U0001F680', 2, 1100)
def _(i):
    s = SH[i]
    gid = uid('g')
    def tank(x):
        return (P(f'M{x + 4} 252 Q{x + 14} 290 {x + 24} 252Z', '#ff8a1f', 3)
                + P(f'M{x + 9} 252 Q{x + 14} 274 {x + 19} 252Z', '#ffe27a', 0)
                + R(x, 118, 28, 128, 14, f'url(#{gid})') + R(x + 2, 236, 24, 16, 5, '#5b6472', 4)
                + P(f'M{x} 132 Q{x} 112 {x + 14} 112 Q{x + 28} 112 {x + 28} 132Z', '#e5484d', 5)
                + R(x, 140, 28, 7, 0, '#ffcc33', 3) + shine(x + 5, 150, 5, 50))
    return {'back': lingrad(gid, SILVER, vertical=False) + tank(46 + s) + tank(126 - s)
                    + R(70 + s, 176, 60 - 2 * s, 30, 8, '#79818d', 5),
            'body': L(f'M{80 + s} 152 L{84 + s} {STRAP_BOT[i] - 6}', '#3a3f4a', 9) + L(f'M{120 - s} 152 L{116 - s} {STRAP_BOT[i] - 6}', '#3a3f4a', 9)}


@item('cape_royal', 'back', 'Royal Cape', '\U0001F451', 3, 2000)
def _(i):
    s = SH[i]
    gid, gg = uid('g'), uid('g')
    ermine = ''.join(P(f'M{x} {y} l-2 4 2 3 2 -3z', K, 0) for x, y in
                     ((44 + s, 278), (64 + s, 282), (100, 280), (136 - s, 282), (156 - s, 278)))
    return {'back': lingrad(gid, [(0, '#8a3ae0'), (1, '#3d1475')]) + lingrad(gg, GOLD)
                    + P(f'M{58 + s} 148 L{142 - s} 148 L{176 - s} 292 L{24 + s} 292Z', '#fff6b0', 0, ' opacity="0.3"')
                    + P(f'M{62 + s} 152 L{138 - s} 152 L{170 - s} 288 L{30 + s} 288Z', f'url(#{gid})')
                    + P(f'M{34 + s} 270 L{166 - s} 270 L{170 - s} 288 L{30 + s} 288Z', '#ffffff', 4) + ermine
                    + L(f'M{64 + s} 156 L{36 + s} 268 M{136 - s} 156 L{164 - s} 268', f'url(#{gg})', 5)
                    + shine(130 - s, 162, 5, 96)
                    + sparkle(168 - s, 214, 7, '#fff6b0') + sparkle(30 + s, 186, 5, '#fff6b0'),
            'body': lingrad(gg + 'b', GOLD) + R(84, 144, 32, 14, 7, f'url(#{gg}b)', 4)
                    + gem(100, 151, 6, '#e5484d', 2.5)}


@item('wings_phoenix', 'back', 'Phoenix Wings', '\U0001F525', 3, 3000)
def _(i):
    s = SH[i]
    ax = 72 + s
    gid = uid('g')
    def wing():
        return (P(f'M{ax} 168 C{ax - 40} 100 {ax - 96} 112 {ax - 92} 150 C{ax - 104} 162 {ax - 88} 180 {ax - 72} 176 '
                  f'C{ax - 86} 196 {ax - 66} 210 {ax - 50} 200 C{ax - 54} 222 {ax - 26} 228 {ax} 204Z', '#ffb02e', 0, ' opacity="0.35"')
                + P(f'M{ax} 172 C{ax - 36} 112 {ax - 86} 122 {ax - 82} 154 C{ax - 92} 166 {ax - 78} 182 {ax - 64} 178 '
                    f'C{ax - 76} 196 {ax - 58} 206 {ax - 44} 198 C{ax - 46} 216 {ax - 22} 220 {ax} 202Z', f'url(#{gid})', 5)
                + P(f'M{ax - 4} 182 C{ax - 30} 150 {ax - 56} 146 {ax - 64} 160 C{ax - 50} 166 {ax - 40} 176 {ax - 30} 190Z', '#ffe27a', 0)
                + L(f'M{ax - 8} 186 C{ax - 30} 170 {ax - 50} 166 {ax - 70} 168', '#e0301e', 3)
                + sparkle(ax - 80, 132, 7, '#fff6b0') + sparkle(ax - 58, 214, 5, '#fff6b0'))
    k = [1, 1, 0.88, 0.76][i]
    sq = lambda w: f'<g transform="translate({ax},0) scale({k},1) translate({-ax},0)">{w}</g>'
    return {'back': lingrad(gid, FIRE) + sq(wing()) + mirror(sq(wing()))}


# ════════════════ NECK ════════════════

@item('tie_red', 'neck', 'Red Tie', '\U0001F454', 0, 60)
def _(i):
    return {'body': P('M93 148 L107 148 L104 158 L96 158Z', '#a31f26', 4)
                    + P('M96 158 L104 158 L110 196 L100 206 L90 196Z', '#e5484d', 4)
                    + L('M96 172 L106 166 M94 186 L108 178', '#a31f26', 3)}


@item('bowtie', 'neck', 'Bow Tie', '\U0001F380', 0, 80)
def _(i):
    return {'body': P('M100 154 L80 144 L80 164Z', '#1d1d24', 4) + P('M100 154 L120 144 L120 164Z', '#1d1d24', 4)
                    + R(94, 148, 12, 12, 4, '#2b2b33', 4)}


@item('bandana', 'neck', 'Neck Bandana', '\U0001F9E3', 0, 100)
def _(i):
    x, w = TORSO[i][0], TORSO[i][1]
    return {'body': P(f'M{x - 2} 148 L{x + w + 2} 148 L100 186Z', '#e5484d', 5)
                    + ''.join(C(xx, yy, 2.2, '#ffffff', 0) for xx, yy in ((92, 158), (108, 158), (100, 170), (84, 152), (116, 152)))}


@item('whistle', 'neck', 'Coach Whistle', '\U0001F4E3', 0, 120)
def _(i):
    return {'body': L('M84 150 Q100 192 116 150', '#2f6bff', 4)
                    + R(92, 184, 18, 11, 5, '#c9d0da', 4) + R(88, 186, 6, 7, 2, '#c9d0da', 3) + C(103, 189, 2, K, 0)}


@item('scarf_cozy', 'neck', 'Cozy Scarf', '\U0001F9E3', 0, 150)
def _(i):
    x, w = TORSO[i][0], TORSO[i][1]
    stripes = lambda yy: ''.join(R(xx, yy, 6, 20, 0, '#ffffff', 0) for xx in range(x, x + w + 6, 14))
    cid = uid('tc')
    return {'body': f'<clipPath id="{cid}"><rect x="{x - 6}" y="142" width="{w + 12}" height="20" rx="10"/></clipPath>'
                    + R(x - 6, 142, w + 12, 20, 10, '#2f6bff', 0)
                    + f'<g clip-path="url(#{cid})">{stripes(142)}</g>'
                    + R(x - 6, 142, w + 12, 20, 10, 'none')
                    + R(70, 152, 20, 54, 8, '#2f6bff') + R(70, 168, 20, 6, 0, '#ffffff', 0) + R(70, 186, 20, 6, 0, '#ffffff', 0)
                    + L('M72 206 v6 M80 206 v6 M88 206 v6', '#2f6bff', 3)}


@item('dogtags', 'neck', 'Dog Tags', '\U0001F3F7️', 1, 250)
def _(i):
    return {'body': L('M86 150 Q100 184 114 150', '#9aa3b0', 3)
                    + f'<g transform="rotate(-8 98 188)">' + R(90, 178, 16, 22, 5, '#c9d0da', 3.5) + '</g>'
                    + f'<g transform="rotate(10 106 190)">' + R(98, 180, 16, 22, 5, '#e3e8ef', 3.5)
                    + L('M102 188 h8 M102 193 h6', '#6b7482', 2) + '</g>'}


@item('neckphones', 'neck', 'Neck Phones', '\U0001F3A7', 1, 380)
def _(i):
    x, w = TORSO[i][0], TORSO[i][1]
    return {'body': L(f'M{x + 8} 158 Q100 186 {x + w - 8} 158', '#1d1d24', 9)
                    + R(x - 2, 146, 20, 26, 9, '#e5484d') + R(x + w - 18, 146, 20, 26, 9, '#e5484d')
                    + C(x + 8, 159, 4, '#ffffff', 0, ' opacity="0.5"') + C(x + w - 8, 159, 4, '#ffffff', 0, ' opacity="0.5"')}


@item('pearls', 'neck', 'Pearl Necklace', '\U0001F9AA', 1, 450)
def _(i):
    import math
    s = ''
    for k in range(11):
        t = k / 10
        xx = 82 + 36 * t
        yy = 152 + 22 * math.sin(math.pi * t)
        s += C(xx, yy, 4.2, '#fbf6ee', 2.5) + C(xx - 1.2, yy - 1.4, 1.2, '#ffffff', 0)
    return {'body': s}


@item('chain_gold', 'neck', 'Gold Chain', '⛓️', 2, 700)
def _(i):
    import math
    gid = uid('g')
    s = lingrad(gid, GOLD)
    for k in range(12):
        t = k / 11
        xx = 80 + 40 * t
        yy = 152 + 30 * math.sin(math.pi * t)
        s += E(xx, yy, 4.5, 3.2, f'url(#{gid})', 2.5)
    s += R(91, 182, 18, 18, 4, f'url(#{gid})', 3.5) + P('M96 186 h8 l-4 10z', '#c98a00', 0)
    s += sparkle(116, 194, 5, '#fff6b0')
    return {'body': s}


@item('amulet', 'neck', 'Mystic Amulet', '\U0001F52E', 2, 1000)
def _(i):
    gid = uid('g')
    return {'body': lingrad(gid, GOLD)
                    + L('M84 150 Q100 186 116 150', '#3a2a22', 4)
                    + C(100, 190, 17, '#b98cff', 0, ' opacity="0.35"')
                    + P('M100 174 L112 186 L100 206 L88 186Z', f'url(#{gid})', 4)
                    + gem(100, 188, 7.5, '#9b59ff', 2.5)
                    + sparkle(118, 176, 5) + sparkle(84, 202, 4)}


@item('medallion', 'neck', 'Hero Medallion', '\U0001F3C5', 2, 1300)
def _(i):
    gid = uid('g')
    return {'body': lingrad(gid, GOLD)
                    + P('M82 150 L96 184 L104 184 L118 150 L110 150 L100 174 L90 150Z', '#2f6bff', 3.5)
                    + C(100, 194, 16, f'url(#{gid})', 5)
                    + star(100, 194, 9, '#e5484d', 2.5)
                    + sparkle(120, 182, 6, '#fff6b0')}


@item('collar_diamond', 'neck', 'Diamond Collar', '\U0001F48D', 3, 2500)
def _(i):
    import math
    gid = uid('g')
    s = lingrad(gid, GOLD)
    s += L('M76 150 Q100 182 124 150', '#fff6b0', 14).replace('stroke="#fff6b0"', 'stroke="#fff6b0" opacity="0.35"')
    s += L('M76 150 Q100 182 124 150', f'url(#{gid})', 7)
    for k in range(7):
        t = (k + 0.5) / 7
        xx = 76 + 48 * t
        yy = 150 + 32 * t * (1 - t) * 2 * 0.98
        if k != 3:
            s += gem(xx, yy + 1, 4.2, '#e9fbff', 2)
    s += P('M100 172 L110 184 L100 204 L90 184Z', '#b9ecff', 4) + L('M90 184 H110 M100 172 L96 184 L100 204 L104 184Z', '#5fb7e6', 1.5)
    s += C(97, 182, 2, '#fff', 0)
    s += sparkle(118, 176, 7) + sparkle(80, 194, 5) + sparkle(112, 206, 4)
    return {'body': s}


# ─────────────────────────── output ───────────────────────────

def build():
    out = []
    for it in ITEMS:
        layers = {}
        for ti, t in enumerate(TIERS):
            for layer, inner in it['fn'](ti).items():
                layers[f'{it["id"]}/{t}/{layer}'] = wrap(inner)
        d = {k: v for k, v in it.items() if k != 'fn'}
        d['art'] = layers
        out.append(d)
    return out


if __name__ == '__main__':
    items = build()
    json.dump(items, open(sys.argv[1], 'w'), ensure_ascii=False)
    from collections import Counter
    print(len(items), Counter(i['slot'] for i in items))
