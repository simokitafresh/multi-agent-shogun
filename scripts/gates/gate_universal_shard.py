#!/usr/bin/env python3
import runpy, sys
from pathlib import Path
sys.argv.append("--plan") if len(sys.argv) == 2 else None
runpy.run_path(str(Path(__file__).parents[1] / "universal_shard.py"), run_name="__main__")
