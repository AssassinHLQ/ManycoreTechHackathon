"""把第二批十颗星球插进 main.gd 的 anomaly_text 和 definitions。

用按行定位的脚本而不是手写 edit，原因是那段是制表符缩进的 GDScript 字典，
jianmo 那行末尾没有逗号，手改容易踩缩进/逗号。
"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

MAIN = Path(__file__).resolve().parent.parent / "scripts" / "main.gd"

NEW_ANOMALY = [
    ("chixiao", "红色的第一课", "赤霄星的沙是锈的。这里下过一次铁雨，从那以后所有东西都在慢慢变红。记录者把测得的含铁量刻在崖壁上，最后一行的字迹很新：我们也是会锈的。"),
    ("cangwu", "树没有名字", "苍梧星的人不给树起名。他们说树活得比名字久，起名是给自己留念想。林下留有半截木牌，正面空白，背面刻着一行小字：这棵是我们一起种的。"),
    ("jinwu", "正午不会结束", "金乌星的日照长得不像话。这里的钟表全部停在同一个时刻，因为不需要别的时刻。白色盐盘上有一串脚印，走了很远，最后停在正中央。"),
    ("yuheng", "称过的玉", "玉衡星的每一块石英都被称过重量，数字写在旁边的石台上。没有人解释为什么需要这些数字，但石台被擦得很干净——像是有人一直在这里等一个答案。"),
    ("sue", "灰色的纪念", "素娥星什么都没有，只有灰。灰下面埋着整整齐齐的一排排石桩，没有字。看久了会发现它们的间距完全一致——这是有人在数什么，数了很久。"),
    ("danxia", "一层就是一万年", "丹霞星的岩壁是一本竖着放的书。红色是一层，赭色是一层，白的是中间那次长久的停顿。有人在某一层的高度上凿了一个小龛，里面空的，但龛口朝东。"),
    ("biluo", "浅水里的回声", "碧落星的水浅得能看见自己的影子。环礁围出的湖里没有风，声音传不出去，喊一句要等很久才回来——回来的时候已经不是同一句了。"),
    ("youdu", "这里不需要光", "幽都星的光很弱，弱到只能看清脚下。这里的人把灯都朝内放，说是为了不惊动外面的暗。最后一份记录只有半句：暗不是敌人，是——"),
    ("yaoguang", "亮得看不清", "瑶光星太亮了。晶石把光反复折射，让人分不清远近。观测站的镜面全部朝下，据说这样才看得清星星；镜面朝上的那些，都已经熔了。"),
    ("xuanpu", "长在暗处的", "玄圃星的植被只在阴影里发光，越暗越亮。整片园子像是有人精心打理过——修剪整齐、留有步道——但没有脚印，也没有门。"),
]


def main() -> None:
    text = MAIN.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines(True)

    # ── 1. anomaly_text：在 jianmo 那行之后插入 ──
    idx = None
    for i, line in enumerate(lines):
        if line.startswith('\t\t"jianmo": ["门后没有空气"'):
            idx = i
            break
    if idx is None:
        raise SystemExit("没找到 jianmo 的 anomaly 行")

    if '"chixiao"' in text:
        print("anomaly 已插入过，跳过")
    else:
        # jianmo 行补逗号
        if not lines[idx].rstrip().endswith(","):
            lines[idx] = lines[idx].rstrip() + ",\n"
        ins = []
        for pid, title, body in NEW_ANOMALY:
            ins.append('\t\t"%s": ["%s", "%s"],\n' % (pid, title, body))
        lines[idx + 1:idx + 1] = ins
        print("已插入 %d 条 anomaly" % len(ins))

    MAIN.write_text("".join(lines), encoding="utf-8", newline="")
    print("写出", MAIN)


if __name__ == "__main__":
    main()
