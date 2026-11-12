"""阁楼线「还不够」的第二批资产清单。

挑选标准：**玩家视线停留最久、当前仍为程序化几何**的物件。
（家具与六世界摆件已在第一批做完）
"""

# (目录名, faceCount, 目标高度米, 提示词)
ITEMS = [
    # ── 阁楼：四扇门是玩家每次都要看的，现在是一块平板 ────────────────
    # 门本身做成"老木门"，四扇共用同一个模型（颜色靠材质发光嵌板区分，那个保留）
    ("wooden-door", 16000, 2.05,
     "An old solid wooden interior door with recessed panels, aged oak, brass handle, "
     "simple carved frame, slightly weathered, realistic PBR materials, closed"),
    ("door-frame", 12000, 2.20,
     "A tall wooden door frame surround with a simple moulded architrave, dark stained oak, "
     "slightly worn edges, realistic PBR materials"),

    # ── 阁楼：镜界回廊的镜框 ─────────────────────────────────────────
    ("mirror-frame", 14000, 1.90,
     "An ornate but restrained standing mirror frame in dark carved wood with a subtle "
     "brass inlay border, empty frame without glass, realistic PBR materials"),

    # ── 阁楼：四件信物（雪夜/云海/萤火/雨巷带回来的纪念）──────────────
    ("keepsake-snow", 10000, 0.20,
     "A tiny glass snow globe with a miniature snowy pine inside, worn brass base, "
     "realistic PBR materials"),
    ("keepsake-cloud", 10000, 0.18,
     "A small round frosted glass pebble with soft white cloud-like wisps trapped inside, "
     "polished smooth surface, realistic PBR materials"),
    ("keepsake-firefly", 10000, 0.20,
     "A tiny glass vial sealed with a cork, holding a faint amber glowing light inside, "
     "weathered brass cap, realistic PBR materials"),
    ("keepsake-alley", 10000, 0.18,
     "A small old brass water-clock token shaped like a tiny roof tile with a carved "
     "raindrop motif, patina surface, realistic PBR materials"),

    # ── 阁楼：墙面上的黄铜天气旋钮 ───────────────────────────────────
    ("weather-dial", 12000, 0.40,
     "An antique round brass wall-mounted weather dial with an engraved face and a single "
     "pointing needle, aged patina, realistic PBR materials"),

    # ── 阁楼：窗边的茶叶罐与小碟（茶席细节）──────────────────────────
    ("tea-canister", 10000, 0.14,
     "A small round tin tea canister with a fitted lid and a paper label, aged brass finish, "
     "subtle dents, realistic PBR materials"),
    ("tea-saucer", 10000, 0.03,
     "A small shallow ceramic saucer, celadon green glaze, thin rim, realistic PBR materials"),

    # ── 云海：云团（栈桥两侧的主体填充）──────────────────────────────
    ("cloud-cluster", 14000, 2.2,
     "A soft puffy cumulus cloud cluster, voluminous and rounded, bright white with faint "
     "grey underside, realistic volumetric-looking surface, isolated cloud"),
    # ── 云海：望远镜已有，补一个观星用的星图桌 ───────────────────────
    ("star-chart-table", 14000, 0.85,
     "A small round wooden observation table with an unrolled star chart pinned on top, "
     "brass corner weights, realistic PBR materials"),

    # ── 雪夜：雪堆（现在是压扁的球）──────────────────────────────────
    ("snow-drift", 12000, 0.7,
     "An irregular wind-sculpted snow drift mound, smooth rounded ridges, clean white snow "
     "surface with subtle sparkle, realistic PBR materials"),
    # ── 雪夜：结冰的湖面边缘 / 冰柱 ──────────────────────────────────
    ("ice-shard", 10000, 0.9,
     "A cluster of translucent pale blue ice shards jutting from the ground, sharp facets, "
     "realistic glassy PBR materials"),

    # ── 萤火：火塘（保留发光火焰，外壳换模型）────────────────────────
    ("stone-firepit", 14000, 0.55,
     "A ring of rough field stones forming a low campfire pit, soot-blackened inner stones, "
     "realistic PBR materials, no fire"),
    # ── 萤火：森林地面（现在是纯色地面）──────────────────────────────
    ("forest-log", 12000, 0.5,
     "A fallen moss-covered tree log with bark texture and broken branch stubs, "
     "realistic PBR materials"),

    # ── 雨巷：巷子尽头的木门（原来是一块平板）────────────────────────
    ("alley-end-door", 16000, 2.40,
     "A tall narrow old wooden door set in a stone doorway, weathered planks, iron hinges, "
     "faded dark paint, realistic PBR materials, closed"),
    # ── 雨巷：墙上的水管 ─────────────────────────────────────────────
    ("wall-pipe", 10000, 2.4,
     "A vertical rusted iron drainpipe with mounting brackets and a curved elbow at the "
     "bottom, weathered metal, realistic PBR materials"),

    # ── 镜界：镜面庭院里的地面镶边 ───────────────────────────────────
    ("mirror-plinth", 12000, 0.35,
     "A low hexagonal stone plinth with a polished reflective top surface and simple carved "
     "edges, pale grey stone, realistic PBR materials"),
]
