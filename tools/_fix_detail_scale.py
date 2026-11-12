"""修细节着色器的坐标系：VERTEX 是模型单位，必须乘 to_world 才是米。"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
REPO = Path(__file__).resolve().parent.parent
SH = REPO / "shaders" / "planet_detail.gdshader"
PL = REPO / "scripts" / "planet.gd"


def main() -> None:
    s = SH.read_text(encoding="utf-8", errors="replace")
    if "model_scale" not in s:
        s = s.replace(
            'uniform vec3 detail_tint : source_color = vec3(1.02, 0.99, 0.95);',
            'uniform vec3 detail_tint : source_color = vec3(1.02, 0.99, 0.95);\n'
            '// 模型单位 -> 米的缩放（由 planet.gd 传入 to_world）\n'
            'uniform float model_scale = 1.0;',
        )
        s = s.replace(
            "\tv_local = VERTEX;",
            "\t// VERTEX 是模型空间单位（球半径约 0.5），乘上缩放才是真实米数\n"
            "\tv_local = VERTEX * model_scale;",
        )
        SH.write_text(s, encoding="utf-8", newline="")
        print("✓ 着色器改用真实米")
    else:
        print("· 着色器已修过")

    p = PL.read_text(encoding="utf-8", errors="replace")
    if "_apply_detail_material(world_scale" not in p:
        p = p.replace(
            "func _apply_detail_material() -> void:",
            "func _apply_detail_material(world_scale: float) -> void:",
        )
        p = p.replace(
            "_apply_detail_material()\n",
            "_apply_detail_material(to_world)\n",
        )
        p = p.replace(
            '\t\t\tmat.set_shader_parameter("detail_meters", 8.0)',
            '\t\t\tmat.set_shader_parameter("detail_meters", 8.0)\n'
            '\t\t\tmat.set_shader_parameter("model_scale", world_scale)',
        )
        PL.write_text(p, encoding="utf-8", newline="")
        print("✓ planet.gd 传入 world_scale")
    else:
        print("· planet.gd 已修过")


if __name__ == "__main__":
    main()
