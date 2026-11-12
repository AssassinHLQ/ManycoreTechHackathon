"""落地后每帧把飞船重钉到行星地表，消除与行星变换的帧间错拍（震动）。

排查结论（probe_landed_jitter.gd 实测）：
  velocity = 0、朝向漂移 0.0000 度、terrain_height 差 0.000 米
  → 飞船本体既没在动速度、也没在转，地形也没变
  但世界坐标每帧仍在动 0.11~0.32 米

原因：飞船 reparent 到行星之后**没有每帧重钉**。
  对接分支有 `global_position = docked_station.dock_ship_position()` 这样的重钉，
  落地分支没有 —— 行星在 `_process` 里更新位置，飞船在 `_physics_process` 里读，
  两者不同步就是肉眼可见的微抖。

修法：落地后记下「着陆时的地表方向」，每帧按当前地形高度重新贴一次。
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SHIP = Path(__file__).resolve().parent.parent / "scripts" / "ship.gd"

OLD = '''	if landed:
		velocity = Vector3.ZERO
		thrust_level = 0.0'''

NEW = '''	if landed:
		velocity = Vector3.ZERO
		thrust_level = 0.0
		# ⚠ 2026-11-11 每帧重钉到地表：落地后飞船挂在行星下，但行星在
		#   `_process` 里更新位置、飞船在 `_physics_process` 里读，两者不同步
		#   会产生肉眼可见的微抖（实测世界坐标每帧 0.11~0.32 米）。
		#   对接分支一直是这么做的，落地分支漏了。
		if landed_planet != null and is_instance_valid(landed_planet):
			global_position = landed_planet.global_position \\
				+ landed_planet.surface_position(landing_normal, LANDING_REST_ALT)'''

# 记录着陆方向
OLD2 = '''	landed = true
	land_phase = LandPhase.NONE
	thrust_level = 0.0
	game.audio.play_ui(330.0)'''
NEW2 = '''	landed = true
	land_phase = LandPhase.NONE
	landing_normal = normal
	thrust_level = 0.0
	game.audio.play_ui(330.0)'''

# 兼容版 land() 也记录
OLD3 = '''	_align_belly_to(normal, 1.0, 1.0)
	landed = true
	land_phase = LandPhase.NONE
	game.audio.play_ui(330.0)'''
NEW3 = '''	_align_belly_to(normal, 1.0, 1.0)
	landed = true
	land_phase = LandPhase.NONE
	landing_normal = normal
	game.audio.play_ui(330.0)'''

# 声明变量
OLD4 = '''var land_phase: int = LandPhase.NONE'''
NEW4 = '''var land_phase: int = LandPhase.NONE
## 着陆时的地表法线（用于每帧重钉位置，消除帧间错拍）
var landing_normal := Vector3.UP'''


def main() -> None:
    t = SHIP.read_text(encoding="utf-8", errors="replace")
    ok = 0
    for old, new, label in (
        (OLD4, NEW4, "声明 landing_normal"),
        (OLD, NEW, "落地分支每帧重钉"),
        (OLD2, NEW2, "记录着陆法线(状态机)"),
        (OLD3, NEW3, "记录着陆法线(兼容 land)"),
    ):
        if old in t:
            t = t.replace(old, new, 1)
            ok += 1
            print("✓", label)
        else:
            print("✗ 没找到：", label)
    SHIP.write_text(t, encoding="utf-8", newline="")
    print("%d/4" % ok)


if __name__ == "__main__":
    main()
