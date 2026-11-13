# -*- coding: utf-8 -*-
"""把飞船尺寸对齐到星球的 ×5 世界尺度。

根因（2026-11-13，用户「船就是变小了啊，小了大概三倍」）：
  a0fde88 把星球上的一切按 prop_scale = 5 放大：
    建筑、道具、洞穴、**玩家胶囊 1.65 m -> 8.25 m**
  但飞船的 SHIP_MODEL_TARGET_LENGTH 一直是 14.0（世界米），没有乘 5。
  于是 14 m 的船旁边站着一个 8.25 m 高的人 —— 船看起来就缩水了约 3~5 倍。

按真实比例校验：
  F-16 机长 15 m，飞行员 1.8 m，比例 8.3。
  现在玩家 8.25 m，要保持同样比例，船应为 8.25 * 8.3 ≈ 68 m。
  取 70 m（正好等于 14 x 5，与 prop_scale 一致）。

连带改动（都由 ship_model_* 推导，会自动跟着走）：
  · 碰撞盒、座舱相机、着陆高度 —— 见 _ready / _build_external_model
  · SHIP_MODEL_GROUND_SINK 2.3 -> 11.5（下压量按同倍率）
  · 喷口坐标 EXHAUST_NOZZLES 是在**14 m 机长**下实测的，改为按
    length/14.0 的比例实时缩放 —— 以后改 TARGET_LENGTH 不会再对不齐
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

P = "scripts/ship.gd"
s = io.open(P, encoding="utf-8").read()

REPLACES = [
    # 1) 机长 14 -> 70（对齐 prop_scale x5）
    ("const SHIP_MODEL_TARGET_LENGTH := 14.0",
     "const SHIP_MODEL_TARGET_LENGTH := 70.0"),
    # 2) 落地下压量同比
    ("const SHIP_MODEL_GROUND_SINK := 2.3",
     "const SHIP_MODEL_GROUND_SINK := 11.5"),
]

for old, new in REPLACES:
    n = s.count(old)
    if n != 1:
        print("警告：%s 出现 %d 次，跳过" % (old[:50], n))
        continue
    s = s.replace(old, new)
    print("  %s  ==>  %s" % (old.strip(), new.strip()))

# 3) 喷口坐标按比例缩放：在 _build_external_exhaust 里插入 ref_scale
OLD_NOZ = "\t\tvar nozzle: Vector3 = EXHAUST_NOZZLES[i]\n"
NEW_NOZ = (
    "\t\t# ⚠ 2026-11-13：EXHAUST_NOZZLES 是在**机长 14 m** 时实测的坐标。\n"
    "\t\t#   现在机长可调（70 m），必须按比例缩放，否则喷焰会缩在机身中段。\n"
    "\t\tvar ref_scale: float = length / 14.0\n"
    "\t\tvar nozzle: Vector3 = (EXHAUST_NOZZLES[i] as Vector3) * ref_scale\n"
)
n = s.count(OLD_NOZ)
if n == 1:
    s = s.replace(OLD_NOZ, NEW_NOZ)
    print("  EXHAUST_NOZZLES 改为按 length/14.0 缩放")
else:
    print("警告：喷口锚点出现 %d 次，跳过" % n)

# 4) 喷口直径同理
OLD_D = "\t\tvar nozzle_d: float = 0.95      # 实测单喷口直径（米）\n"
NEW_D = "\t\tvar nozzle_d: float = 0.95 * ref_scale   # 实测单喷口直径（14 m 基准）x 比例\n"
n = s.count(OLD_D)
if n == 1:
    s = s.replace(OLD_D, NEW_D)
    print("  nozzle_d 改为 0.95 * ref_scale")
else:
    print("警告：nozzle_d 出现 %d 次，跳过" % n)

# 5) 腹部喷口的前后偏移用的是 length 比例，已经自适应；
#    但 belly_y 里的 +0.10 是固定米数，按比例放大
OLD_B = "\tvar belly_y: float = -SHIP_MODEL_GROUND_SINK + 0.10\n"
NEW_B = "\tvar belly_y: float = -SHIP_MODEL_GROUND_SINK + SHIP_MODEL_GROUND_SINK * 0.0435\n"
n = s.count(OLD_B)
if n == 1:
    s = s.replace(OLD_B, NEW_B)
    print("  belly_y 的 0.10 m 偏移改为按 SINK 比例")
else:
    print("警告：belly_y 出现 %d 次，跳过" % n)

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("\n完成。新机长 70 m（= 14 x 5），与 prop_scale 一致。")
