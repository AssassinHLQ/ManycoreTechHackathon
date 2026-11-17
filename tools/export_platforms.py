"""Build desktop/Web releases and an Android test APK without opening windows."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
LOGS = ROOT / "_tools" / "_tmp"
TARGETS = {
    "windows": ("Windows Desktop", "game.exe"),
    "linux": ("Linux", "game.x86_64"),
    "web": ("Web", "index.html"),
    "android": ("Android", "game-debug.apk"),
}
NOTICES = ["THIRD_PARTY_NOTICES.md", "LICENSE", "assets/models/LICENSE_MANIFEST.json",
           "assets/licenses/godot-MIT.txt", "assets/licenses/GODOT_THIRD_PARTY.txt",
           "assets/licenses/OFL-LXGWWenKai.txt", "assets/licenses/OFL-NotoSansSymbols2.txt"]
HIDDEN = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
ERRORS = re.compile(r"^(?:SCRIPT ERROR:|ERROR:|FAIL\b).*$", re.M)


def run(label, command, timeout=600, expected=None, env=None):
    log_path = LOGS / ("platform_" + label + ".log")
    started = time.monotonic()
    print("Running " + label, flush=True)
    with log_path.open("w", encoding="utf-8") as log:
        proc = subprocess.run([str(part) for part in command], cwd=ROOT, env=env,
                              stdout=log, stderr=subprocess.STDOUT,
                              creationflags=HIDDEN, timeout=timeout)
    output = log_path.read_text(encoding="utf-8", errors="replace")
    errors = ERRORS.findall(output)
    if proc.returncode or errors or (expected and expected not in output):
        raise RuntimeError(f"{label}: exit={proc.returncode}, errors={errors[:5]}; see {log_path}")
    return {"log": str(log_path), "seconds": round(time.monotonic() - started, 1),
            "exit_code": proc.returncode}


def validate_android(path, sdk, java):
    with zipfile.ZipFile(path) as apk:
        if apk.testzip() is not None:
            raise RuntimeError("Android APK has a damaged ZIP member")
        names = apk.namelist()
        for notice in NOTICES:
            if apk.read("assets/" + notice) != (ROOT / notice).read_bytes():
                raise RuntimeError("Android notice differs: " + notice)
        if "lib/arm64-v8a/libgodot_android.so" not in names:
            raise RuntimeError("Android ARM64 engine is missing")
        if not any(name.endswith((".etc2.ctex", ".astc.ctex")) for name in names):
            raise RuntimeError("Android GPU-compressed mobile textures are missing")
        for scene in (ROOT / "assets/runtime_bakes").glob("*.scn"):
            if "assets/assets/runtime_bakes/" + scene.name not in names:
                raise RuntimeError("Android runtime snapshot is missing: " + scene.name)
        for folder in ["tests/", "tools/", "_tools/", "build/", "captures/", "demo/"]:
            if any(name.startswith("assets/" + folder) for name in names):
                raise RuntimeError("Android includes development files: " + folder)
    versions = sorted((sdk / "build-tools").iterdir(),
                      key=lambda p: tuple(int(n) for n in re.findall(r"\d+", p.name)))
    build_tools = versions[-1]
    env = dict(os.environ, JAVA_HOME=str(java))
    if os.name == "nt":
        signer = [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", str(build_tools / "apksigner.bat")]
    else:
        signer = [build_tools / "apksigner"]
    result = run("android_signature", signer + ["verify", "--verbose", "--print-certs", path], env=env)
    metadata = run("android_metadata", [build_tools / ("aapt.exe" if os.name == "nt" else "aapt"),
                                       "dump", "badging", path])
    output = Path(metadata["log"]).read_text(encoding="utf-8")
    if "org.starwardwilds.sunnywindow" not in output or "native-code: 'arm64-v8a'" not in output:
        raise RuntimeError("Android package identity or architecture differs")
    result["metadata"] = metadata
    result["kind"] = "debug-signed test APK; device gameplay not verified"
    return result


def archive_target(target, directory):
    if target == "linux":
        path = BUILD / "SunnyWindow-Linux-x86_64.tar.gz"
        with tarfile.open(path, "w:gz") as bundle:
            for source in sorted(directory.rglob("*")):
                info = bundle.gettarinfo(source, arcname=str(source.relative_to(directory)))
                if source.name == "game.x86_64":
                    info.mode = 0o755
                if source.is_file():
                    with source.open("rb") as data:
                        bundle.addfile(info, data)
        with tarfile.open(path) as bundle:
            if not bundle.getmember("game.x86_64").mode & 0o111:
                raise RuntimeError("Linux archive lost the executable bit")
            for member in bundle.getmembers():
                with bundle.extractfile(member) as data:
                    while data.read(1024 * 1024):
                        pass
    else:
        label = {"windows": "Windows", "web": "Web"}[target]
        path = BUILD / ("SunnyWindow-" + label + ".zip")
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
            for source in sorted(directory.rglob("*")):
                if source.is_file() and source.suffix != ".import":
                    bundle.write(source, arcname=str(source.relative_to(directory)))
        with zipfile.ZipFile(path) as bundle:
            if bundle.testzip() is not None:
                raise RuntimeError("Archive CRC verification failed: " + str(path))
    with path.open("rb") as data:
        return {"path": str(path), "bytes": path.stat().st_size,
                "sha256": hashlib.file_digest(data, "sha256").hexdigest()}


def file_record(path, directory):
    with path.open("rb") as data:
        return {"name": str(path.relative_to(directory)), "bytes": path.stat().st_size,
                "sha256": hashlib.file_digest(data, "sha256").hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platforms", nargs="*", choices=list(TARGETS), default=list(TARGETS))
    parser.add_argument("--godot", default=os.environ.get("GODOT") or shutil.which("godot")
                        or r"D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe")
    parser.add_argument("--skip-bake", action="store_true", help="Only after a successful bake of these sources")
    parser.add_argument("--skip-tests", action="store_true", help="Only after source tests passed for these sources")
    parser.add_argument("--archives", action="store_true", help="Also create portable desktop/Web archives")
    parser.add_argument("--android-sdk", type=Path, default=Path(os.environ.get("ANDROID_HOME")
                        or Path.home() / "AppData/Local/Android/Sdk"))
    parser.add_argument("--java-sdk", type=Path, default=Path(os.environ.get("JAVA_HOME", "")))
    args = parser.parse_args()
    LOGS.mkdir(parents=True, exist_ok=True)
    BUILD.mkdir(exist_ok=True)
    report_path = BUILD / "platform-validation.json"
    report = {"source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT,
              creationflags=HIDDEN, text=True).strip(), "exports": {}, "success": False,
              "source_sha256": {str(p.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest()
                  for folder in ["scripts", "shaders", "scenes"] for p in (ROOT / folder).rglob("*")
                  if p.suffix in [".gd", ".gdshader", ".tscn", ".tres"]}}
    for name in ["project.godot", "export_presets.cfg", "default_bus_layout.tres", *NOTICES]:
        report["source_sha256"][name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    if report_path.is_file():
        previous = json.loads(report_path.read_text(encoding="utf-8"))
        if previous.get("source_commit") == report["source_commit"] and previous.get("source_sha256") == report["source_sha256"]:
            report.update({key: previous[key] for key in ["exports", "tests", "bake"] if key in previous})
    engine = [args.godot, "--headless", "--path", ROOT]
    try:
        if not args.skip_bake:
            report["bake"] = run("bake", engine + ["--script", "res://tools/bake_runtime_assets.gd",
                "--", "--no-capture", "--rebake-runtime"], expected="RUNTIME BAKE COMPLETE")
        report["import"] = run("import", engine + ["--editor", "--import"])
        if not args.skip_tests:
            report["tests"] = {name: run(name, engine + ["--script", f"res://tests/{name}.gd", "--", "--no-capture"])
                               for name in ["smoke_test", "font_coverage_test", "touch_test", "runtime_bake_test"]}
        for target in args.platforms:
            report["exports"].pop(target, None)
            preset, filename = TARGETS[target]
            directory = BUILD / target
            directory.mkdir(exist_ok=True)
            entry = directory / filename
            mode = "--export-debug" if target == "android" else "--export-release"
            result = run("export_" + target, engine + [mode, preset, entry], timeout=1200)
            if not entry.is_file():
                raise RuntimeError("Export did not produce " + str(entry))
            if target == "web":
                for name in ["mobile_immersive.js", "sw.js"]:
                    shutil.copy2(ROOT / "web_mobile" / name, directory / name)
                run("web_inject", [sys.executable, ROOT / "web_mobile/inject_immersive.py", entry])
                run("web_cache_test", ["node", ROOT / "tests/web_cache_test.mjs"])
            if target == "android":
                result["validation"] = validate_android(entry, args.android_sdk, args.java_sdk)
            else:
                pack = directory / "index.pck" if target == "web" else directory / "game.pck"
                if target == "windows":
                    pack = entry
                if target == "linux":
                    with entry.open("rb") as binary:
                        header = binary.read(20)
                    if header[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", header, 18)[0] != 62:
                        raise RuntimeError("Linux output is not an x86-64 ELF executable")
                    result["native_runtime"] = "not run; a Linux host is required"
                result["package_check"] = run("package_" + target, [args.godot, "--headless", "--main-pack", pack,
                    "--path", directory, "--script", ROOT / "tests/export_package_test.gd", "--", "--no-capture"],
                    expected="EXPORT PACKAGE COMPLETE:")
                if target == "windows":
                    result["native_runtime"] = run("windows_boot", [entry, "--headless", "--audio-driver", "Dummy",
                        "--max-fps", "60", "--quit-after", "1800", "--", "--no-capture"],
                        expected="\u884c\u661f\u603b\u6570 20")
                if target == "web":
                    result["browser"] = run("web_browser", ["node", ROOT / "tests/web_export_test.mjs",
                        directory, LOGS / "web_export"], expected="WEB EXPORT TEST COMPLETE:")
            for notice in NOTICES:
                destination = directory / notice
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / notice, destination)
            if args.archives and target != "android":
                result["archive"] = archive_target(target, directory)
            result["entry"] = str(entry)
            result["files"] = [file_record(p, directory)
                               for p in sorted(directory.iterdir()) if p.is_file()]
            report["exports"][target] = result
            report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
            print("Verified " + target, flush=True)
        report["success"] = True
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print("Report: " + str(report_path), flush=True)


if __name__ == "__main__":
    main()
