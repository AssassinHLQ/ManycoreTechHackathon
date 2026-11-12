"""放宽飞船修理的判定：范围太小、且「对准船体中心」太难。

用户：「飞船修理的判断范围太小了」

现状：
  · REPAIR_RANGE = 6.0 米 —— 是玩家**相机**到飞船**原点**的距离
  · 但飞船有 11 米长（HULL_Z = 3.25，即半长 3.25 米），原点在机身中心；
    站在机头旁边时，相机到原点的距离本身就有 3~4 米，余量极小
  · REPAIR_AIM_COS = 0.906（≈25° 锥角）—— 必须盯住**船体中心点**，
    贴着船身站时视线很容易落在别处，判定直接失败

改法（两条都放宽，但保留「必须靠近且大致朝向」的设计意图）：
  · 距离改成**到船体包围盒**的距离（站在船身任何部位附近都算），
    判定半径 6 → 14 米
  · 瞄准锥角 25° → 45°（cos 0.906 → 0.707）
  · 另外：距离很近（< 8 米）时**免掉瞄准判定** —— 都贴到船身上了，
    还要抬头对着中心点太苛刻
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SHIP = Path(__file__).resolve().parent.parent / "scripts" / "ship.gd"

OLD_CONST = '''## 能否开始修理的判定半径（米）。玩家要在飞船附近。
const REPAIR_RANGE := 6.0
## 对着飞船的判定：视线方向与「玩家→飞船」夹角余弦要大于它（≈ 25°）。
const REPAIR_AIM_COS := 0.906'''

NEW_CONST = '''## 能否开始修理的判定半径（米）。玩家要在飞船附近。
##
## ⚠ 2026-11-11 用户：「飞船修理的判断范围太小了」。
##   原来是 6 米，而且量的是**相机到飞船原点**的距离 —— 飞船半长 3.25 米，
##   站在机头旁边光这段就吃掉 3~4 米余量，稍微一站偏就判不到。
##   现在放大到 14 米，并改成量**到船体包围盒**的距离（见 repair_check）。
const REPAIR_RANGE := 14.0
## 对着飞船的判定：视线方向与「玩家→飞船」夹角余弦要大于它（≈ 45°）。
##
## 原来 0.906（≈25°）要求盯住**船体中心点**，贴着船身站时视线常落在别处，
## 手感很差。放宽到 0.707（≈45°），并且**近距离直接免掉瞄准判定**。
const REPAIR_AIM_COS := 0.707
## 贴得这么近（米）就不检查瞄准了 —— 都站到船身上了，不用再抬头找中心。
const REPAIR_CONTACT_RANGE := 8.0'''

OLD_CHECK = '''	var to_ship: Vector3 = global_position - player.camera.global_position
	var dist: float = to_ship.length()
	if dist > REPAIR_RANGE:
		return [false, ""]                      # 太远就不提示，免得满屏字'''

NEW_CHECK = '''	var cam_pos: Vector3 = player.camera.global_position
	# 距离按**到船体包围盒**量，而不是到船体原点：
	# 飞船半长 3.25 米、半高 1.0 米，站到机头/机尾旁边时原点其实不近。
	var local: Vector3 = global_transform.affine_inverse() * cam_pos
	var box := Vector3(HULL_X, HULL_Y, HULL_Z)
	var outside := Vector3(
		maxf(0.0, absf(local.x) - box.x),
		maxf(0.0, absf(local.y) - box.y),
		maxf(0.0, absf(local.z) - box.z))
	var dist: float = outside.length()          # 0 = 已经在船体范围内
	if dist > REPAIR_RANGE:
		return [false, ""]                      # 太远就不提示，免得满屏字
	var to_ship: Vector3 = global_position - cam_pos'''

OLD_AIM = '''	var fwd: Vector3 = -player.camera.global_transform.basis.z
	if dist > 0.001:
		var aim: float = fwd.normalized().dot(to_ship.normalized())
		if aim < REPAIR_AIM_COS:
			return [false, "对准飞船再按 F 修理"]'''

NEW_AIM = '''	# 贴近船身时免掉瞄准判定：都站到船边了，不用再抬头找中心点。
	if dist > REPAIR_CONTACT_RANGE:
		var fwd: Vector3 = -player.camera.global_transform.basis.z
		if to_ship.length() > 0.001:
			var aim: float = fwd.normalized().dot(to_ship.normalized())
			if aim < REPAIR_AIM_COS:
				return [false, "对准飞船再按 F 修理"]'''


def main() -> None:
    t = SHIP.read_text(encoding="utf-8", errors="replace")
    ok = 0
    for old, new, label in (
        (OLD_CONST, NEW_CONST, "放宽半径与锥角 + 加接触距离"),
        (OLD_CHECK, NEW_CHECK, "距离改按包围盒计算"),
        (OLD_AIM, NEW_AIM, "近距离免瞄准"),
    ):
        if old in t:
            t = t.replace(old, new, 1)
            ok += 1
            print("✓", label)
        else:
            print("✗ 没找到：", label)
    SHIP.write_text(t, encoding="utf-8", newline="")
    print("%d/3" % ok)


if __name__ == "__main__":
    main()
