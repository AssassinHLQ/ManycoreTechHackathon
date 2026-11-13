# -*- coding: utf-8 -*-
"""步骤 C + D（A/B 由另一个会话负责，本脚本刻意不碰 _prop_mesh_for_instancing）。

C. 网格缓存加 LRU 上限
   _prop_mesh_cache 是 static、只增不减，20 颗星球共用一个进程内缓存。
   高模网格单个 10~20 MB，全留会吃光内存。加 48 个上限 + LRU 淘汰。

   \u26a0 关键：淘汰只是丢掉**缓存里的那条引用**。Mesh 若还被某个星球的
     MultiMesh 持有，引用计数会让它继续存活 —— 不会黑模、不会掉贴图。
     下次再需要时重新从 GLB 载入（很便宜，一次实例化）。

D. 道具绘制距离跟 LOD 设置联动
   原来硬编码 visibility_range_end = 2200.0，与设置里的 LOD 档位无关。
   现在读 settings.LOD_DISTANCE[level]：LOD=0 时 900 米外直接不出 GPU。
   建场时 settings 尚未创建（它在 _build_world_progressive 里排在行星之后），
   此时按默认档位 2；settings 建好后会调 _apply_lod() 用同一套数值再刷一遍。

   地标/大地貌件（lm-* / lf-*）与 settings._apply_lod 保持一致，乘 1.6 ——
   否则远处地标会突然消失。
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

P = "scripts/planet.gd"
s = io.open(P, encoding="utf-8").read()
orig = s
ok = []


def sub(old, new, label):
    global s
    n = s.count(old)
    if n != 1:
        print("  [跳过] %s：锚点出现 %d 次" % (label, n))
        return
    s = s.replace(old, new)
    ok.append(label)
    print("  [完成] %s" % label)


# ── 1) 加 settings preload（不改动已有的 preload 行）──────────────────
sub(
    'const CloudShader = preload("res://shaders/clouds.gdshader")\n',
    'const CloudShader = preload("res://shaders/clouds.gdshader")\n'
    '## 读取 LOD 距离档位用。settings.gd 不 preload 任何脚本，无循环依赖。\n'
    'const SettingsScript = preload("res://scripts/settings.gd")\n',
    "planet.gd 增加 SettingsScript preload",
)

# ── 2) 缓存加 LRU 结构 ────────────────────────────────────────────────
sub(
    "## 已加载的 AI 网格缓存（prop_id -> Mesh），同一进程里 20 颗星球共用一份。\n"
    "static var _prop_mesh_cache := {}\n",
    "## 已加载的 AI 网格缓存（prop_id -> Mesh），同一进程里 20 颗星球共用一份。\n"
    "static var _prop_mesh_cache := {}\n"
    "## 缓存上限（LRU）。高模网格单个 10~20 MB，48 个已经足够覆盖\n"
    "## 「当前星球 + 相邻几颗」的常用道具，再多的部分淘汰掉。\n"
    "const PROP_CACHE_LIMIT := 48\n"
    "## LRU 顺序：队尾最新。淘汰时从队首摘。\n"
    "static var _prop_cache_order: Array = []\n",
    "增加 PROP_CACHE_LIMIT 与 _prop_cache_order",
)

# ── 3) 缓存命中时也刷新 LRU 位置 ──────────────────────────────────────
sub(
    "static func _prop_mesh(prop_id: String) -> Mesh:\n"
    "\tif _prop_mesh_cache.has(prop_id):\n"
    "\t\treturn _prop_mesh_cache[prop_id]\n",
    "static func _prop_mesh(prop_id: String) -> Mesh:\n"
    "\tif _prop_mesh_cache.has(prop_id):\n"
    "\t\t_prop_cache_touch(prop_id)\n"
    "\t\treturn _prop_mesh_cache[prop_id]\n",
    "缓存命中时刷新 LRU",
)

# ── 4) 插入后登记 LRU ─────────────────────────────────────────────────
sub(
    "\t_prop_mesh_cache[prop_id] = mesh\n\treturn mesh\n",
    "\t_prop_mesh_cache[prop_id] = mesh\n"
    "\t_prop_cache_touch(prop_id)\n"
    "\treturn mesh\n"
    "\n"
    "\n"
    "## 把 prop_id 挪到 LRU 队尾，并在超过上限时淘汰队首。\n"
    "##\n"
    "## \u26a0 淘汰只删除**缓存里的引用**。如果某个星球的 MultiMesh 仍然持有该\n"
    "##   Mesh，引用计数会让它继续存活（不会黑模/掉贴图）。下次再需要时\n"
    "##   重新载入 GLB 即可 —— 一次 PackedScene.instantiate，代价很小。\n"
    "static func _prop_cache_touch(prop_id: String) -> void:\n"
    "\t_prop_cache_order.erase(prop_id)\n"
    "\t_prop_cache_order.append(prop_id)\n"
    "\twhile _prop_cache_order.size() > PROP_CACHE_LIMIT:\n"
    "\t\tvar oldest: String = String(_prop_cache_order.pop_front())\n"
    "\t\tif oldest != prop_id:\n"
    "\t\t\t_prop_mesh_cache.erase(oldest)\n",
    "插入后登记 LRU + 淘汰函数",
)

# ── 5) D：绘制距离改用 LOD 档位 ───────────────────────────────────────
sub(
    "\t\tinstance.visibility_range_end = 2200.0\n",
    "\t\tinstance.visibility_range_end = _lod_view_distance_for(prop_id)\n",
    "visibility_range_end 改用 LOD 档位",
)

# ── 6) 加 LOD 距离辅助函数（放在 _flush_props 之前）────────────────────
sub(
    "func _flush_vegetation() -> void:\n",
    "## 该类道具的绘制距离（米），跟随设置里的 LOD 档位。\n"
    "##\n"
    "## 建场时 settings 还没创建（它在 _build_world_progressive 里排在行星之后），\n"
    "## 所以先按默认档位 2；settings 建好后会调 _apply_lod() 用同一套数值再刷一遍，\n"
    "## 因此两者不会打架。\n"
    "## 地标（lm-*）与大地貌件（lf-*）乘 1.6，与 settings._apply_lod 保持一致。\n"
    "func _lod_view_distance_for(prop_id: String) -> float:\n"
    "\tvar level: int = 2\n"
    "\tif game != null and game.settings != null:\n"
    "\t\tlevel = clampi(int(game.settings.values.lod), 0, 3)\n"
    "\tvar d: float = float(SettingsScript.LOD_DISTANCE[clampi(level, 0, 3)])\n"
    "\tif prop_id.contains(\"lm-\") or prop_id.contains(\"lf-\"):\n"
    "\t\treturn d * 1.6\n"
    "\treturn d\n"
    "\n"
    "\n"
    "func _flush_vegetation() -> void:\n",
    "增加 _lod_view_distance_for 辅助函数",
)

if s != orig:
    io.open(P, "w", encoding="utf-8", newline="").write(s)
print("\n完成 %d / 6 项" % len(ok))
