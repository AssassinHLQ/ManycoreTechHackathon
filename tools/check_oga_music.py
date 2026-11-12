# -*- coding: utf-8 -*-
"""核实一批 OpenGameArt 曲目的许可证、作者、时长、下载量。

合集页（collection）不显示许可证，必须逐首打开详情页才看得到。
这个脚本直接抓 HTML，从 license_images 图标和 License(s) 区块里取真值。
"""
import re
import urllib.request

URLS = [
    "https://opengameart.org/content/deep-space-flight",
    "https://opengameart.org/content/background-space-track",
    "https://opengameart.org/content/another-space-background-track",
    "https://opengameart.org/content/new-beginning",
    "https://opengameart.org/content/mysterious-ambience-song21",
    "https://opengameart.org/content/space-music-out-there",
    "https://opengameart.org/content/cc0-calm-relaxing-music",
    "https://opengameart.org/content/dark-sci-fi-audio-pack",
]


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    return urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "replace")


def main():
    for u in URLS:
        slug = u.rsplit("/", 1)[-1]
        try:
            h = fetch(u)
        except Exception as e:
            print("%-40s | ERR %s" % (slug, e))
            continue

        t = re.search(r"<title>(.*?)</title>", h, re.S)
        title = t.group(1).split("|")[0].strip() if t else "?"

        # 许可证图标文件名即许可证标识
        lic = sorted(set(re.findall(r"license_images/([A-Za-z0-9_\-]+)\.png", h)))

        # 作者
        a = re.search(r'Author:\s*(?:&nbsp;)*\s*<a href="/users/[^"]+">([^<]+)</a>', h)
        author = a.group(1).strip() if a else "?"

        # 音频文件与大小
        audio = re.findall(r'href="([^"]+\.(?:ogg|mp3|wav|flac))"', h)
        audio = [x for x in audio if "/styles/" not in x]
        size = re.search(r'([\d\.]+)\s*(Mb|Kb|MB|KB)', h)
        size_s = size.group(0) if size else "?"

        # 下载次数
        dl = re.search(r"\[([\d,]+)\s*download", h)
        dls = dl.group(1) if dl else "?"

        print("\n=== %s" % title[:70])
        print("    slug    : %s" % slug)
        print("    license : %s" % (", ".join(lic) if lic else "未找到(需人工看)"))
        print("    author  : %s" % author)
        print("    size    : %s   downloads: %s" % (size_s, dls))
        print("    audio   : %s" % (audio[:2] if audio else "-"))


main()
