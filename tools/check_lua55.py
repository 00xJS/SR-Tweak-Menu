#!/usr/bin/env python3
"""check_lua55.py [folder]

Compiles every .lua file under the mod folder (default SRTweakMenu) with Lua
5.4 and 5.5, the versions the Windows and Mac loaders run. Lua 5.5 refuses,
among other things, assignments to a for-loop variable, which would stop a
file loading on the Mac only. Needs lupa (pip install lupa).
"""
import glob, os, sys
import lupa


def main(folder):
    runtimes = []
    for name in ("lua54", "lua55"):
        try:
            runtimes.append((name, __import__("lupa." + name, fromlist=["LuaRuntime"]).LuaRuntime()))
        except ImportError:
            print(f"{name}: not available in this lupa, skipped")
    bad = 0
    for path in sorted(glob.glob(os.path.join(folder, "**", "*.lua"), recursive=True)):
        src = open(path, encoding="utf-8").read()
        for name, rt in runtimes:
            check = rt.eval("function(src, name) local f, err = load(src, name, 't') return err end")
            err = check(src, "@" + path)
            if err:
                bad += 1
                print(f"{name}: {err}")
    print("OK" if bad == 0 else f"{bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "SRTweakMenu"))
