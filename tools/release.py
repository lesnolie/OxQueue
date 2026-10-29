"""Record changes and build an addon release only when its changelog is current."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]


def source_files(root):
    files = [root / "AGENTS.md"]
    for folder in ("OxQueue", "tools", "tests"):
        files.extend(p for p in (root / folder).rglob("*")
                     if p.is_file() and "__pycache__" not in p.parts
                     and p.suffix not in (".pyc", ".zip"))
    return sorted(files, key=lambda p: p.relative_to(root).as_posix())


def fingerprint(root):
    digest = hashlib.sha256()
    for file in source_files(root):
        name = file.relative_to(root).as_posix().encode("utf-8")
        content = file.read_bytes()
        digest.update(len(name).to_bytes(8, "big") + name)
        digest.update(len(content).to_bytes(8, "big") + content)
    return digest.hexdigest()


def version(root):
    toc = (root / "OxQueue/OxQueue.toc").read_text(encoding="utf-8")
    lua = (root / "OxQueue/OxQueue.lua").read_text(encoding="utf-8")
    a = re.search(r"^## Version:\s*(\d+\.\d+\.\d+)\s*$", toc, re.M)
    b = re.search(r'local VERSION = "(\d+\.\d+\.\d+)"', lua)
    if not a or not b or a[1] != b[1]:
        raise ValueError("TOC and Lua versions must match.")
    return a[1]


def history(root):
    return json.loads((root / "CHANGELOG.json").read_text(encoding="utf-8"))


def markdown(entries):
    lines = ["# OxQueue 更新日志 / Changelog", ""]
    for entry in entries:
        lines.extend([f"## {entry['version']} - {entry['date']}", ""])
        lines.extend(f"- {note}" for note in entry["zh"])
        lines.append("")
        lines.extend(f"- {note}" for note in entry["en"])
        lines.extend(["", "验证 / Validation:", ""])
        lines.extend(f"- {note}" for note in entry["verified"])
        lines.append("")
    return "\n".join(lines)


def record(root, notes, english, verified):
    if any(not note.strip() for note in [*notes, *english, *verified]):
        raise ValueError("Change notes and validation results cannot be blank.")
    entries = history(root)
    entry = {
        "version": version(root),
        "date": datetime.now(ZoneInfo("Asia/Singapore")).date().isoformat(),
        "zh": notes, "en": english, "verified": verified,
        "source_sha256": fingerprint(root),
    }
    entries.insert(0, entry)
    (root / "CHANGELOG.json").write_text(
        json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (root / "CHANGELOG.md").write_text(markdown(entries), encoding="utf-8")
    return entry


def check(root):
    entries = history(root)
    if not entries or entries[0].get("version") != version(root):
        raise ValueError("The latest changelog must match the addon version.")
    if entries[0].get("source_sha256") != fingerprint(root):
        raise ValueError("Files changed without a matching changelog. Run the record command first.")
    if (root / "CHANGELOG.md").read_text(encoding="utf-8") != markdown(entries):
        raise ValueError("CHANGELOG.md differs from CHANGELOG.json. Run record to regenerate it.")
    return entries[0]


def build(root):
    entry = check(root)
    for test in ("check.py", "test_release.py"):
        subprocess.run([sys.executable, str(root / "tests" / test)], cwd=root, check=True)
    check(root)
    target = root / f"OxQueue-{entry['version']}.zip"
    # Finish the archive before copying it to either release download.
    with tempfile.TemporaryDirectory(prefix="oxqueue-release-") as temporary:
        staged = Path(temporary) / target.name
        with zipfile.ZipFile(staged, "w", zipfile.ZIP_DEFLATED) as archive:
            for file in source_files(root):
                if file.is_relative_to(root / "OxQueue"):
                    archive.write(file, file.relative_to(root).as_posix())
            for name in ("CHANGELOG.json", "CHANGELOG.md"):
                archive.write(root / name, f"OxQueue/{name}")
        shutil.copyfile(staged, target)
        shutil.copyfile(staged, root / "OxQueue.zip")
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    note = commands.add_parser("record", help="Save change notes and the current source fingerprint")
    note.add_argument("--note", action="append", required=True)
    note.add_argument("--note-en", action="append", required=True)
    note.add_argument("--verified", action="append", required=True)
    commands.add_parser("check", help="Reject unlogged source changes")
    commands.add_parser("build", help="Check notes, run addon tests and build the ZIP")
    args = parser.parse_args()
    try:
        if args.command == "record":
            entry = record(ROOT, args.note, args.note_en, args.verified)
            print(f"Saved changelog for {entry['version']}.")
        elif args.command == "check":
            print(f"Changelog matches {check(ROOT)['version']} and current source.")
        else:
            print(f"Built {build(ROOT)}")
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release blocked: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
