import io
import re
import sys

PATH = r"scripts\ship.gd"

with io.open(PATH, encoding="utf-8") as f:
    src = f.read()

orig = src

# ── 1. hull_shape 不再是 BoxShape3D ──
src = src.replace(
    "var hull_shape: BoxShape3D",
    "var hull_shape: Shape3D")

# ── 2. 记录 GLB 实例与 holder，供碰撞取顶点用 ──
anchor = "var ship_model_center := Vector3.ZERO"
assert src.count(anchor) == 1, "ship_model_center anchor"
src = src.replace(anchor, anchor + """

## GLB 实例根节点与它的 holder（ShipModel），碰撞形状要从这里取顶点。
## 见 _build_mesh_collision / _collect_model_faces。
var _ship_model_root: Node3D = null
var _ship_model_holder: Node3D = null""")

# ── 3. _ready 里：先试「三角面碰撞」，失败才退回盒子 ──
new_hull = '''\tvar hull_collision := CollisionShape3D.new()
\thull_collision.name = "Hull"
\t# ⚠ 2026-11-11 用户：「碰撞怎么还是长方形？不能低多边形覆盖吗？」
\t#
\t#   旧版一直是一个 BoxShape3D 罩住整艘船。历史沿革（都记在这里，别再往回改）：
\t#     · 第一版：包围盒 × 0.72/0.85 —— 覆盖率 X 72% / Y 85% / Z 58%，
\t#       机头、机尾、机翼都有大块无碰撞区，人能直接走进模型里；
\t#     · 第二版：提到 × 0.97，覆盖率够了，但中心按「高/2」放，整体悬在
\t#       机身上方 2.3 米（GLB 原点在机身中部偏上，AABB 的 y 是负的）；
\t#     · 第三版：改成用 AABB 中心，位置终于对了，**但形状仍然是长方形**。
\t#
\t#   为什么长方形必然不对：这艘船机头是尖的、机翼是薄的后掠三角翼、
\t#   机尾三个喷口内凹。盒子把这些全算成实心 —— 机头正前方两米就有空气墙，
\t#   机翼下方和机身之间的大块空气也被挡住，「碰撞手感」完全对不上眼睛。
\t#
\t#   现在：直接用**可见网格的三角面**当碰撞面（ConcavePolygonShape3D）。
\t#     · 形状 100% 等于看到的外形，没有空气墙，也钻不进去；
\t#     · hull_body 是 StaticBody3D，三角网碰撞正是它的标准用法，
\t#       不需要做凸包分解（凹面也能精确表达）；
\t#     · 站点碰撞查询需要一个「整体形状」，那里用同一批顶点抽稀出的
\t#       低多边形凸包（ConvexPolygonShape3D），比盒子贴合得多。
\t#
\t#   顶点只取 GLB 本体（model 子树）—— holder 下面还挂着程序化补的
\t#   尾焰与光环，那些是发光特效，绝不能算进碰撞。
\tif _build_mesh_collision(hull_collision):
\t\tpass
\telif ship_model_length > 0.01:
\t\tvar box := BoxShape3D.new()
\t\tbox.size = Vector3(
\t\t\tmaxf(0.6, ship_model_span * 0.97),
\t\t\tmaxf(0.5, ship_model_height * 0.97),
\t\t\tmaxf(0.8, ship_model_length * 0.97))
\t\thull_collision.position = ship_model_center
\t\thull_collision.shape = box
\t\thull_shape = box
\telse:
\t\tvar box := BoxShape3D.new()
\t\tbox.size = Vector3(3.0, 1.8, 4.6)
\t\thull_collision.position = Vector3(0, -0.2, 0.2)
\t\thull_collision.shape = box
\t\thull_shape = box
\thull_body.add_child(hull_collision)
\tadd_child(hull_body)'''

pattern = re.compile(
    r"\tvar hull_collision := CollisionShape3D\.new\(\).*?\tadd_child\(hull_body\)",
    re.DOTALL)
assert pattern.search(src), "ready hull block not found"
src = pattern.sub(lambda m: new_hull, src, count=1)

# ── 4. _build_external_model 末尾记录节点引用 ──
anchor4 = "\t_build_external_exhaust(holder, bounds)\n\treturn true"
assert src.count(anchor4) == 1, "exhaust anchor"
src = src.replace(anchor4,
                  "\t_ship_model_root = model\n"
                  "\t_ship_model_holder = holder\n"
                  "\t_build_external_exhaust(holder, bounds)\n"
                  "\treturn true")

# ── 5. 站点查询的 transform 不再需要手工偏移（形状已在船体局部空间）──
offset_old = "at_position + global_transform.basis * Vector3(0.0, -0.2, 0.2)"
n = src.count(offset_old)
assert n == 2, "station offset count = %d" % n
src = src.replace(offset_old, "at_position")

# ── 6. 插入两个新函数（在 _build_external_exhaust 的说明块之前）──
anchor6 = "## 按实测包围盒在机尾补三束喷焰（外部模型专用，见 _build_external_model）。"
assert src.count(anchor6) == 1, "insert anchor"

helpers = '''## 把模型自己的三角面做成碰撞形状（见 _ready 里的说明）。
##
## 返回 true 表示成功；此时：
##   · collider.shape   = ConcavePolygonShape3D（可见网格的三角面，船体局部空间）
##   · hull_shape       = ConvexPolygonShape3D（同一批顶点抽稀的凸包，给站点查询用）
## 返回 false 时调用方退回盒子。
func _build_mesh_collision(collider: CollisionShape3D) -> bool:
\tvar faces := _collect_model_faces()
\tif faces.size() < 36:
\t\t# 少于 12 个三角面就没意义（模型没加载 / 只有几张片），退回盒子。
\t\treturn false
\tvar concave := ConcavePolygonShape3D.new()
\tconcave.set_faces(faces)
\tcollider.shape = concave
\tcollider.position = Vector3.ZERO
\t# 站点碰撞查询用的整体形状：同一批顶点按 1/16 米网格抽稀成低多边形凸包。
\t# ConvexPolygonShape3D 的点越少查询越快，3000 个点对一艘 14 米长的船足够贴合。
\tvar pts := PackedVector3Array()
\tvar seen := {}
\tvar stride: int = maxi(1, int(faces.size() / 3000.0))
\tfor i in range(0, faces.size(), stride):
\t\tvar key := Vector3i((faces[i] * 16.0).round())
\t\tif seen.has(key):
\t\t\tcontinue
\t\tseen[key] = true
\t\tpts.append(faces[i])
\tif pts.size() >= 4:
\t\tvar convex := ConvexPolygonShape3D.new()
\t\tconvex.points = pts
\t\thull_shape = convex
\treturn true


## 收集 GLB 本体全部三角面顶点，转换到 **ship 局部空间**（= 碰撞体所在空间）。
##
## holder 带了缩放与居中偏移，model 自己可能带朝向旋转，网格节点可能还有中间层，
## 所以每个 MeshInstance3D 都要把「它到 model 的相对变换」乘上「model 到 ship 的变换」。
## 这段 walker 写法和 _build_external_model 里量包围盒那段完全同源，改一处要改两处。
func _collect_model_faces() -> PackedVector3Array:
\tvar faces := PackedVector3Array()
\tvar root: Node3D = _ship_model_root
\tif root == null or not is_instance_valid(root):
\t\treturn faces
\tvar holder_xform := Transform3D.IDENTITY
\tif _ship_model_holder != null and is_instance_valid(_ship_model_holder):
\t\tholder_xform = _ship_model_holder.transform
\tvar stack: Array[Node] = [root]
\twhile not stack.is_empty():
\t\tvar node: Node = stack.pop_back()
\t\tif node is MeshInstance3D:
\t\t\tvar mi := node as MeshInstance3D
\t\t\tif mi.mesh != null:
\t\t\t\tvar rel := Transform3D.IDENTITY
\t\t\t\tvar walker: Node = mi
\t\t\t\twhile walker != null and walker != root:
\t\t\t\t\trel = (walker as Node3D).transform * rel
\t\t\t\t\twalker = walker.get_parent()
\t\t\t\tif walker == root:
\t\t\t\t\trel = root.transform * rel
\t\t\t\tvar xform: Transform3D = holder_xform * rel
\t\t\t\tfor s in range(mi.mesh.get_surface_count()):
\t\t\t\t\tvar arrays: Array = mi.mesh.surface_get_arrays(s)
\t\t\t\t\tif arrays.size() <= Mesh.ARRAY_VERTEX:
\t\t\t\t\t\tcontinue
\t\t\t\t\tvar verts = arrays[Mesh.ARRAY_VERTEX]
\t\t\t\t\tif verts == null:
\t\t\t\t\t\tcontinue
\t\t\t\t\tvar vpack: PackedVector3Array = verts
\t\t\t\t\tvar idx = arrays[Mesh.ARRAY_INDEX]
\t\t\t\t\tif idx != null:
\t\t\t\t\t\tvar ipack: PackedInt32Array = idx
\t\t\t\t\t\tvar n: int = ipack.size() - (ipack.size() % 3)
\t\t\t\t\t\tvar k := 0
\t\t\t\t\t\twhile k < n:
\t\t\t\t\t\t\tfaces.append(xform * vpack[ipack[k]])
\t\t\t\t\t\t\tfaces.append(xform * vpack[ipack[k + 1]])
\t\t\t\t\t\t\tfaces.append(xform * vpack[ipack[k + 2]])
\t\t\t\t\t\t\tk += 3
\t\t\t\t\telse:
\t\t\t\t\t\tvar n2: int = vpack.size() - (vpack.size() % 3)
\t\t\t\t\t\tvar k2 := 0
\t\t\t\t\t\twhile k2 < n2:
\t\t\t\t\t\t\tfaces.append(xform * vpack[k2])
\t\t\t\t\t\t\tfaces.append(xform * vpack[k2 + 1])
\t\t\t\t\t\t\tfaces.append(xform * vpack[k2 + 2])
\t\t\t\t\t\t\tk2 += 3
\t\tfor child in node.get_children():
\t\t\tstack.append(child)
\treturn faces


'''

src = src.replace(anchor6, helpers + anchor6)

with io.open(PATH, "w", encoding="utf-8", newline="\n") as f:
    f.write(src)

print("changed bytes: %d -> %d" % (len(orig), len(src)))
