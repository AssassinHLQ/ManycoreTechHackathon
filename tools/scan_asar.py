# -*- coding: utf-8 -*-
"""在 app.asar（本质是 头JSON + 拼接文件）里搜关键字，打印上下文。

为什么要这样搜：app.asar 不是压缩包，是「4字节长度 + JSON 头 + 原始文件字节」
直接拼起来的。所以包名、错误文案都是明文，可以按字节扫。
用 Find 而不是把它当文本读，避免 208MB 一次性进内存。
"""
import io
import sys

PATH = r"C:\Users\WY157\AppData\Local\Programs\DeepSeek Harness\resources\app.asar"
NEEDLES = [
    b"web-search-deepseek",
    b"dsh-web-search",
    b"is not registered",
    b"webSearch",
]
CTX = 160
LIMIT_PER = 6


def main():
    hits = {n: [] for n in NEEDLES}
    with io.open(PATH, "rb") as fh:
        # 分块读，块间保留重叠，避免关键字跨块漏掉
        chunk_size = 8 << 20
        overlap = max(len(n) for n in NEEDLES) + CTX * 2
        prev = b""
        base = 0
        while True:
            chunk = fh.read(chunk_size)
            if not chunk:
                break
            buf = prev + chunk
            for n in NEEDLES:
                if len(hits[n]) >= LIMIT_PER:
                    continue
                start = 0
                while len(hits[n]) < LIMIT_PER:
                    i = buf.find(n, start)
                    if i < 0:
                        break
                    lo = max(0, i - CTX)
                    hi = min(len(buf), i + len(n) + CTX)
                    hits[n].append((base - len(prev) + i, buf[lo:hi]))
                    start = i + 1
            base += len(chunk)
            prev = buf[-overlap:]

    for n in NEEDLES:
        print("\n" + "=" * 70)
        print("### %s  ->  %d hit(s)" % (n.decode(), len(hits[n])))
        for off, blob in hits[n]:
            txt = blob.decode("utf-8", "replace")
            txt = " ".join(txt.split())
            print("  @0x%X  ...%s..." % (off, txt[:300]))


main()
