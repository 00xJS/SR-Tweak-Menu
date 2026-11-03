"""Makes the creator's sr_alwaysload01 chunk from your own copy of the game's.

The 25 DemoWallNew records (the demo build's invisible boundary walls, unused in
the full game) and the out-of-the-way duct pillar (record 18) become 26 creator
slots, and their 26 meshes become 26 piece shapes sharing the pillar's vertex
buffer. Slot k starts as piece k, so at run time main.lua can read every
piece's mesh and collision shape off the slots and turn any slot into any piece.

args: Map Studio's studio-py folder, the original chunk, the output chunk.
Writes pieces.lua next to the output (slot uids and piece sizes for main.lua)."""
import math, os, struct, sys
sys.path.insert(0, sys.argv[1])
import sr_reborn_core as c
import sr1_obj_core as objcore

PILLAR_REC, PILLAR_MESH = 18, 69
WALL_RECS = list(range(22, 47))
SLOT_RECS = [PILLAR_REC] + WALL_RECS
PROFILE = b'Invincible'
SEE_SQ = 400.0 ** 2           # record +28: squared draw distance (the walls had 25 m)


def rect(l, h, z=0.0, y=0.0):
    return [((z - l / 2, y), (z + l / 2, y), (z + l / 2, y + h), (z - l / 2, y + h))]


def wedge(l, h):
    return [((-l / 2, 0), (l / 2, 0), (l / 2, h))]


def arc(r, n, deg=90.0, flip=False, shift=0.0):
    """Slices (z, y) under a circular curve that starts flat on the ground and
    bends up by `deg`: a quarter pipe at 90, a launch curve at less. Each slice
    runs from the curve to the piece's back, so every one is convex."""
    a = math.radians(deg)
    pts = [(r * math.sin(a * i / n), r - r * math.cos(a * i / n)) for i in range(n + 1)]
    length = pts[-1][0]
    pts = [(z - length / 2, y) for z, y in pts]
    back, out = length / 2, []
    for i in range(n):
        poly = [pts[i], (back, pts[i][1]), (back, pts[i + 1][1]), pts[i + 1]]
        poly = [p for j, p in enumerate(poly) if abs(p[0] - poly[j - 1][0]) + abs(p[1] - poly[j - 1][1]) > 1e-4]
        if flip:
            poly = [(-z, y) for z, y in poly][::-1]
        out.append([(z + shift, y) for z, y in poly])
    return out


def octagon(r):
    return [[(r * math.cos(math.pi / 8 + i * math.pi / 4), r + r * math.sin(math.pi / 8 + i * math.pi / 4)) for i in range(8)]]


def stairs(steps, run, rise):
    total = steps * run
    return [rect(run, rise * (i + 1), -total / 2 + run * (i + 0.5))[0] for i in range(steps)]


# key, label, half width (X), profile polygons in (z, y). Every piece sits on
# y = 0 and is centred on its footprint; +Z is "forward" (ramps rise towards it).
# At most 15 polygons per piece (the game's limit for one object's shape).
PIECES = [
    ('ramp', 'Ramp', 2.5, wedge(10, 2)),
    ('ramp_mid', 'Medium ramp', 3.0, wedge(14, 4)),
    ('bigramp', 'Big ramp', 4.0, wedge(20, 6)),
    ('megaramp', 'Mega ramp', 6.0, wedge(30, 12)),
    ('kicker', 'Kicker', 2.0, wedge(3, 1.5)),
    ('kicker_steep', 'Steep kicker', 2.0, wedge(3, 3)),
    ('ramp_wide', 'Wide ramp', 8.0, wedge(10, 2)),
    ('launch', 'Launch curve', 3.0, arc(14, 8, 40)),
    ('tabletop', 'Table top', 4.0, [((-12, 0), (12, 0), (6, 3), (-6, 3))]),
    ('ridge', 'Pyramid ridge', 4.0, [((-6, 0), (6, 0), (0, 3))]),
    ('quarter', 'Quarter pipe', 4.0, arc(5, 6)),
    ('quarter_big', 'Big quarter pipe', 6.0, arc(10, 10)),
    ('halfpipe', 'Half pipe', 4.0, arc(5, 6, flip=True, shift=-6.5) + arc(5, 6, shift=6.5)),
    ('platform', 'Platform', 5.0, rect(10, 1)),
    ('platform_big', 'Big platform', 10.0, rect(20, 1)),
    ('plank', 'Long plank', 3.0, rect(30, 0.5)),
    ('bridge', 'Long bridge', 4.0, rect(60, 1)),
    ('beam', 'Balance beam', 0.5, rect(20, 0.4)),
    ('block', 'Block', 2.0, rect(4, 4)),
    ('cube', 'Small cube', 1.0, rect(2, 2)),
    ('pillar', 'Pillar', 1.0, rect(2, 10)),
    ('tower', 'Tower', 3.0, rect(6, 20)),
    ('wall', 'Wall', 5.0, rect(0.5, 4)),
    ('wall_high', 'High wall', 10.0, rect(1, 10)),
    ('drum', 'Drum', 3.0, octagon(1.5)),
    ('stairs', 'Stairs', 2.0, stairs(8, 1, 0.5)),
]
PIECE_MESHES = [PILLAR_MESH] + list(range(74, 74 + len(PIECES) - 1))
assert len(PIECES) == len(SLOT_RECS) and all(len(p[3]) <= 15 for p in PIECES)


def sub(a, b): return tuple(a[i] - b[i] for i in range(3))
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def dot(a, b): return sum(a[i]*b[i] for i in range(3))
def unit(a):
    m = math.sqrt(dot(a, a))
    return tuple(x / m for x in a)


def prism(w, prof):
    """A convex profile pushed out to +-w in X: vertices and outward faces (index lists)."""
    n = len(prof)
    verts = [(-w, y, z) for z, y in prof] + [(w, y, z) for z, y in prof]
    faces = [list(range(n)), list(range(2 * n - 1, n - 1, -1))]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, n + i, n + j, j])
    centre = tuple(sum(v[a] for v in verts) / len(verts) for a in range(3))
    out = []
    for f in faces:
        p = [verts[k] for k in f]
        nrm = unit(cross(sub(p[1], p[0]), sub(p[2], p[0])))
        if dot(nrm, sub(p[0], centre)) < 0:
            f = f[::-1]
            nrm = tuple(-x for x in nrm)
        out.append((f, nrm, -dot(nrm, p[0])))
    return verts, out


def render(polys, w, vd, strip, base):
    """Appends the piece to the shared vertex data and index list (both windings,
    so it shows whichever way the game culls). Returns triangles added."""
    tris, first_index = 0, len(strip)
    for prof in polys:
        verts, faces = prism(w, prof)
        for f, n, _ in faces:
            p = [verts[k] for k in f]
            t = unit(sub(p[1], p[0]))
            b = cross(n, t)
            first = base[0]
            for v in p:
                u, vv = dot(v, t) / 4, dot(v, b) / 4
                quv = struct.pack('>hh', int(u * 1024), int(vv * 1024))
                vd += struct.pack('>3f', *v) + struct.pack('>II', objcore.pack_dec3n(n, 0), objcore.pack_tangent(t, 1))
                vd += quv * 4
                base[0] += 1
            for i in range(1, len(p) - 1):
                for tri in ((first, first + i, first + i + 1), (first + i + 1, first + i, first)):
                    if len(strip) > first_index:
                        strip += [strip[-1], tri[0]]
                        if (len(strip) - first_index) % 2:
                            strip.append(tri[0])
                    strip += tri
                    tris += 1
    return tris, first_index, len(strip) - first_index


def hull_record(polys, w):
    out = bytearray(struct.pack('>IIIII', 1, len(polys), 0, 0, 0)) + b'\0' * 12 * len(polys)
    lo, hi = [1e9] * 3, [-1e9] * 3
    for prof in polys:
        verts, faces = prism(w, prof)
        for v in verts:
            for a in range(3):
                lo[a], hi[a] = min(lo[a], v[a]), max(hi[a], v[a])
        out += struct.pack('>II', 0, 2) + struct.pack('>HH', len(verts), 0)
        for v in verts:
            out += struct.pack('>3f', *v)
        out += struct.pack('>I', len(faces))
        for _, n, d in faces:
            out += struct.pack('>4f', *n, d)
        tris = [(f[0], f[i], f[i + 1]) for f, _, _ in faces for i in range(1, len(f) - 1)]
        out += struct.pack('>H', len(tris)) + b''.join(struct.pack('>3H', *t) for t in tris)
        out += b'\0' * (-len(out) % 4)
        out += struct.pack('>H', len(tris)) + b''.join(struct.pack('>4H', 7, *t) for t in tris)
        out += b'\0' * (-len(out) % 4)
    h = [(hi[a] - lo[a]) / 2 for a in range(3)]
    com = [(hi[a] + lo[a]) / 2 for a in range(3)]
    out += struct.pack('>12f', (h[1]**2 + h[2]**2) / 3, 0, 0, 0, (h[0]**2 + h[2]**2) / 3, 0, 0, 0, (h[0]**2 + h[1]**2) / 3, *com)
    return out, lo, hi


def hull_bank():
    recs = [hull_record(p[3], p[2]) for p in PIECES]
    out = bytearray(struct.pack('>4sIII', b'HKCM', 3, 0, len(recs)))
    for r, _, _ in recs:
        out += r
    struct.pack_into('>I', out, 8, len(out))
    return out, [(lo, hi) for _, lo, hi in recs]


def collision(g, insts, empty):
    """The chunk's collision blob with the given meshes' blocks emptied and the
    instance tree (the last block) rebuilt the way Map Studio builds it."""
    stock = c.parse_mopp_blocks(g.coll)
    if len(stock) != len(g.meshes) + 1:
        raise SystemExit('collision block count does not match the meshes')
    has = [bool(b['code']) and k not in empty for k, b in enumerate(stock[:-1])]
    blocks = []
    for k, b in enumerate(stock[:-1]):
        if has[k]:
            raw = bytes(g.coll[b['at']:b['at'] + 28 + len(b['code'])])
        else:
            raw = bytes(b['header24']) + b'\0' * 4
        blocks.append(bytearray(raw))
    vbk = [-1 if not M.subs else c.U32(M.subs[0].s16, 8) for M in g.meshes]
    items = []
    for i in range(len(insts) // 112):
        flags, me = c.U32(insts, 112 * i + 108), c.U32(insts, 112 * i + 104)
        if me >= len(g.meshes):
            continue
        canon = vbk.index(vbk[me])
        if (flags & 0x4c7) or not has[canon]:
            continue
        h = g.meshes[me].hdr
        mn, mx = c.instance_aabb(insts, i, [c.F32(h, 0), c.F32(h, 4), c.F32(h, 8)], [c.F32(h, 12), c.F32(h, 16), c.F32(h, 20)])
        items.append({'key': len(items), 'mn': mn, 'mx': mx})
    blocks.append(c.build_mopp_block(items))
    blob = bytearray()
    for i, b in enumerate(blocks):
        blob += b
        if i + 1 < len(blocks):
            c.PadTo(blob, 64)
    return blob


src = open(sys.argv[2], 'rb').read()
ch = c.read_chunk(src)
g = c.chunk_geometry(ch)
recs, insts = ch.get('static_records').data, ch.get('instances').data
count = c.U32(ch.header, 868)
names = bytes(recs[count * 80:]).split(b'\0')[:count]

# The instance tree's keys count the collidable instances in order; the stock
# tree must use the same numbering the rebuild uses.
stock_keys = c.mopp_keys(c.parse_mopp_blocks(g.coll)[-1]['code'])
rebuilt = c.parse_mopp_blocks(collision(g, insts, set()))[-1]
if max(stock_keys) != max(c.mopp_keys(rebuilt['code'])):
    raise SystemExit('the collision tree does not number instances the way this script does')
if names[PILLAR_REC] != b'b266aADuctPillar04' or any(not names[r].startswith(b'DemoWallNew') for r in WALL_RECS):
    raise SystemExit('this chunk is not the one the creator was written for')
vb_index = c.U32(g.meshes[PILLAR_MESH].subs[0].s16, 8)
vb = g.vbs[vb_index]
if c.U16(vb.desc, 16) != 36:
    raise SystemExit('unexpected vertex size')
used = {c.U32(insts, c.I32(recs, r * 80 + 60) * 112 + 104) for r in SLOT_RECS}
for i in range(len(insts) // 112):
    if c.U32(insts, i * 112 + 104) in used and i not in {c.I32(recs, r * 80 + 60) for r in SLOT_RECS}:
        raise SystemExit('a slot mesh is shared with another object')
material = c.U16(g.meshes[PILLAR_MESH].subs[0].b16, 6)

vd, strip, base, total = bytearray(), [], [0], 0
ranges = []
for key, label, w, polys in PIECES:
    tris, first, cnt = render(polys, w, vd, strip, base)
    total += tris
    ranges.append((first, cnt))
if base[0] > 65535:
    raise SystemExit('too many vertices')
vb.vd = vd
vb.ib = bytearray()
for i in strip:
    c.Put16(vb.ib, i)
c.Wr16(vb.desc, 0, total)
c.Wr16(vb.desc, 12, base[0])
c.Wr16(vb.desc, 14, len(strip))

bank, bounds = hull_bank()
for t, m in enumerate(PIECE_MESHES):
    mesh = g.meshes[m]
    s = mesh.subs[0]
    first, cnt = ranges[t]
    c.Wr32(s.s16, 8, vb_index)
    c.Wr16(s.s16, 2, 1)
    s.b16 = bytearray(struct.pack('>IHH', first, cnt, material))
    if s.has12:
        c.Wr16(s.s12, 2, 1)
        s.b12 = bytearray(struct.pack('>IHH', first, cnt, c.U16(s.b12, 6)))
    lo, hi = bounds[t]
    for a in range(3):
        c.WrF(mesh.hdr, a * 4, lo[a])
        c.WrF(mesh.hdr, 12 + a * 4, hi[a])

blob = ch.get('rec_blob308').data
profile_at = len(blob) - 4
blob += PROFILE + b'\0'
c.Wr32(blob, 0, len(blob) - 4)

slots = []
for k, r in enumerate(SLOT_RECS):
    t = k
    name = 'sr_creator_%02d' % k
    uid = c.crc32_sr(name)
    if any(c.U32(recs, i * 80 + 40) == uid for i in range(count)):
        raise SystemExit('name hash collision')
    park = (k * 25.0, -150.0, 0.0)
    ia = c.I32(recs, r * 80 + 60) * 112
    for a, v in enumerate(park):
        c.WrF(insts, ia + 4 + a * 4, v)
    for a, v in enumerate((1, 0, 0, 0, 1, 0, 0, 0, 1)):
        c.WrF(insts, ia + 16 + a * 4, v)
    c.Wr32(insts, ia + 104, PIECE_MESHES[t])
    c.Wr32(insts, ia + 108, 0)
    at = r * 80
    lo, hi = bounds[t]
    for a in range(3):
        c.WrF(recs, at + a * 4, park[a] + lo[a])
        c.WrF(recs, at + 16 + a * 4, park[a] + hi[a])
    c.WrF(recs, at + 28, SEE_SQ)
    c.Wr32(recs, at + 32, 0x10020000)
    c.Wr32(recs, at + 40, uid)
    c.Wr16(recs, at + 56, t)
    c.Wr32(recs, at + 64, profile_at)
    names[r] = name.encode('ascii')
    slots.append((k, r, uid, PIECES[t][0]))

ch.get('static_records').data = bytearray(recs[:count * 80]) + b''.join(n + b'\0' for n in names)
ch.get('block556').data = bank
g.coll = collision(g, insts, {PILLAR_MESH} | {c.U32(insts, c.I32(recs, r * 80 + 60) * 112 + 104) for r in SLOT_RECS} | set(range(74, 99)))
c.set_geometry(ch, g)
out = c.write_chunk(ch)

check = c.read_chunk(out)
cg = c.chunk_geometry(check)
assert bytes(check.get('block556').data) == bytes(bank)
assert bytes(cg.vbs[vb_index].vd) == bytes(vd)
assert len(c.parse_mopp_blocks(cg.coll)) == len(cg.meshes) + 1
open(sys.argv[3], 'wb').write(out)

lua = ['-- Made by build_chunk.py: the creator\'s piece types and slots.', 'return {', '  pieces = {']
for t, (key, label, w, polys) in enumerate(PIECES):
    lo, hi = bounds[t]
    lua.append('    { key = "%s", label = "%s", w = %.2f, l = %.2f, h = %.2f, front_h = %.2f },' % (
        key, label, hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1],
        max([y for prof in polys for z, y in prof if abs(z - hi[2]) < 1e-3] or [0])))
lua.append('  },')
lua.append('  -- slot k starts as piece k')
lua.append('  slots = {')
for k, r, uid, key in slots:
    lua.append('    0x%08X,' % uid)
lua += ['  },', '}', '']
open(os.path.join(os.path.dirname(os.path.abspath(sys.argv[3])), 'pieces.lua'), 'w').write('\n'.join(lua))
print('%d slots, %d piece types, %d vertices, %d triangles, %d bytes (was %d)' % (len(slots), len(PIECES), base[0], total, len(out), len(src)))
