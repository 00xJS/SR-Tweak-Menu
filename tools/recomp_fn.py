#!/usr/bin/env python3
"""recomp_fn.py <generated dir> <image.bin> sub_XXXXXXXX [max lines]

Prints the PowerPC of one recompiled game function (from the comments in
build/generated/saintsrow_recomp.*.cpp) with lis/addi address constants
resolved, and the string at that address when there is one. image.bin
comes from xex_image.py. Handy for following a script function's wrapper
(see script_functions.txt) into the game code.
"""
import glob, re, sys

def asm_of(gen, name):
    for f in sorted(glob.glob(gen + "/saintsrow_recomp.*.cpp")):
        text = open(f).read()
        i = text.find("DEFINE_REX_FUNC(%s)" % name)
        if i < 0: continue
        body = text[i:text.find("\nDEFINE_REX_FUNC", i + 1)]
        return [l[4:] for l in body.split("\n") if l.startswith("\t// ")]
    sys.exit("function %s not found" % name)

def main(gen, image_path, name, maxl=400):
    img = open(image_path, "rb").read(); BASE = 0x82000000
    def cstr(a):
        o = a - BASE
        if o < 0 or o + 1 >= len(img): return None
        e = img.find(b"\0", o, o + 80); s = img[o:e] if e > 0 else b""
        return s.decode("ascii") if len(s) >= 3 and all(32 <= c < 127 for c in s) else None
    regs = {}
    for l in asm_of(gen, name)[:maxl]:
        m = re.match(r"(\w+) ?(.*)", l.strip()); note = ""
        if m:
            op, a = m.group(1), [x.strip() for x in m.group(2).split(",")] if m.group(2) else []
            if op == "lis": regs[a[0]] = (int(a[1]) << 16) & 0xFFFFFFFF
            elif op == "addi" and len(a) == 3 and a[1] in regs:
                v = (regs[a[1]] + int(a[2])) & 0xFFFFFFFF; regs[a[0]] = v
                s = cstr(v); note = "   ; 0x%08X%s" % (v, (' "%s"' % s) if s else "")
            elif op in ("lwz", "lfs", "lbz", "lhz", "lfd", "stw", "stfs", "stb", "sth") and len(a) == 2 and re.match(r"-?\d+\(r\d+\)", a[1]):
                off, r = re.match(r"(-?\d+)\((r\d+)\)", a[1]).groups()
                if r in regs: note = "   ; 0x%08X" % ((regs[r] + int(off)) & 0xFFFFFFFF)
                if op.startswith("l") and op != "lfd" and op != "lfs": regs.pop(a[0], None)
            elif op == "bl": regs = {k: v for k, v in regs.items() if int(k[1:]) >= 14}
            elif a and re.match(r"r\d+$", a[0]) and op not in ("cmplwi", "cmpwi", "cmplw", "cmpw", "std"): regs.pop(a[0], None)
        print(l + note)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 400)
