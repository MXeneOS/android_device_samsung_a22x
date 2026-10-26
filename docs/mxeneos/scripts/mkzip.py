#!/usr/bin/env python3
"""Build the a22x sideload zip: writes system, product and boot only.

Why this exists: the stock full-OTA path (ota_from_target_files) needs a recovery image and rewrites the whole
dynamic-partition layout, including the prebuilt vendor and odm. This port ships neither. This script reuses the
tree's own releasetools (block-image payloads, edify script, updater binary from the target files) and writes only
the three partitions below. It does not write vendor, odm, dtbo, vbmeta, recovery or any firmware.

Run from the root of the Android tree:
  PATH=$PWD/out_a22x/host/linux-x86/bin:$PATH python3 mkzip.py <target_files.zip> <output.zip>
"""
import os
import sys
import tempfile
import zipfile

sys.path.insert(0, "build/make/tools/releasetools")
import common  # noqa: E402
import edify_generator  # noqa: E402

PARTITIONS = ["system", "product"]  # logical partitions that already exist in the phone's super
BOOT_DEVICE = "/dev/block/by-name/boot"
DEVICES = ["a22x"]
HOST = "out_a22x/host/linux-x86"
# Scratch space: the build node's /tmp is a small RAM-backed tmpfs, keep the 2 GB of temp files on the NVMe disk.
SCRATCH = os.environ.get("MKZIP_SCRATCH", "/mnt/nvme/mxeneos-build/a22x/tmp")
os.makedirs(SCRATCH, exist_ok=True)
tempfile.tempdir = SCRATCH


def main():
    tf, out = sys.argv[1], sys.argv[2]
    opts = common.OPTIONS
    opts.search_path = HOST
    opts.java_path = "prebuilts/jdk/jdk21/linux-x86/bin/java"  # the tree's own JDK, used by signapk
    opts.worker_threads = 12
    opts.cache_size = 209715200  # BOARD_CACHEIMAGE_PARTITION_SIZE; only bounds the stash of incremental updates

    input_zip = zipfile.ZipFile(tf)
    wanted = ["IMAGES/%s.%s" % (p, e) for p in PARTITIONS for e in ("img", "map")]
    wanted += ["IMAGES/boot.img", "META/*", "OTA/*"]
    opts.input_tmp = common.UnzipTemp(tf, wanted)
    opts.info_dict = common.LoadInfoDict(input_zip)
    info = opts.info_dict

    if info.get("ab_update") == "true":
        sys.exit("target files are A/B; this phone is not")
    for p in PARTITIONS:
        if p not in info["dynamic_partition_list"].split():
            sys.exit("%s is not a dynamic partition in this build" % p)

    script = edify_generator.EdifyGenerator(info["recovery_api_version"], info)
    tmp_zip = common.MakeTempFile(suffix=".zip")
    output_zip = zipfile.ZipFile(tmp_zip, "w", compression=zipfile.ZIP_DEFLATED)

    cond = " || ".join('getprop("%s") == "%s"' % (prop, dev)
                       for dev in DEVICES
                       for prop in ("ro.product.device", "ro.build.product", "ro.product.vendor.device"))
    cond += ' || getprop("ro.product.model") == "SM-A226B"'
    script.AppendExtra('ifelse(%s, ui_print("Device check passed."), abort("E3004: This package is for a22x (SM-A226B)."));' % cond)
    script.Print("MXeneOS for a22x: writes system, product and boot only.")
    script.Print("vendor, odm, dtbo, vbmeta, recovery and modem are not touched.")

    for p in PARTITIONS:
        tgt = common.GetUserImage(p, opts.input_tmp, input_zip, info_dict=info, reset_file_map=True)
        bd = common.BlockDifference(p, tgt, src=None)
        bd.WriteScript(script, output_zip, progress=0.4, write_verify_script=True)
        script.AppendExtra('unmap_partition("%s");' % p)

    boot = os.path.join(opts.input_tmp, "IMAGES", "boot.img")
    common.ZipWrite(output_zip, boot, "boot.img")
    script.Print("Writing boot...")
    script.AppendExtra('package_extract_file("boot.img", "%s");' % BOOT_DEVICE)
    script.Print("Done.")

    script.AddToZip(input_zip, output_zip)
    common.ZipWriteStr(output_zip, "META-INF/com/android/metadata",
                       "ota-type=BLOCK\npre-device=%s\n" % ",".join(DEVICES))
    output_zip.close()

    key = "build/make/target/product/security/testkey"
    common.SignFile(tmp_zip, out, key, None, whole_file=True)
    print("wrote", out)
    common.Cleanup()  # releasetools temp dirs live in SCRATCH; remove them when done


if __name__ == "__main__":
    main()
