import pathlib
import sys

page = pathlib.Path(sys.argv[1])
html = page.read_text(encoding="utf-8")
marker = "<!-- mobile-immersive -->"
if marker in html:
    sys.exit(0)

snippet = (
    '<meta name="mobile-web-app-capable" content="yes">\n'
    '<meta name="apple-mobile-web-app-capable" content="yes">\n'
    '<meta name="theme-color" content="#050a16">\n'
    '<!-- mobile-immersive -->\n'
    '<script src="./mobile_immersive.js" defer></script>\n'
)
if "</head>" in html:
    html = html.replace("</head>", snippet + "</head>", 1)
else:
    html = snippet + html
page.write_text(html, encoding="utf-8")
