"""Run the balance simulator: python tools/balance_sim.py [seeds] [name filter]   (default 40; runs tools/balance_sim.luau, needs the `luau` CLI)."""
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests" / "luau"))
import run  # noqa: E402


def main() -> None:
    spec = Path(__file__).with_name("balance_sim.luau")
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 40
    only = sys.argv[2] if len(sys.argv) > 2 else ""
    with tempfile.TemporaryDirectory() as t:
        b = Path(t) / "b.luau"
        b.write_text(f"__SEEDS = {seeds}\n__ONLY = {only!r}\n" + run.build_bundle(spec), encoding="utf-8")
        r = subprocess.run(["luau", str(b)], capture_output=True, text=True)
        sys.stdout.write(r.stdout)
        sys.stderr.write(r.stderr)


if __name__ == "__main__":
    main()
