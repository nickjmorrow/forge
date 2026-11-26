#!/usr/bin/env python3
"""A library of figures (looping line drawings of movements) for guide steps.

Writes figures.json: {"slug": figure}, each in the shape `forge guide put` accepts as a step's "figure".
Points live in a 100 x 100 box, y downward. Review them with the UI test `aLibraryOfFiguresValidatesAndRenders`:

    python3 tools/figures/make_figures.py
    cd UI && FORGE_FIGURES_JSON=../tools/figures/figures.json FORGE_SNAPSHOT_DIR=/tmp/sheets swift test --filter aLibraryOfFigures
"""
import json
import math
import os

FIGS = {}
TAU = 2 * math.pi


def parts(*specs):
    out = []
    for spec in specs:
        kind, points, *tone = spec
        part = {"kind": kind, "points": points.split()}
        if tone:
            part["tone"] = tone[0]
        out.append(part)
    return out


def fig(name, part_list, frames, duration, easing="ease"):
    """frames: point dicts, or (points, back) pairs. Later frames keep only what moved from the first."""
    built = []
    first = None
    for frame in frames:
        points, back = frame if isinstance(frame, tuple) else (frame, None)
        points = {k: [round(v[0], 1), round(v[1], 1)] for k, v in points.items()}
        if first is None:
            first = points
            kept = points
        else:
            kept = {k: v for k, v in points.items() if first.get(k) != v}
        entry = {"points": kept}
        if back:
            entry["back"] = back
        built.append(entry)
    figure = {"duration": duration, "parts": part_list, "frames": built}
    if easing != "ease":
        figure["easing"] = easing
    FIGS[name] = figure


def sampled(fn, n):
    return [fn(i / n) for i in range(n)]


def polar(c, r, deg):
    """A point r from c; 0 degrees is straight down, 90 forward (right), 180 up."""
    a = math.radians(deg)
    return (c[0] + r * math.sin(a), c[1] + r * math.cos(a))


def add(p, dx, dy):
    return (p[0] + dx, p[1] + dy)


# ---- Side view, standing, facing right -------------------------------------------------------------------------------------

FLOOR = dict(g1=(8, 91.5), g2=(92, 91.5))
SIDE = dict(FLOOR, hd=(50, 14.5), sh=(50, 26), mid=(50, 38), hip=(50, 50), el=(51, 38), ha=(52, 50), kn=(50, 70), an=(50, 88), toe=(58, 89))
SIDE_PARTS = parts(("floor", "g1 g2"), ("line", "hip kn an toe"), ("curve", "hip mid sh"), ("head", "hd"), ("line", "sh el ha"))
SIDE_FAR_LEG = dict(kn2=(50, 70), an2=(50, 88), toe2=(58, 89))
SIDE_PARTS_2LEGS = parts(("floor", "g1 g2"), ("line", "hip kn2 an2 toe2", "dim"), ("line", "hip kn an toe"), ("curve", "hip mid sh"), ("head", "hd"),
                         ("line", "sh el ha"))


def side(**over):
    return dict(SIDE, **over)


fig("forward-back-bends", SIDE_PARTS, [
    side(),
    side(hip=(44, 50), mid=(57, 50), sh=(63, 64), hd=(61, 76), el=(69, 74), ha=(71, 86), kn=(47, 70)),
    side(),
    side(hip=(54, 50), mid=(52, 38), sh=(46, 27), hd=(41, 17), el=(44, 39), ha=(45, 51), kn=(52, 70)),
], 6)

fig("standing-forward-fold", SIDE_PARTS, [
    side(),
    side(hip=(42, 50), mid=(54, 55), sh=(60, 68), hd=(60, 80), el=(66, 78), ha=(68, 88), kn=(46, 70)),
], 4.5)


def arm_circle(t):
    deg = 360 * t
    return side(c=SIDE["sh"], r=(24, 24), ha=polar(SIDE["sh"], 24, deg), el=polar(SIDE["sh"], 12, deg))


fig("arm-circles", parts(("ring", "c r", "accent")) + SIDE_PARTS + parts(("dot", "ha", "accent")), sampled(arm_circle, 16), 3, "linear")


def shoulder_circle(t):
    a = TAU * t
    sh = (50 + 5.5 * math.cos(a), 30 + 5.5 * math.sin(a))
    return side(nk=(50, 26), c=(50, 30), r=(5.5, 5.5), sh=sh, el=add(sh, 1, 12), ha=add(sh, 2, 24))


fig("shoulder-circles", parts(("floor", "g1 g2"), ("line", "hip kn an toe"), ("curve", "hip mid nk"), ("head", "hd"), ("line", "sh el ha"),
                              ("ring", "c r", "accent"), ("dot", "sh", "accent")), sampled(shoulder_circle, 12), 2.4, "linear")

fig("pelvic-tilt", SIDE_PARTS + parts(("line", "pa pb", "accent")), [
    side(el=(42, 39), ha=(49, 48), hip=(48, 50), mid=(53, 39), pa=(43, 46), pb=(55, 54)),
    side(el=(42, 39), ha=(51, 48), hip=(52, 50), mid=(48, 39), pa=(45, 54), pb=(57, 46)),
], 3)

fig("high-knees", SIDE_PARTS_2LEGS, [
    side(**SIDE_FAR_LEG),
    side(**SIDE_FAR_LEG, kn=(63, 52), an=(62, 71), toe=(70, 72)),
    side(**SIDE_FAR_LEG),
    side(kn2=(63, 52), an2=(62, 71), toe2=(70, 72)),
], 3.2)

fig("butt-kicks", SIDE_PARTS_2LEGS, [
    side(**SIDE_FAR_LEG),
    side(**SIDE_FAR_LEG, kn=(51, 70), an=(38, 60), toe=(33, 65)),
    side(**SIDE_FAR_LEG),
    side(kn2=(51, 70), an2=(38, 60), toe2=(33, 65)),
], 3.2)


def band_arc(deg):
    return side(ha=polar(SIDE["sh"], 24, deg), el=polar(SIDE["sh"], 12, deg))


fig("band-dislocates", SIDE_PARTS + parts(("dot", "ha", "accent")),
    [band_arc(d) for d in (35, 83, 131, 180, 228, 276, 325, 276, 228, 180, 131, 83)], 5, "linear")


def front_leg_swing(t):
    deg = 10 + 35 * math.sin(TAU * t)
    a = math.radians(deg)
    an = polar(SIDE["hip"], 38, deg)
    return side(**SIDE_FAR_LEG, kn=polar(SIDE["hip"], 20, deg), an=an, toe=(an[0] + 8 * math.cos(a), an[1] - 8 * math.sin(a)))


fig("front-leg-swings", SIDE_PARTS_2LEGS, sampled(front_leg_swing, 12), 2.2, "linear")

COUNTER = parts(("floor", "c1 c2"))
fig("standing-lat-stretch", COUNTER + SIDE_PARTS, [
    side(c1=(74, 53), c2=(96, 53), an=(52, 88), toe=(60, 89), kn=(52, 70), hip=(52, 50), mid=(54, 38), sh=(56, 27), hd=(57, 15.5), el=(66, 40), ha=(76, 50)),
    side(c1=(74, 53), c2=(96, 53), an=(38, 88), toe=(46, 89), kn=(37, 70), hip=(34, 52), mid=(46, 56), sh=(58, 54), hd=(66, 60), el=(68, 52), ha=(78, 50)),
], 4)

fig("deep-squat", COUNTER + SIDE_PARTS, [
    side(c1=(72, 53), c2=(96, 53), an=(52, 88), toe=(60, 89), kn=(52, 70), hip=(52, 50), mid=(52, 38), sh=(52, 26), hd=(52, 14.5), el=(62, 40), ha=(73, 50)),
    side(c1=(72, 53), c2=(96, 53), an=(52, 88), toe=(60, 89), kn=(60, 64), hip=(40, 74), mid=(44, 62), sh=(50, 50), hd=(52, 38.5), el=(62, 52), ha=(73, 50)),
], 4)

fig("low-lunge", parts(("floor", "g1 g2"), ("line", "hip kn2 toe2"), ("line", "hip kn an toe"), ("curve", "hip mid sh"), ("head", "hd"), ("line", "sh el ha")), [
    dict(FLOOR, kn2=(31, 84), toe2=(12, 87), kn=(68, 66), an=(68, 88), toe=(76, 89), hip=(48, 60), mid=(49, 48), sh=(50, 36), hd=(50, 24.5), el=(58, 50), ha=(66, 62)),
    dict(FLOOR, kn2=(30, 86), toe2=(12, 87), kn=(72, 67), an=(68, 88), toe=(76, 89), hip=(51, 71), mid=(51, 58), sh=(51, 46), hd=(51, 34.5), el=(59, 58), ha=(70, 64)),
], 4)

fig("kneeling-quad-stretch", parts(("floor", "g1 g2"), ("line", "hip kn toe"), ("curve", "hip mid sh"), ("head", "hd"), ("line", "sh el ha")), [
    dict(FLOOR, kn=(52, 86), toe=(26, 88), hip=(52, 60), mid=(52, 48), sh=(52, 36), hd=(52, 24.5), el=(51, 48), ha=(50, 60)),
    dict(FLOOR, kn=(52, 86), toe=(26, 88), hip=(56, 61), mid=(54, 47), sh=(43, 40), hd=(35, 31), el=(40, 54), ha=(36, 69)),
], 4)

WALL = parts(("floor", "w1 w2"))
fig("calf-stretch", WALL + SIDE_PARTS_2LEGS, [
    dict(FLOOR, w1=(88, 12), w2=(88, 91.5), hip=(50, 52), mid=(54, 40), sh=(58, 29), hd=(61, 18), el=(70, 34), ha=(86, 32), kn=(40, 70), an=(30, 87), toe=(38, 89),
         kn2=(60, 70), an2=(62, 88), toe2=(70, 89)),
    dict(FLOOR, w1=(88, 12), w2=(88, 91.5), hip=(55, 53), mid=(60, 41), sh=(65, 31), hd=(69, 20.5), el=(76, 36), ha=(86, 32), kn=(43, 71), an=(30, 87), toe=(38, 89),
         kn2=(67, 71), an2=(62, 88), toe2=(70, 89)),
], 3.5)

# ---- Side view, on the floor -----------------------------------------------------------------------------------------------

LOW = dict(g1=(6, 86), g2=(94, 86))
FLOOR_PARTS = parts(("floor", "g1 g2"), ("line", "hip kn toe"), ("curve", "hip mid sh"), ("head", "hd"), ("line", "sh el ha"))

fig("cobra", FLOOR_PARTS, [
    dict(LOW, toe=(12, 81), kn=(32, 81), hip=(50, 81), mid=(62, 81), sh=(74, 79), hd=(84, 76), el=(65, 73), ha=(73, 82)),
    dict(LOW, toe=(12, 81), kn=(32, 81), hip=(50, 81), mid=(61, 75), sh=(66, 60), hd=(70, 48), el=(70, 71), ha=(73, 82)),
], 4.5)

QUAD = dict(LOW, toe=(16, 84), kn=(36, 83), hip=(36, 58), sh=(68, 58), el=(68.5, 70), ha=(69, 83))
fig("cat-camel", FLOOR_PARTS, [
    dict(QUAD, mid=(52, 47), hd=(77, 68)),
    dict(QUAD, mid=(52, 65), hd=(80, 48)),
], 4)

fig("thread-the-needle", parts(("floor", "g1 g2"), ("line", "sh ha2", "dim"), ("line", "hip kn toe"), ("curve", "hip mid sh"), ("head", "hd"), ("line", "sh el ha")), [
    dict(QUAD, mid=(52, 57), hd=(79, 58), ha2=(66, 83)),
    dict(QUAD, hip=(36, 56), mid=(50, 62), sh=(64, 74), hd=(74, 78), el=(77, 80), ha=(90, 83), ha2=(50, 82)),
], 4)

SUPINE = dict(LOW, hd=(14, 78.5), sh=(25, 81), mid=(38, 81), hip=(52, 81))
fig("glute-bridge", parts(("floor", "g1 g2"), ("line", "hip kn an toe"), ("curve", "hip mid sh"), ("head", "hd"), ("line", "sh ha")), [
    dict(SUPINE, kn=(67, 61), an=(75, 83), toe=(82, 83.5), ha=(47, 83)),
    dict(SUPINE, hip=(52, 65), mid=(39, 71), kn=(68, 59), an=(75, 83), toe=(82, 83.5), ha=(47, 83)),
], 3.5)

SUPINE_LEG_PARTS = parts(("floor", "g1 g2"), ("line", "hip an2 toe2", "dim"), ("line", "hip kn an toe"), ("curve", "hip mid sh"), ("head", "hd"), ("line", "sh el ha"))
fig("knee-to-chest", SUPINE_LEG_PARTS, [
    dict(SUPINE, an2=(87, 82), toe2=(89, 75), kn=(69, 81), an=(86, 81), toe=(88, 74), el=(36, 82), ha=(46, 82)),
    dict(SUPINE, an2=(87, 82), toe2=(89, 75), kn=(42, 61), an=(59, 57), toe=(65, 53), el=(35, 69), ha=(45, 61)),
], 4)


def raised_leg(deg):
    a = math.radians(deg)
    hip = SUPINE["hip"]
    an = (hip[0] + 36 * math.cos(a), hip[1] - 36 * math.sin(a))
    kn = (hip[0] + 18 * math.cos(a), hip[1] - 18 * math.sin(a))
    return dict(kn=kn, an=an, toe=(an[0] - 7 * math.sin(a), an[1] - 7 * math.cos(a)))


fig("supine-hamstring-stretch", SUPINE_LEG_PARTS + parts(("line", "an ha", "accent")), [
    dict(SUPINE, an2=(87, 82), toe2=(89, 75), el=(35, 74), ha=(45, 70), **raised_leg(28)),
    dict(SUPINE, an2=(87, 82), toe2=(89, 75), el=(34, 72), ha=(43, 66), **raised_leg(72)),
], 4)

fig("seated-chest-opener", parts(("floor", "g1 g2"), ("line", "hip kn an toe"), ("curve", "hip mid sh"), ("head", "hd"), ("line", "sh el ha")), [
    dict(LOW, hip=(50, 81), kn=(66, 63), an=(76, 83), toe=(83, 84), mid=(47, 69), sh=(45, 57), hd=(45, 45.5), el=(37, 69), ha=(30, 83)),
    dict(LOW, hip=(55, 81), kn=(70, 64), an=(76, 83), toe=(83, 84), mid=(52, 67), sh=(43, 59), hd=(36, 50), el=(35, 71), ha=(28, 83)),
], 4)

# ---- Front view, standing --------------------------------------------------------------------------------------------------

FRONT = dict(FLOOR, hd=(50, 15), nk=(50, 28), shl=(38, 28), shr=(62, 28), ell=(35, 40), hal=(34, 52), elr=(65, 40), har=(66, 52),
             hc=(50, 52), mc=(50, 40), hl=(45, 52), hr=(55, 52), knl=(44, 71), fl=(43, 89), knr=(56, 71), fr=(57, 89))
FRONT_PARTS = parts(("floor", "g1 g2"), ("line", "hl knl fl"), ("line", "hr knr fr"), ("line", "hl hr"), ("curve", "hc mc nk"), ("line", "shl shr"),
                    ("head", "hd"), ("line", "shl ell hal"), ("line", "shr elr har"))
ARM_L, ARM_R = 7, 8
HANDS_ON_HIPS = dict(ell=(30, 41), hal=(43, 51), elr=(70, 41), har=(57, 51))


def front(**over):
    return dict(FRONT, **over)


def elbow_circle(t):
    a = TAU * t
    return front(ell=(22, 28), elr=(78, 28), hal=(22 + 13 * math.cos(a), 28 + 13 * math.sin(a)), har=(78 - 13 * math.cos(a), 28 + 13 * math.sin(a)),
                 r=(13, 13))


fig("elbow-circles", parts(("ring", "ell r", "accent"), ("ring", "elr r", "accent")) + FRONT_PARTS + parts(("dot", "hal", "accent"), ("dot", "har", "accent")),
    sampled(elbow_circle, 12), 2.6, "linear")

fig("scarecrows", FRONT_PARTS, [
    front(ell=(22, 28), elr=(78, 28), hal=(22, 11), har=(78, 11)),
    front(ell=(22, 28), elr=(78, 28), hal=(22, 45), har=(78, 45)),
], 3)


def neck_circle(t):
    a = TAU * t
    return front(hd=(50 + 5.5 * math.cos(a), 15 + 2.5 * math.sin(a)), c=(50, 15), r=(12, 5.5))


fig("neck-circles", parts(("ring", "c r", "accent"), ("floor", "g1 g2"), ("line", "hl knl fl"), ("line", "hr knr fr"), ("line", "hl hr"), ("curve", "hc mc nk"),
                          ("line", "shl shr"), ("line", "nk hd"), ("head", "hd"), ("line", "shl ell hal"), ("line", "shr elr har")),
    sampled(neck_circle, 12), 3, "linear")

TWIST_PARTS = parts(("floor", "g1 g2"), ("line", "hl knl fl"), ("line", "hr knr fr"), ("line", "hl hr"), ("line", "hc nk"), ("line", "shl shr"),
                    ("head", "hd"), ("dot", "nose", "accent"), ("line", "shl ell hal"), ("line", "shr elr har"))


def twist(t, elbow, hand, amplitude):
    """Turning about the spine: offsets from it shrink with the turn; the arm that swings behind is drawn dim."""
    th = amplitude * math.sin(TAU * t)
    c, s = math.cos(th), math.sin(th)

    def at(off, y):
        return (50 + off * c, y + off * s * 0.07)

    points = front(shl=at(-12, 28), shr=at(12, 28), ell=at(-elbow[0], elbow[1]), elr=at(elbow[0], elbow[1]), hal=at(-hand[0], hand[1]), har=at(hand[0], hand[1]),
                   nose=(50 + 4.5 * s, 15.5))
    back = [8] if s > 0.05 else [9] if s < -0.05 else None
    return (points, back)


fig("torso-twists", TWIST_PARTS, sampled(lambda t: twist(t, (24, 28), (37, 28), 1.0), 16), 4, "linear")
fig("standing-spinal-twist", TWIST_PARTS, sampled(lambda t: twist(t, (20, 38), (27, 47), 1.1), 16), 6, "linear")


def lean(k, overhead=False):
    """Bending sideways from the waist: k is -1 (to the viewer's left) to 1."""
    phi = 0.45 * k
    nk = (50 + 13 * k, 28 + 3 * abs(k))
    shl = (nk[0] - 12 * math.cos(phi), nk[1] - 12 * math.sin(phi))
    shr = (nk[0] + 12 * math.cos(phi), nk[1] + 12 * math.sin(phi))
    points = front(nk=nk, mc=(50 + 4 * k, 40), shl=shl, shr=shr, hd=(nk[0] + 13 * math.sin(phi), nk[1] - 13 * math.cos(phi)),
                   ell=add(shl, -3, 12), hal=add(shl, -4, 24), elr=add(shr, 3, 12), har=add(shr, 4, 24))
    if overhead and k:
        a = phi + (0.5 if k > 0 else -0.5)
        d = (math.sin(a), -math.cos(a))
        sh, el, ha = (shl, "ell", "hal") if k > 0 else (shr, "elr", "har")
        points[el] = (sh[0] + 12 * d[0], sh[1] + 12 * d[1])
        points[ha] = (sh[0] + 24 * d[0], sh[1] + 24 * d[1])
    return points


fig("side-bends", FRONT_PARTS, [lean(0), lean(-1), lean(0), lean(1)], 5)
fig("standing-side-bend", FRONT_PARTS, [lean(0), lean(-1, True), lean(0), lean(1, True)], 6)


def waist_circle(t):
    a = TAU * t
    hc = (50 + 7 * math.cos(a), 52 + 2 * math.sin(a))
    hl, hr = add(hc, -5, 0), add(hc, 5, 0)
    return front(hc=hc, hl=hl, hr=hr, mc=(50 + 3.5 * math.cos(a), 40), knl=((hl[0] + 43) / 2, 71), knr=((hr[0] + 57) / 2, 71),
                 ell=(30 + 3 * math.cos(a), 41), hal=add(hl, -2, -1), elr=(70 + 3 * math.cos(a), 41), har=add(hr, 2, -1), c=(50, 52), r=(14, 4.5))


fig("hip-circles", parts(("ring", "c r", "accent")) + FRONT_PARTS, sampled(waist_circle, 12), 3, "linear")


def thigh_circle(t):
    a = TAU * t
    kn = (65 + 6 * math.cos(a), 60 + 5 * math.sin(a))
    return front(**HANDS_ON_HIPS, knr=kn, fr=add(kn, -2, 17), c=(65, 60), r=(6, 5))


fig("knee-circles", FRONT_PARTS + parts(("ring", "c r", "accent"), ("dot", "knr", "accent")), sampled(thigh_circle, 12), 2.8, "linear")


def side_leg_swing(t):
    deg = 12 + 28 * math.sin(TAU * t)
    return front(**HANDS_ON_HIPS, knr=polar(FRONT["hr"], 19, deg), fr=polar(FRONT["hr"], 37, deg))


fig("side-leg-swings", FRONT_PARTS, sampled(side_leg_swing, 12), 2.2, "linear")

fig("wall-slides", FRONT_PARTS, [
    front(ell=(27, 38), hal=(25, 20), elr=(73, 38), har=(75, 20)),
    front(ell=(27, 18), hal=(22, 3), elr=(73, 18), har=(78, 3)),
], 3.5)

fig("overhead-triceps-stretch", FRONT_PARTS, [
    front(),
    (front(elr=(58, 9), har=(50, 27), ell=(40, 41), hal=(49, 39)), [ARM_L]),
], 4)

fig("seated-90-90", parts(("floor", "g1 g2"), ("line", "hl knl fl", "dim"), ("line", "hl hr"), ("curve", "hc mc nk"), ("line", "shl shr"), ("head", "hd"),
                          ("line", "hr knr fr"), ("line", "shl hal"), ("line", "shr har")), [
    dict(g1=(8, 89), g2=(92, 89), hc=(50, 75), hl=(45, 75), hr=(55, 75), knl=(26, 80), fl=(20, 72), knr=(76, 80), fr=(50, 86),
         mc=(50, 62), nk=(50, 49), shl=(38, 49), shr=(62, 49), hd=(50, 36), hal=(32, 76), har=(68, 70)),
    dict(g1=(8, 89), g2=(92, 89), hc=(50, 75), hl=(45, 75), hr=(55, 75), knl=(26, 80), fl=(20, 72), knr=(76, 80), fr=(50, 86),
         mc=(54, 64), nk=(60, 55), shl=(49, 52), shr=(71, 58), hd=(65, 43), hal=(40, 78), har=(80, 72)),
], 4)

# ---- Seen from above, lying down (head at the top) -------------------------------------------------------------------------

ABOVE_PARTS = parts(("line", "hl knl fl"), ("line", "hr knr fr"), ("line", "hl hr"), ("line", "hc nk"), ("line", "shl shr"), ("head", "hd"),
                    ("dot", "nose", "accent"), ("line", "shl ell hal"), ("line", "shr elr har"))
ABOVE = dict(hd=(50, 15), nose=(50, 15), nk=(50, 28), shl=(38, 28), shr=(62, 28), hc=(50, 54), hl=(45, 54), hr=(55, 54),
             knl=(46, 72), fl=(46, 90), knr=(54, 72), fr=(54, 90))

fig("prone-pec-stretch", ABOVE_PARTS, [
    dict(ABOVE, ell=(25, 28), hal=(12, 28), elr=(71, 36), har=(63, 43)),
    dict(ABOVE, ell=(25, 28), hal=(12, 28), elr=(63, 31), har=(60, 41), shr=(56, 27), nk=(48, 28), hd=(47, 15), nose=(51.5, 15), hr=(54, 54)),
], 4)

fig("supine-spinal-twist", ABOVE_PARTS, [
    dict(ABOVE, ell=(25, 28), hal=(12, 28), elr=(75, 28), har=(88, 28), knr=(56, 61), fr=(56, 67)),
    dict(ABOVE, ell=(25, 28), hal=(12, 28), elr=(75, 28), har=(88, 28), knr=(31, 62), fr=(36, 80), hr=(53, 52), nose=(54.5, 15)),
], 4.5)

fig("frog-stretch", parts(("line", "hl knl fl"), ("line", "hr knr fr"), ("line", "hl hr"), ("line", "hc nk"), ("line", "shl shr"), ("head", "hd"),
                          ("line", "shl ell hal"), ("line", "shr elr har")), [
    dict(hd=(50, 16), nk=(50, 29), shl=(40, 29), shr=(60, 29), ell=(36, 34), hal=(36, 14), elr=(64, 34), har=(64, 14),
         hc=(50, 56), hl=(45, 56), hr=(55, 56), knl=(22, 58), fl=(24, 82), knr=(78, 58), fr=(76, 82)),
    dict(hd=(50, 23), nk=(50, 35), shl=(40, 35), shr=(60, 35), ell=(36, 34), hal=(36, 14), elr=(64, 34), har=(64, 14),
         hc=(50, 64), hl=(45, 64), hr=(55, 64), knl=(22, 58), fl=(24, 82), knr=(78, 58), fr=(76, 82)),
], 4)

# ---- Close-ups of one joint ------------------------------------------------------------------------------------------------

fig("finger-flexion", parts(("line", "th0 th1 th2", "dim"), ("line", "fa wr kn"), ("line", "kn pip tip")), [
    dict(fa=(8, 62), wr=(40, 56), kn=(58, 52), pip=(73, 50), tip=(87, 49), th0=(44, 57), th1=(52, 64), th2=(62, 66)),
    dict(fa=(8, 62), wr=(40, 56), kn=(58, 52), pip=(67, 64), tip=(54, 64), th0=(44, 57), th1=(52, 64), th2=(60, 70)),
], 2.4)


def wrist_circle(t):
    a = TAU * t
    return dict(fa=(8, 60), wr=(46, 56), tip=(72 + 5 * math.cos(a), 56 + 11 * math.sin(a)), c=(72, 56), r=(5, 11))


fig("wrist-circles", parts(("ring", "c r", "accent"), ("line", "fa wr"), ("line", "wr tip"), ("dot", "tip", "accent")), sampled(wrist_circle, 12), 2.6, "linear")


def ankle_circle(t):
    a = TAU * t
    return dict(top=(40, 6), an=(40, 58), heel=(35, 65), toe=(70 + 5 * math.cos(a), 64 + 10 * math.sin(a)), c=(70, 64), r=(5, 10))


fig("ankle-circles", parts(("ring", "c r", "accent"), ("line", "top an"), ("line", "an heel"), ("line", "an toe"), ("dot", "toe", "accent")),
    sampled(ankle_circle, 12), 2.6, "linear")


def ankle_tilt(th):
    c, s = math.cos(th), math.sin(th)
    return dict(g1=(20, 85), g2=(80, 85), top=(50, 6), an=(50, 60), fc=(50, 74), fa=(50 - 16 * c, 74 - 16 * s), fb=(50 + 16 * c, 74 + 16 * s))


fig("ankle-tilts", parts(("floor", "g1 g2"), ("line", "top an fc"), ("line", "fa fb")), [ankle_tilt(-0.38), ankle_tilt(0.38)], 2.4)

fig("toe-flexion", parts(("line", "top an"), ("line", "an heel ball"), ("line", "an ball"), ("line", "ball tip")), [
    dict(top=(34, 6), an=(34, 60), heel=(26, 80), ball=(64, 82), tip=(79, 69)),
    dict(top=(34, 6), an=(34, 60), heel=(26, 80), ball=(64, 82), tip=(77, 93)),
], 2.4)

if __name__ == "__main__":
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "figures.json")
    with open(out, "w") as f:
        json.dump(FIGS, f, separators=(",", ":"), sort_keys=True)
    print(f"{len(FIGS)} figures, {os.path.getsize(out)} bytes -> {out}")
