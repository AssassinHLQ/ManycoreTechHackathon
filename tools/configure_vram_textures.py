"""Keep 3D textures GPU-compressed without rewriting generated source art."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]


def configure(root: Path = ROOT) -> list[str]:
    changed = []
    for path in sorted((root / "assets/models").rglob("*.import")):
        original = path.read_text(encoding="utf-8")
        if 'importer="texture"' not in original:
            continue
        text = re.sub(r"^compress/mode=\d+$", "compress/mode=2", original, flags=re.M)
        text = re.sub(r"^mipmaps/generate=false$", "mipmaps/generate=true", text, flags=re.M)
        text = re.sub(r"^detect_3d/compress_to=\d+$", "detect_3d/compress_to=0", text, flags=re.M)
        # This flat ORM map alone previously occupied 64 MiB with mipmaps.
        if path.relative_to(root).as_posix() == "assets/models/space-station/textures/orm.png.import":
            text = re.sub(r"^process/size_limit=\d+$", "process/size_limit=1024", text, flags=re.M)
        if text != original:
            path.write_text(text, encoding="utf-8", newline="\n")
            changed.append(path.relative_to(root).as_posix())
    return changed


if __name__ == "__main__":
    changed = configure()
    output = ROOT / "_tools/_tmp/vram_import_changes.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(changed, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Configured {len(changed)} texture imports; source images are unchanged.")
