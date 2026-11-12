# -*- coding: utf-8 -*-
"""修正「其余模型」段落 + 补全许可证表。"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

P = "THIRD_PARTY_NOTICES.md"
s = io.open(P, encoding="utf-8").read()

OLD1 = (
    "其余模型（`black-hole`、`one-dim-star`、`qinglan-planet*`、`ship-fighter`、\n"
    "`space-station*`）为本项目自行制作或程序化生成，见 3.7。"
)
NEW1 = (
    "**以下模型不是 Lux3D 产出**，为本项目自行制作或程序化生成，见 3.7：\n"
    "`black-hole`（黑洞）、`one-dim-star`（一维星点云）、`ship-fighter`（玩家飞船）、\n"
    "`space-station` / `space-station-3`（归航站外壳）。"
)

OLD2 = (
    "| Aholo Lux3D 生成的星球模型（`assets/models/*-lux3d`） | 平台条款 | "
    "**非本仓库可再许可**，见 3.2.2 |"
)
NEW2 = (
    "| Aholo Lux3D 生成的星球模型（`assets/models/*-lux3d*`） | 平台条款 | "
    "**非本仓库可再许可**，见 3.2.2 |\n"
    "| Aholo Lux3D 生成的阁楼/世界摆件（`assets/models/props/attic*`） | 平台条款 | "
    "同上，见 3.2.3 |\n"
    "| Aholo Lux3D 生成的星球道具（`assets/models/props/*`） | 平台条款 | 同上，见 3.2.5 |"
)

changed = []
if OLD1 in s:
    s = s.replace(OLD1, NEW1)
    changed.append("其余模型段")
else:
    print("警告：OLD1 未找到")

if OLD2 in s:
    s = s.replace(OLD2, NEW2)
    changed.append("许可表")
else:
    print("警告：OLD2 未找到")

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("已修改：" + ("、".join(changed) if changed else "无"))
