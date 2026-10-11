#!/usr/bin/env python3
"""run_lua.py <script.lua> [args...]

Runs a Lua 5.4 script with the lupa package (pip install lupa), for the
offline tests in this folder when no standalone Lua is installed. The
script's directory is put on package.path.
"""
import os, sys
from lupa import lua54

def main():
    script = sys.argv[1]
    rt = lua54.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()
    g.arg = rt.table_from(dict(enumerate(sys.argv[2:], 1)))
    folder = os.path.dirname(os.path.abspath(script)).replace("\\", "/")
    rt.execute('package.path = "%s/?.lua;" .. package.path' % folder)
    with open(script, encoding="utf-8") as f:
        rt.execute(f.read())

if __name__ == "__main__":
    main()
