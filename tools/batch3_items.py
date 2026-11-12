"""第三批：太空站内部 + 其他剩余高曝光程序化物件。

station.gd 有 355 个程序化图元，是剩余最大的程序化模块。
优先做**玩家会走近、会看**的可交互家具，不做壳体与结构件（要精确对齐）。
"""

# (目录名, faceCount, 目标高度米, 提示词)
ITEMS = [
    # ── 太空站：座椅（多处重复，收益最大）──────────────────────────
    ("station-seat", 14000, 0.95,
     "A modern space station passenger seat, molded shell with pale grey padding, "
     "brushed metal frame and armrests, subtle wear, realistic PBR materials"),
    # ── 太空站：控制台 ─────────────────────────────────────────────
    ("station-console", 16000, 1.10,
     "A sci-fi operations console desk with an angled dark glass display panel and "
     "brushed alloy body, small physical buttons along the front edge, realistic PBR materials"),
    # ── 太空站：花箱（走廊绿植）────────────────────────────────────
    ("station-planter", 12000, 1.20,
     "A cylindrical brushed-metal planter box with a small leafy green shrub growing out of it, "
     "industrial style, realistic PBR materials"),
    # ── 太空站：公共望远镜（观景厅）────────────────────────────────
    ("station-viewer", 14000, 1.55,
     "A coin-operated style observation telescope on a sturdy metal pedestal, "
     "long tapered tube, worn chrome fittings, realistic PBR materials"),
    # ── 太空站：舱门 ───────────────────────────────────────────────
    ("station-hatch", 16000, 2.10,
     "A heavy round-cornered spacecraft pressure hatch door with a small porthole window, "
     "pale alloy panels, bolted frame, warning stripe accents, realistic PBR materials"),
    # ── 太空站：走廊长凳 / 候车座 ──────────────────────────────────
    ("station-bench", 12000, 0.55,
     "A simple modern waiting bench with a slim cushioned seat on a metal frame, "
     "pale grey upholstery, rounded edges, realistic PBR materials"),
    # ── 太空站：墙面信息屏 ─────────────────────────────────────────
    ("wall-screen", 10000, 0.75,
     "A thin wall-mounted information display panel with a dark glass face and a slim "
     "alloy bezel, no content, realistic PBR materials"),
    # ── 太空站：货运箱（走廊堆放）──────────────────────────────────
    ("cargo-crate", 12000, 0.85,
     "An industrial cargo crate with reinforced corners, latches and a stencilled label, "
     "scuffed pale alloy, realistic PBR materials"),

    # ── 地下 / 洞穴：灯与支架（洞穴探索用）────────────────────────
    ("cave-lamp", 12000, 1.60,
     "A rugged portable work lamp on a folding tripod stand, square floodlight head, "
     "scuffed yellow-grey metal, realistic PBR materials"),
    ("cave-strut", 12000, 2.20,
     "A rusty steel roof support strut with bolted base plates, worn industrial prop, "
     "realistic PBR materials"),
    ("cave-crate", 10000, 0.60,
     "An old wooden mining crate with rope handles and iron corner brackets, "
     "dusty and weathered, realistic PBR materials"),

    # ── 通用：行星表面的补给箱 / 天线（多星球复用）────────────────
    ("supply-tank", 14000, 1.40,
     "A small cylindrical fuel supply tank on stubby legs with a valve wheel on top, "
     "weathered white paint and rust streaks, realistic PBR materials"),
    ("comm-antenna", 16000, 3.20,
     "A small dish communication antenna on a lattice mast with a ground base, "
     "pale grey dish and rusty steel frame, realistic PBR materials"),
    ("beacon-post", 12000, 1.90,
     "A slim beacon post with a glowing amber lamp housing at the top and a small "
     "solar panel, weathered alloy, realistic PBR materials"),
]
