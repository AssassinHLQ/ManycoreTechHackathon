# -*- coding: utf-8 -*-
"""从 app.asar 里列出/提取文件。

asar 格式（无压缩）：
  u32 @0  = 4               （下一段的 pickle 长度）
  u32 @4  = 头部 payload 长度
  u32 @8  = 头部 JSON 长度
  12..12+jsonLen = JSON 头
  JSON 之后的文件数据起点 = 8 + (u32@4)

用法：
  python extract_asar.py list  [过滤子串]
  python extract_asar.py dump  <内部路径前缀> <输出目录>
"""
import io
import json
import os
import struct
import sys

PATH = r"C:\Users\WY157\AppData\Local\Programs\DeepSeek Harness\resources\app.asar"


def load_header():
    """实测头布局（4 个 u32，共 16 字节）：
        @0  = 4              pickle 长度标记
        @4  = 头部 payload 长度
        @8  = payload - 4
        @12 = JSON 字节数
        @16 = JSON 起点
       文件数据基址 = 8 + u32@4 = 16 + JSON 长度
    """
    with io.open(PATH, "rb") as fh:
        head = fh.read(16)
        _a, payload_len, _c, json_len = struct.unpack("<IIII", head)
        fh.seek(16)
        raw = fh.read(json_len)
    data_base = 8 + payload_len
    assert data_base == 16 + json_len, (data_base, json_len)
    return json.loads(raw.decode("utf-8")), data_base


def walk(node, prefix=""):
    """把 asar 的树摊平成 {路径: 条目}。"""
    out = {}
    files = node.get("files") or {}
    for name, child in files.items():
        p = (prefix + "/" + name) if prefix else name
        if "files" in child:
            out.update(walk(child, p))
        else:
            out[p] = child
    return out


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    header, data_base = load_header()
    flat = walk(header)
    print("条目总数 %d，数据基址 %d" % (len(flat), data_base))

    mode = sys.argv[1]
    if mode == "list":
        needle = sys.argv[2] if len(sys.argv) > 2 else ""
        seen = set()
        for p in sorted(flat):
            # 只看包名层，不要每个文件都刷屏
            parts = p.split("/")
            if len(parts) >= 3 and parts[0] == "node_modules":
                pkg = "/".join(parts[:3]) if parts[1].startswith("@") else "/".join(parts[:2])
                if needle.lower() in pkg.lower() and pkg not in seen:
                    seen.add(pkg)
                    print("  " + pkg)
            elif needle.lower() in p.lower():
                print("  " + p)

    elif mode == "dump":
        pre = sys.argv[2]
        outdir = sys.argv[3]
        n = 0
        with io.open(PATH, "rb") as fh:
            for p in sorted(flat):
                if not p.startswith(pre):
                    continue
                e = flat[p]
                if "offset" not in e:
                    continue
                off = data_base + int(e["offset"])
                size = int(e["size"])
                fh.seek(off)
                blob = fh.read(size)
                dest = os.path.join(outdir, p.replace(pre, "").lstrip("/"))
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with io.open(dest, "wb") as out:
                    out.write(blob)
                n += 1
                print("  %-60s %7d B" % (p.replace(pre, "").lstrip("/"), size))
        print("提取 %d 个文件 -> %s" % (n, outdir))


main()
