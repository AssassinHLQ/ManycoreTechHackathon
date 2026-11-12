# -*- coding: utf-8 -*-
"""扫 OpenGameArt 的 space 音乐合集，逐首核实许可证 + 是否禁止改编。

用户的要求：
  · 项目开源  -> CC-BY-SA 可用
  · 会二次处理音频 -> 必须允许改编，绝对不能是 ND（NoDerivatives）
  · 商用 -> 不能是 NC

OpenGameArt 的许可证图标文件名就是标识，比读正文可靠：
  cc0 / cc-by / cc-by-sa / cc-by-nd / cc-by-nc / gpl / oga-by
"""
import re
import time
import urllib.request

COLLECTION = "https://opengameart.org/content/audiomusicspace"
UA = {"User-Agent": "Mozilla/5.0"}

# 禁止改编 / 禁止商用的标记
BLOCK_DERIV = ("nd",)
BLOCK_COMM = ("nc",)


def fetch(url, timeout=30):
    req = urllib.request.Request(url, headers=UA)
    return urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8", "replace")


def licenses_of(html):
    raw = set(re.findall(r"license_images/([A-Za-z0-9_\-]+)\.png", html))
    return sorted(x.lower().replace("_", "-") for x in raw)


def classify(lics):
    """返回 (可用?, 原因)"""
    if not lics:
        return False, "无许可证信息"
    joined = " ".join(lics)
    # cc0 单独出现就是最宽松
    if lics == ["cc0"]:
        return True, "CC0 最宽松"
    if any(any(b in l for b in BLOCK_DERIV) for l in lics):
        return False, "含 ND：禁止改编"
    if any(any(b in l for b in BLOCK_COMM) for l in lics):
        return False, "含 NC：禁止商用"
    ok = [l for l in lics if l in ("cc0", "cc-by", "cc-by-sa", "gpl", "oga-by")]
    if ok:
        return True, "/".join(ok).upper()
    return False, "未知协议 " + "/".join(lics)


def main():
    html = fetch(COLLECTION)
    links = []
    for m in re.finditer(r'href="(/content/[^"]+)"', html):
        p = m.group(1)
        if p in ("/content/faq",):
            continue
        if p not in links:
            links.append(p)
    print("合集里发现 %d 个条目\n" % len(links))

    good, bad = [], []
    for i, path in enumerate(links):
        url = "https://opengameart.org" + path
        try:
            h = fetch(url, timeout=20)
        except Exception as e:
            print("  [%02d] %-44s ERR %s" % (i, path, e))
            continue
        t = re.search(r"<title>(.*?)</title>", h, re.S)
        title = t.group(1).split("|")[0].strip() if t else path
        lics = licenses_of(h)
        ok, why = classify(lics)
        # 音频文件类型（便于判断可编辑性）
        aud = re.findall(r'href="([^"]+\.(ogg|mp3|wav|flac))"', h)
        exts = sorted(set(a[1] for a in aud))
        (good if ok else bad).append((title, url, why, exts))
        print("  [%02d] %-46s %-10s %s" % (i, title[:44], "/".join(exts) or "-", why))
        time.sleep(0.4)

    print("\n" + "=" * 78)
    print("### 可用（允许改编 + 商用）：%d 首" % len(good))
    for title, url, why, exts in good:
        print("  · %-46s %-14s [%s]" % (title[:44], why, "/".join(exts) or "-"))
        print("    %s" % url)
    print("\n### 不可用：%d 首" % len(bad))
    for title, url, why, exts in bad:
        print("  ✗ %-46s %s" % (title[:44], why))


main()
