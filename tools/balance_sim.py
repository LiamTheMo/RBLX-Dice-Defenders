# usage: python tools/balance_sim.py [seeds]   (runs tools/balance_sim.luau; needs the `luau` CLI)
import subprocess, sys, tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests" / "luau"))
import run

spec = Path(__file__).with_name("balance_sim.luau")
seeds = sys.argv[1] if len(sys.argv) > 1 else "40"
with tempfile.TemporaryDirectory() as t:
    b = Path(t) / "b.luau"
    b.write_text("__SEEDS = " + str(int(seeds)) + "\n" + run.build_bundle(spec), encoding="utf-8")
    r = subprocess.run(["luau", str(b)], capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
