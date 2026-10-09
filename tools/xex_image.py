#!/usr/bin/env python3
"""xex_image.py <default.xex> <image.bin>

Turns the game's XEX2 (encrypted, "basic" compression, as Saints Row's is)
into the flat memory image the console sees at 0x82000000, so strings and
tables can be looked up by address with a hex editor or `strings -t x`.
Uses the OpenSSL command line for AES; nothing else is needed. The image
is the player's own game data: keep it out of anything you share.
"""
import struct, subprocess, sys

RETAIL_KEY = "20B185A59D28FDC340583FBB0896BF91"

def main(path, out):
    d = open(path, "rb").read()
    magic, _flags, pe_off, _res, sec_off, count = struct.unpack(">4sIIIII", d[:24])
    assert magic == b"XEX2", "not an XEX2 file"
    headers = dict(struct.unpack(">II", d[24 + i * 8:32 + i * 8]) for i in range(count))
    fmt = headers[0x3FF]
    _size, enc, comp = struct.unpack(">IHH", d[fmt:fmt + 8])
    assert comp == 1, "only basic compression is handled (this file: %d)" % comp
    blocks = [struct.unpack(">II", d[fmt + 8 + i * 8:fmt + 16 + i * 8]) for i in range((_size - 8) // 8)]
    base = struct.unpack(">I", d[sec_off + 0x110:sec_off + 0x114])[0]
    data = d[pe_off:]
    if enc:
        key = d[sec_off + 0x150:sec_off + 0x160]
        aes = lambda k, buf: subprocess.run(["openssl", "enc", "-d", "-aes-128-cbc", "-K", k, "-iv", "0" * 32, "-nopad"],
                                            input=buf, capture_output=True, check=True).stdout
        session = aes(RETAIL_KEY, key)
        data = aes(session.hex(), data)
    image = bytearray(); p = 0
    for size, zeros in blocks:
        image += data[p:p + size]; p += size; image += b"\0" * zeros
    open(out, "wb").write(image)
    print("image base 0x%08X, %d bytes -> %s" % (base, len(image), out))

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
