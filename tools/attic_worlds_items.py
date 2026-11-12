"""阁楼外面（六个口袋世界）的 Lux3D 资产清单与提示词。

按「玩家看到的多少」和「是否独立摆件」挑选。
⚠ 只做**独立摆件**：地形、墙、栈桥、隔墙保持程序化（要精确对齐/可行走）。
"""

# (目录名, faceCount, 高度米, 提示词)
ITEMS = [
    # ── 雪夜：松林 + 路灯，一进门就是主体 ────────────────────────────
    ("pine-tree", 16000, 2.6,
     "A tall snow-covered pine tree, layered dark green needles with heavy white snow, "
     "slightly irregular natural silhouette, realistic PBR materials, single tree"),
    ("snow-lantern", 10000, 1.5,
     "An old iron street lantern on a slender post, warm amber glow inside frosted glass, "
     "rustic snow-town street furniture, realistic PBR materials"),
    ("snow-sled", 10000, 0.5,
     "A small wooden sled with curved steel runners and rope pull, weathered planks, "
     "patches of snow on top, realistic PBR materials"),
    ("snow-hearth", 14000, 1.1,
     "A rustic stone outdoor hearth with a small iron grate and stacked firewood, "
     "soot-stained stones, realistic PBR materials"),
    ("wooden-sign", 10000, 1.2,
     "A weathered wooden directional signpost with two blank arrow boards on a stout post, "
     "rough sawn timber, realistic PBR materials"),

    # ── 云海：望远镜 + 飞艇 + 信标 ──────────────────────────────────
    ("telescope", 12000, 1.0,
     "An antique brass refracting telescope on a wooden tripod, weathered patina, "
     "pointed slightly upward, realistic PBR materials"),
    ("airship", 20000, 3.0,
     "A small vintage airship with a rounded canvas envelope, wooden gondola and a rear propeller, "
     "weathered brass fittings, realistic PBR materials"),
    ("cloud-beacon", 12000, 2.0,
     "A tall slender lighthouse beacon tower of pale stone with a glowing brass lamp room on top, "
     "wind-worn surface, realistic PBR materials"),
    ("cloud-wincht", 12000, 1.2,
     "An old wooden winch with a rope drum and iron crank handle on a timber frame, "
     "weathered and slightly rusted, realistic PBR materials"),
    ("wind-organ", 14000, 1.6,
     "A whimsical wind organ made of vertical bamboo pipes of varying lengths on a wooden frame, "
     "warm aged wood, realistic PBR materials"),

    # ── 萤火：护林灯 + 水车 + 木鼓 + 蘑菇 ──────────────────────────
    ("ranger-lamp", 10000, 1.1,
     "A small forest ranger's hand lantern hanging from a short hook post, warm glow, "
     "aged metal and wood, realistic PBR materials"),
    ("waterwheel", 18000, 2.2,
     "A rustic wooden waterwheel with paddles and a stone axle mount, moss on the spokes, "
     "weathered timber, realistic PBR materials"),
    ("wood-drum", 10000, 0.8,
     "A hollow log drum carved from a single tree trunk with a slit opening, "
     "dark aged wood with grain, realistic PBR materials"),
    ("glow-mushroom", 10000, 0.6,
     "A cluster of tall bioluminescent mushrooms with pale teal glowing caps and slender stems, "
     "fantasy forest floor growth, realistic PBR materials"),

    # ── 雨巷：灯笼 + 油纸伞 + 石猫 + 纸船 ──────────────────────────
    ("alley-lantern", 10000, 0.7,
     "A traditional red paper lantern with bamboo ribs and a hanging string, "
     "soft warm glow, slightly weathered, realistic PBR materials"),
    ("paper-umbrella", 12000, 1.0,
     "An open oil-paper umbrella with bamboo ribs and a wooden handle, muted indigo canopy, "
     "rain beads on the surface, realistic PBR materials"),
    ("stone-cat", 10000, 0.5,
     "A small carved stone cat figurine sitting upright, weathered grey granite, "
     "simple stylized features, realistic PBR materials"),
    ("paper-boat", 10000, 0.25,
     "A small folded paper boat made of cream paper, crisp folds, slightly damp look, "
     "realistic paper material"),

    # ── 镜界 / 镜牢：棱镜之心 + 镜塔 ───────────────────────────────
    ("prism-heart", 12000, 0.45,
     "A floating faceted crystal prism shaped like a heart, pale icy blue with sharp cut facets, "
     "subtle inner glow, realistic glass-like PBR materials"),
    ("mirror-tower", 16000, 1.8,
     "A slender hexagonal tower of stacked mirrored panels with a dark metal frame, "
     "polished reflective surfaces, realistic PBR materials"),
]
