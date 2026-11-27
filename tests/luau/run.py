#!/usr/bin/env python3
"""Run the headless Luau specs under tests/luau.

Adapted from RBLX-Flintborn's tests/luau/run.py (same owner). Game modules are
written for Roblox: they `require(script.Parent.X)` and use Roblox datatypes.
Each spec runs as one generated bundle: prelude.luau (datatype stubs, a fake
instance tree and a require that resolves it), then every module under
src/shared, src/server and src/client as a loader function (only required
modules run), then the spec itself.

Only pure-logic modules are testable this way; anything touching Instances,
services or the network still needs a Studio playtest.

    python tests/luau/run.py                  # run every *.spec.luau with the `luau` CLI (failures print in full)
    python tests/luau/run.py -v               # also print every passing case
    python tests/luau/run.py --bundle NAME    # print one spec's bundle (e.g. to run in Studio)

The `luau` CLI (tested with 0.746, from github.com/luau-lang/luau releases) must be
on PATH; Aftman cannot pin it. Without it, print a bundle
and run it in Studio's command bar or through the Studio MCP.
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent

# Rojo mount points, keyed by the instance path game code sees.
MOUNTS = {
    ("ReplicatedStorage", "Shared"): ROOT / "src" / "shared",
    ("ServerScriptService", "Server"): ROOT / "src" / "server",
    # Client presentation data some specs cross-check (e.g. a colour per rarity).
    ("StarterPlayer", "StarterPlayerScripts", "Client"): ROOT / "src" / "client",
    ("ServerStorage", "TestSupport"): HERE / "support",
}


def module_entries(include_scripts: bool = False):
    entries = []
    for prefix, folder in MOUNTS.items():
        if not folder.is_dir():
            continue
        for file in sorted(folder.rglob("*.luau")):
            # Entry-point scripts are not requirable modules (only scanned as text).
            if file.name.endswith((".server.luau", ".client.luau")) and not include_scripts:
                continue
            parts = list(file.relative_to(folder).with_suffix("").parts)
            if parts[-1] == "init":
                parts = parts[:-1]
            entries.append((list(prefix) + parts, file.read_text(encoding="utf-8")))
    return entries


def long_string(text: str) -> str:
    level = 0
    while "]" + "=" * level + "]" in text + "]":  # + "]": text may end in "]="
        level += 1
    return "[" + "=" * level + "[\n" + text + "]" + "=" * level + "]"


def build_bundle(spec: Path) -> str:
    spec_source = spec.read_text(encoding="utf-8")
    entries = module_entries()
    chunks = [(HERE / "prelude.luau").read_text(encoding="utf-8")]
    for path, source in entries:
        chunks.append(
            "__defineModule({path}, function(script)\n{source}\nend)\n".format(
                path="{" + ", ".join(json.dumps(p) for p in path) + "}",
                source=source,
            )
        )
    if "__sources" in spec_source:
        # Specs that scan the tree (e.g. for server-only data reaching clients) get
        # every module's and entry script's text as __sources["ReplicatedStorage/Shared/..."].
        rows = [
            "[{}] = {},".format(json.dumps("/".join(path)), long_string(source))
            for path, source in module_entries(include_scripts=True)
        ]
        chunks.append("__sources = {\n" + "\n".join(rows) + "\n}\n")
    chunks.append(
        "__runSpec({name}, function()\n{source}\nend)\n".format(name=json.dumps(spec.name), source=spec_source)
    )
    return "\n".join(chunks)


def main() -> int:
    args = sys.argv[1:]
    verbose = "-v" in args
    args = [a for a in args if a != "-v"]
    specs = sorted(HERE.glob("*.spec.luau"))  # tests/_archive/ is outside HERE and never run

    if len(args) == 2 and args[0] == "--bundle":
        matches = [s for s in specs if s.name.startswith(args[1])]
        if len(matches) != 1:
            print(f"Expected one spec matching {args[1]!r}, found {len(matches)}", file=sys.stderr)
            return 1
        sys.stdout.write(build_bundle(matches[0]))
        return 0
    if args:
        print(__doc__, file=sys.stderr)
        return 1

    luau = shutil.which("luau")
    if luau is None:
        print("luau CLI not found on PATH (download it from github.com/luau-lang/luau releases; tested with 0.746)", file=sys.stderr)
        return 1
    if not specs:
        print("No specs found", file=sys.stderr)
        return 1

    failed = []
    with tempfile.TemporaryDirectory() as tmp:
        for spec in specs:
            bundle = Path(tmp) / (spec.stem + ".bundle.luau")
            bundle.write_text(build_bundle(spec), encoding="utf-8")
            result = subprocess.run([luau, str(bundle)], capture_output=True, text=True)
            bad = result.returncode != 0 or "SPEC FAILED" in result.stdout
            if bad:
                failed.append(spec.name)
            if bad or verbose:
                sys.stdout.write(result.stdout)
                sys.stderr.write(result.stderr)
            else:
                summary = [l for l in result.stdout.splitlines() if l.startswith(spec.name + ":")]
                print(summary[-1] if summary else f"{spec.name}: ok")

    print(f"{len(specs) - len(failed)}/{len(specs)} spec files passed")
    if failed:
        print("FAILED: " + ", ".join(failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
