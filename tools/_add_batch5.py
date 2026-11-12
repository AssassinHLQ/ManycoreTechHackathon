# -*- coding: utf-8 -*-
"""第五批：18 个资产（互动机器 6 + 生态装饰 9 + 大型地貌 3）。

用户 2026-11-12：「a」→ 选「再用 ~250 credits 做第五批」。

余额 567，红线 300 → 可用 267。
18 x 13 = 234 credits，完成余额约 333（留 33 缓冲，不赌到 300 边线）。
"""
import io

P = r"tools\gen_props.py"
s = io.open(P, encoding="utf-8").read()
o = s

TAIL = "no ground plane, no pedestal, no base, no text, no backdrop"

INTERACTIVE = [
    ("med-station", 26000,
     "field medical station, upright cabinet with a cross panel, two small "
     "drawers and a rolled stretcher leaning beside it"),
    ("oxygen-generator", 26000,
     "oxygen generator unit, ribbed drum with intake vents, pressure gauge and "
     "a hose coiled on top"),
    ("ore-crusher", 28000,
     "ore crusher machine, heavy hopper feeding two toothed rollers on a "
     "bolted steel frame with an output chute"),
    ("holo-terminal", 26000,
     "hologram terminal, angled plinth projecting a floating stack of thin "
     "glowing rings above a small screen"),
    ("wind-turbine", 24000,
     "small wind turbine, three-bladed rotor on a lattice tower with a guy "
     "wire and a control box at the base"),
    ("landing-beacon", 26000,
     "landing beacon pylon, squat tower with four outward floodlights and a "
     "flat painted top plate"),
]

DECOR = [
    ("crystal-vein", 20000,
     "crystal vein outcrop, a jagged seam of translucent shards splitting a "
     "low rock shelf"),
    ("frozen-pond", 20000,
     "small frozen pond, cracked ice sheet in a shallow rock basin with white "
     "frost rims"),
    ("sand-ripple", 18000,
     "wind carved sand ripples, parallel wave ridges across a low dune surface"),
    ("alien-mound", 22000,
     "alien termite mound, tall twisted spire of packed earth with ridges and "
     "small dark openings"),
    ("lava-drip", 20000,
     "cooled lava drips, frozen black tendrils hanging from a broken rock lip "
     "with glassy tips"),
    ("coral-stack", 20000,
     "coral stack formation, branching pale coral growths clustered into a low "
     "column"),
    ("mushroom-ring", 18000,
     "fairy mushroom ring, a circle of small glowing mushrooms on bare ground"),
    ("glass-crater", 22000,
     "vitrified crater, small impact bowl with slick fused glass lining and "
     "radiating cracks"),
    ("bone-yard", 22000,
     "bone yard scatter, tangled ribs and long limb bones half buried in dust"),
]

LANDFORM = [
    ("lf-mesa-spire", 26000,
     "mesa spire, tall isolated rock tower with a flat top and vertical eroded "
     "fluting along its sides"),
    ("lf-dune-sea", 26000,
     "dune sea, long parallel sand ridges with sharp crests stretching across "
     "the ground"),
    ("lf-crystal-forest", 26000,
     "crystal forest, a dense stand of tall angular translucent crystal columns "
     "of mixed heights"),
]


def fmt(items):
    return "\n".join('    ("%s", %d,\n     "%s, %s"),' % (pid, f, d, TAIL)
                     for pid, f, d in items)


idx = s.rfind("PROPS += [")
assert idx > 0, "no anchor"
block = ("\n# \u2500\u2500 \u7b2c\u4e94\u6279\uff1a\u4e92\u52a8\u673a\u5668 + \u751f\u6001\u88c5\u9970 + \u5927\u578b\u5730\u8c8c "
         "(18 \u4e2a) \u2500\u2500\n"
         "PROPS += [\n" + fmt(INTERACTIVE) + "\n]\n\n"
         "PROPS += [\n" + fmt(DECOR) + "\n]\n\n"
         "PROPS += [\n" + fmt(LANDFORM) + "\n]\n")
s = s[:idx] + block + s[idx:]

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("added %d assets (interactive %d / decor %d / landform %d)" % (
    len(INTERACTIVE) + len(DECOR) + len(LANDFORM),
    len(INTERACTIVE), len(DECOR), len(LANDFORM)))
