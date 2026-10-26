#!/usr/bin/env python3
"""Offline check of the a22x sideload zip: rebuild each partition image from its block-image payload and
compare with the image the build produced. Also compare boot.img. Read-only on the zip and on the build output."""
import hashlib
import os
import subprocess
import sys
import tempfile
import zipfile

ZIP, IMGDIR = sys.argv[1], sys.argv[2]
BS = 4096


def ranges(tok):
    v = [int(x) for x in tok.split(",")]
    n, rest = v[0], v[1:]
    assert n == len(rest) and n % 2 == 0
    return list(zip(rest[0::2], rest[1::2]))


def sha(path, algo="sha256"):
    h = hashlib.new(algo)
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def rebuild(z, part, tmp):
    tl = z.read(part + ".transfer.list").decode().split("\n")
    version, total = int(tl[0]), int(tl[1])
    assert version >= 3
    cmds = [l for l in tl[4:] if l.strip()]
    kinds = sorted({c.split()[0] for c in cmds})
    br = os.path.join(tmp, part + ".new.dat.br")
    with open(br, "wb") as f:
        f.write(z.read(part + ".new.dat.br"))
    dat = os.path.join(tmp, part + ".new.dat")
    subprocess.check_call(["brotli", "-d", "-f", br, "-o", dat])
    patch = z.read(part + ".patch.dat")
    assert len(patch) == 0, "unexpected patch data"
    img = os.path.join(tmp, part + ".rebuilt.img")
    size = total * BS
    with open(dat, "rb") as d, open(img, "wb") as o:
        o.truncate(size)
        for c in cmds:
            op, rs = c.split()
            if op == "new":
                for a, b in ranges(rs):
                    o.seek(a * BS)
                    data = d.read((b - a) * BS)
                    assert len(data) == (b - a) * BS, "short new.dat"
                    o.write(data)
            elif op in ("zero", "erase"):
                pass  # file already zero-filled
            else:
                raise SystemExit("unsupported transfer command %s in %s" % (op, part))
        assert d.read(1) == b"", "unused data left in new.dat"
    return img, kinds, total


def main():
    z = zipfile.ZipFile(ZIP)
    names = z.namelist()
    ok = True
    with tempfile.TemporaryDirectory(dir=os.path.dirname(os.path.abspath(ZIP))) as tmp:
        for part in ("system", "product"):
            img, kinds, total = rebuild(z, part, tmp)
            built = os.path.join(IMGDIR, part + ".img")
            a, b = sha(img), sha(built)
            same = a == b
            ok &= same
            print("%-8s ops=%s blocks=%d size=%d rebuilt=%s built=%s %s" % (
                part, ",".join(kinds), total, os.path.getsize(img), a[:16], b[:16], "MATCH" if same else "DIFFERENT"))
            print("         sha1 of rebuilt image = %s" % sha(img, "sha1"))
            os.remove(img)
        zb = os.path.join(tmp, "boot.img")
        with open(zb, "wb") as f:
            f.write(z.read("boot.img"))
        a, b = sha(zb), sha(os.path.join(IMGDIR, "boot.img"))
        ok &= a == b
        print("boot     zip=%s built=%s %s" % (a[:16], b[:16], "MATCH" if a == b else "DIFFERENT"))
    bad = [n for n in names if any(k in n.lower() for k in (
        "vendor", "odm", "dtbo", "vbmeta", "recovery", "super", "op_list", "modem", "preloader", "lk.", "tee"))]
    print("entries in zip: %d; names touching vendor/odm/dtbo/vbmeta/recovery/super/etc: %s" % (len(names), bad or "none"))
    print("RESULT:", "ALL MATCH" if ok and not bad else "PROBLEM")


main()
