# -*- coding: utf-8 -*-
"""把 Tavily MCP 追加进 DSH profile 的 cordis.patch.yml。

为什么不用 edit 工具：上一次写入时，中文注释行的换行被吞掉，
多行注释挤成一行，最后 `- insert:` 也被拼到注释尾部，YAML 直接废掉。
用 Python 显式写 '\\n' 就不会有这个问题。

幂等：已经存在 tavily-mcp 就什么都不做。
"""
import io
import sys

PATH = r"C:\Users\WY157\.dsh\profiles\desktop\cordis.patch.yml"
KEY = "tvly-31rJib-cWV6a4tjprBN9CJVCfdCMzNiUwbyyq9URcj5cBmcST"

BLOCK = """
# Tavily 搜索（MCP，stdio + npx）。
# 上面那个内置 provider（web-search-deepseek）保持禁用：它要求端点支持
# Anthropic 原生 web_search_20250305 服务器工具，而 ciallo 中转站会静默
# 丢弃该工具声明（实测模型自述「我没有搜索工具」），每次调用必然失败。
# Tavily 走独立 MCP 工具，不依赖 provider 白名单。
# 密钥放 env，不写进其它地方。
- insert:
    - id: tavily-mcp
      name: "@deepseek-ai/dsh-mcp-client"
      config:
        serverName: tavily
        transport: stdio
        command: cmd.exe
        args:
          - /d
          - /c
          - npx
          - -y
          - tavily-mcp@latest
        env:
          TAVILY_API_KEY: "{key}"
""".format(key=KEY)

with io.open(PATH, "r", encoding="utf-8", newline="") as fh:
    src = fh.read()

if "tavily-mcp" in src:
    print("already present, nothing to do")
    sys.exit(0)

if not src.endswith("\n"):
    src += "\n"

src += BLOCK

with io.open(PATH, "w", encoding="utf-8", newline="") as fh:
    fh.write(src)

print("ok: appended %d bytes, total %d bytes" % (len(BLOCK.encode()), len(src.encode())))
