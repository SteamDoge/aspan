# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 ASpan contributors.
"""Verify committed local RC packages without installing or executing the application."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
VERSION = None
PACKAGE_VERSION = None
ABIS = {}
EXPECTED_CERTIFICATE = "fcf45ba4f79778a536b26cb8493fca7d132cc367bf0fe44aa8a7d10dcb32c1de"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(command):
    # Argument arrays and shell=False preserve spaces without cmd/batch escaping.
    result = subprocess.run(command, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", check=False,
                            timeout=120, shell=False)
    require(result.returncode == 0,
            f"{Path(command[0]).name} failed with exit code {result.returncode}")
    return result.stdout


def check_archive(archive):
    # ZipInfo normalizes backslashes on Windows; inspect the original names too.
    names = [info.orig_filename for info in archive.infolist()]
    require(len(names) == len({name.casefold() for name in names}), "Archive contains duplicate paths")
    for name in names:
        path = PurePosixPath(name)
        require(not path.is_absolute() and ".." not in path.parts
                and "\\" not in name and ":" not in name and "\0" not in name,
                "Archive contains an unsafe path")
        require("integration_test" not in name.lower()
                and not name.lower().endswith(".pdb")
                and not name.endswith("kernel_blob.bin"),
                f"Development artifact in package: {name}")
    require(archive.testzip() is None, "Archive CRC check failed")
    return set(names)


def check_templates(archive, name):
    data = archive.read(name)
    templates = json.loads(data)
    require(isinstance(templates, list) and len(templates) == 23,
            "Expected 23 built-in presets")
    names = [item["name"] for item in templates]
    require(len(set(names)) == 23, "Preset names are not unique")
    require(not {"吃药", "待办"}.intersection(names[:2]),
            "Medicine or todo was placed at the front")
    birthday = next((item for item in templates if item["name"] == "生日"), None)
    require(birthday is not None and birthday.get("cycle") == "yearly"
            and birthday.get("icon") == "birthday", "Birthday preset is missing or invalid")
    source = json.loads((ROOT / "apps/aspan/assets/templates.json").read_text("utf-8-sig"))
    require(templates == source, "Packaged presets differ from source")
    return {"count": len(templates), "names": names, "sha256": digest(data)}


def check_windows(path):
    with zipfile.ZipFile(path) as archive:
        names = check_archive(archive)
        required = {"aspan.exe", "aspan_bridge.dll", "flutter_windows.dll",
                    "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll",
                    "data/app.so", "data/icudtl.dat",
                    "data/flutter_assets/assets/templates.json",
                    "data/flutter_assets/shaders/navigation_glass.frag"}
        require(required <= names, "Windows bundle is missing required executable/runtime/data files")
        for name in ("aspan.exe", "aspan_bridge.dll", "flutter_windows.dll",
                     "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"):
            data = archive.read(name)
            require(data[:2] == b"MZ" and len(data) >= 64, f"Invalid PE file: {name}")
            offset = int.from_bytes(data[60:64], "little")
            require(data[offset:offset + 4] == b"PE\0\0"
                    and int.from_bytes(data[offset + 4:offset + 6], "little") == 0x8664,
                    f"Expected Windows x64 binary: {name}")
        allowed = required | {"dartjni.dll", "file_selector_windows_plugin.dll",
                              "data/flutter_assets/AssetManifest.bin", "data/flutter_assets/FontManifest.json",
                              "data/flutter_assets/NativeAssetsManifest.json", "data/flutter_assets/NOTICES.Z",
                              "data/flutter_assets/fonts/MaterialIcons-Regular.otf",
                              "data/flutter_assets/shaders/ink_sparkle.frag", "data/flutter_assets/shaders/stretch_effect.frag"}
        require(names == allowed, f"Windows bundle file set differs from current dependencies: {names ^ allowed}")
        bridge = archive.read("aspan_bridge.dll")
        for symbol in (b"aspan_invoke_json", b"aspan_free_json"):
            require(symbol in bridge, "Windows bridge ABI symbol is missing")
        require(digest(bridge) == file_digest(ROOT / "target/release/aspan_bridge.dll"),
                "Packaged Windows bridge differs from the release build")
        return {"platform": "windows-x64", "crc": "passed", "required_files": sorted(required),
                "bridge_sha256": digest(bridge),
                "presets": check_templates(archive, "data/flutter_assets/assets/templates.json")}


def java_executable(value):
    path = Path(value)
    if path.is_dir():
        direct = path / ("java.exe" if os.name == "nt" else "java")
        path = direct if direct.is_file() else path / "bin" / direct.name
    require(path.is_file(), "--java must identify an existing JDK root, bin directory or java executable")
    return path


def check_android(path, abi, args):
    require(args.sdk and args.java, "Android verification requires --sdk and --java")
    build_tools = Path(args.sdk) / "build-tools" / args.build_tools
    aapt = Path(args.aapt) if args.aapt else build_tools / ("aapt.exe" if os.name == "nt" else "aapt")
    signer = Path(args.apksigner) if args.apksigner else build_tools / "lib/apksigner.jar"
    require(aapt.is_file() and signer.is_file(), "Existing aapt and apksigner.jar are required")
    signed = run([str(java_executable(args.java)), "-jar", str(signer), "verify",
                  "--verbose", "--print-certs", str(path)])
    require(re.search(r"^Verifies\s*$", signed, re.MULTILINE), "APK signature did not verify")
    require("Verified using v2 scheme (APK Signature Scheme v2): true" in signed,
            "APK Signature Scheme v2 verification failed")
    certificates = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F:]+)\s*$",
                              signed, re.MULTILINE)
    identities = re.findall(r"^Signer #\d+ certificate DN: (.+)$", signed, re.MULTILINE)
    require(len(certificates) == len(identities) == 1, "Expected one APK signing certificate")
    require("android debug" not in identities[0].lower(), "APK is signed with an Android Debug identity")
    require(certificates[0].replace(":", "").lower() == EXPECTED_CERTIFICATE,
            "APK certificate differs from the independently signed rc0.0.1 release")
    badging = run([str(aapt), "dump", "badging", str(path)])
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'",
                        badging, re.MULTILINE)
    require(package is not None, "APK package metadata is missing")
    rust_target, machine, version_code = ABIS[abi]
    require(package.groups() == ("cn.aquantum.aspan", str(version_code), PACKAGE_VERSION),
            "APK package name or version does not match this RC")
    require(re.search(r"^sdkVersion:'24'\s*$", badging, re.MULTILINE), "APK minSdk must be 24")
    require("application-debuggable" not in badging, "APK is debuggable")
    xml = run([str(aapt), "dump", "xmltree", str(path), "AndroidManifest.xml"])
    for line in xml.splitlines():
        if "android:debuggable" in line:
            value = re.search(r"=\s*\(type 0x12\)0x([0-9a-fA-F]+)", line)
            require(value is not None and int(value.group(1), 16) == 0, "APK manifest enables debugging")
    require(re.search(r"android:allowBackup[^\n]*=\s*\(type 0x12\)0x0(?:\s|$)", xml) is not None,
            "APK must explicitly disable Android Auto Backup")
    require("android:dataExtractionRules" in xml and "android:fullBackupContent" in xml,
            "APK must include cloud and device-transfer exclusions")
    with zipfile.ZipFile(path) as archive:
        names = check_archive(archive)
        packaged_abis = {name.split("/")[1] for name in names
                         if name.startswith("lib/") and name.endswith(".so")}
        require(packaged_abis == {abi}, "APK must contain only its named ABI")
        require({f"lib/{abi}/libapp.so", f"lib/{abi}/libflutter.so",
                 f"lib/{abi}/libaspan_bridge.so"} <= names, "APK is missing Release native libraries")
        require("assets/flutter_assets/shaders/navigation_glass.frag" in names,
                "APK is missing the navigation glass shader")
        bridge = archive.read(f"lib/{abi}/libaspan_bridge.so")
        require(bridge[:6] == b"\x7fELF\x02\x01"
                and int.from_bytes(bridge[18:20], "little") == machine,
                "Android bridge has an invalid ELF architecture")
        for symbol in (b"aspan_invoke_json", b"aspan_free_json"):
            require(symbol in bridge, "Android bridge ABI symbol is missing")
        source = ROOT / "target/android" / rust_target / "release/libaspan_bridge.so"
        source_hash = file_digest(source)
        # Android Gradle applies llvm-strip even to a Cargo-stripped library.
        # Reproduce that transform instead of mistaking ELF metadata changes for
        # a different native build. This disposable output inherits the same
        # Low integrity as the existing shared NDK used by release.ps1.
        strip = Path(args.sdk) / "ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe"
        require(strip.is_file(), "Existing NDK llvm-strip is required")
        with tempfile.TemporaryDirectory(prefix="verify-strip-", dir=ROOT / "target/android") as temporary:
            stripped = Path(temporary) / "libaspan_bridge.so"
            run([str(strip), "--strip-unneeded", "-o", str(stripped), str(source)])
            require(digest(bridge) == file_digest(stripped),
                    "Packaged Android bridge differs from the independently stripped release build")
        return {"platform": f"android-{abi}", "crc": "passed", "package": package[1],
                "version_code": version_code, "version_name": package[3], "min_sdk": 24,
                "debuggable": False, "signature_v2": "verified", "certificate_dn": identities[0].strip(),
                "certificate_sha256": certificates[0].replace(":", "").lower(),
                "bridge_sha256": digest(bridge),
                "cargo_bridge_sha256": source_hash,
                "native_transform": "NDK llvm-strip --strip-unneeded reproduced byte-for-byte",
                "presets": check_templates(archive, "assets/flutter_assets/assets/templates.json")}


def verify(args):
    global VERSION, PACKAGE_VERSION, ABIS
    delivery = Path(args.delivery).resolve()
    manifest = json.loads((delivery / "manifest.json").read_text("utf-8-sig"))
    source = run(["git", "-C", str(ROOT), "show", f"{manifest.get('commit', '')}:apps/aspan/pubspec.yaml"])
    version = re.search(r"^version: (([0-9]+\.[0-9]+\.[0-9]+)-rc\.1)\+([1-9][0-9]*)\s*$", source, re.MULTILINE)
    require(version is not None, "Committed pubspec must contain an RC version and build")
    PACKAGE_VERSION, numeric_version, build = version.groups()
    VERSION = f"rc{numeric_version}"
    build = int(build)
    ABIS = {"arm64-v8a": ("aarch64-linux-android", 183, 2000 + build),
            "x86_64": ("x86_64-linux-android", 62, 4000 + build)}
    require(manifest.get("version") == VERSION and manifest.get("package_version") == PACKAGE_VERSION
            and manifest.get("build_number") == build and manifest.get("kind") == "release-candidate",
            "Manifest differs from committed package version")
    tag = manifest.get("tag", "")
    require(tag == f"{VERSION}-build.{build}" and re.fullmatch(r"[0-9a-f]{40}", manifest.get("commit", "")),
            "Manifest source identity is missing")
    commit = run(["git", "-C", str(ROOT), "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}"])
    require(commit.strip() == manifest["commit"], "Release tag differs from manifest commit")
    expected = set()
    platform = manifest.get("platform")
    require(platform in ("windows", "android", "all"), "Unknown manifest platform")
    if platform in ("windows", "all"):
        expected.add(f"ASpan-{VERSION}-windows-x64.zip")
    if platform in ("android", "all"):
        expected.update(f"ASpan-{VERSION}-android-{abi}.apk" for abi in ABIS)
    entries = manifest.get("artifacts", [])
    require(len(entries) == len(expected) and {entry["name"] for entry in entries} == expected,
            "Manifest artifact set is incomplete or unexpected")
    results = []
    for entry in entries:
        path = delivery / entry["name"]
        require(path.is_file() and path.stat().st_size == entry["bytes"], "Artifact is missing or size differs")
        sha256 = file_digest(path)
        require(sha256 == entry["sha256"].lower(), f"SHA-256 mismatch: {path.name}")
        if path.suffix == ".zip":
            result = check_windows(path)
        else:
            abi = next(abi for abi in ABIS if path.name == f"ASpan-{VERSION}-android-{abi}.apk")
            result = check_android(path, abi, args)
        results.append({"name": path.name, "bytes": path.stat().st_size, "sha256": sha256, **result})
    certificates = {item["certificate_sha256"] for item in results if "certificate_sha256" in item}
    require(len(certificates) <= 1, "Android APKs use different signing certificates")
    return {"ok": True, "scope": "static package verification; runtime acceptance is recorded separately",
            "version": VERSION, "commit": manifest["commit"], "tag": tag,
            "checked_at": datetime.now(timezone.utc).isoformat(), "artifacts": results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("delivery", help="Delivery directory containing manifest.json")
    parser.add_argument("--sdk", help="Existing Android SDK root")
    parser.add_argument("--java", help="Existing JDK root, bin directory or java executable")
    parser.add_argument("--build-tools", default="36.0.0")
    parser.add_argument("--aapt", help="Override aapt executable path")
    parser.add_argument("--apksigner", help="Override apksigner.jar path (not the batch wrapper)")
    args = parser.parse_args()
    if sys.version_info < (3, 11):
        parser.error("Python 3.11 or later is required")
    try:
        report = verify(args)
    except Exception as error:
        report = {"ok": False, "checked_at": datetime.now(timezone.utc).isoformat(),
                  "error": str(error)}
    output = Path(args.delivery).resolve() / "verification-package.json"
    if output.exists():
        previous = output.with_name(f"verification-package-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')}.json")
        previous.write_bytes(output.read_bytes())
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Package verification: {'PASSED' if report['ok'] else 'FAILED'}; {output}")
    if not report["ok"]:
        print(report["error"], file=sys.stderr)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
