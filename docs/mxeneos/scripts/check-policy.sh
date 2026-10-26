#!/usr/bin/env bash
# Preflight for the a22x zip: do what init does on the phone, offline, with the images that will ship.
#
# Inputs
#   system.img / product.img : the built images (what the zip writes)
#   vendor_phone.img         : the phone's own vendor partition, read raw via TWRP (read-only)
#   odm_phone.img            : the phone's own odm partition, same way
# Checks
#   1. init's exact secilc command (system/core/init/selinux.cpp, split policy) must exit 0
#   2. compiled policy version must be <= 30 (4.14 kernel)
#   3. property_info_checker over plat + system_ext + product + the phone's vendor property contexts
#   4. checkfc on every file_contexts / service_contexts the phone would load
#   5. genfscon / fs_use rules defined twice with different contexts across the inputs
# Exit status is non-zero if any check fails.
set -u
TOP=${TOP:-/mnt/nvme/mxeneos-build/lineage}
A=${A:-/mnt/nvme/mxeneos-build/a22x}
OUT=${OUT:-out_a22x}
IM=$TOP/$OUT/target/product/a22x/obj/PACKAGING/target_files_intermediates/mxeneos_a22x-target_files/IMAGES
H=$TOP/$OUT/host/linux-x86/bin
VENDOR=${VENDOR:-$A/vendor_phone.img}
ODM=${ODM:-$A/crash1-odm.img}
W=${W:-$A/preflight}
rm -rf "$W"; mkdir -p "$W"/{sys,sext,prod,ven,odm}
fail=0
ok()  { echo "PASS  $*"; }
bad() { echo "FAIL  $*"; fail=1; }

dump() { # image, in-image dir, dest
  "$H/debugfs" -R "rdump $2 $3" "$1" >/dev/null 2>&1
}
dump "$IM/system.img" /system/etc/selinux "$W/sys"
dump "$IM/system.img" /system/system_ext/etc/selinux "$W/sext"
dump "$IM/product.img" /etc/selinux "$W/prod"
dump "$VENDOR" /etc/selinux "$W/ven"
dump "$ODM" /etc/selinux "$W/odm"
S=$W/sys/selinux; X=$W/sext/selinux; P=$W/prod/selinux; V=$W/ven/selinux; O=$W/odm/selinux
for f in "$S/plat_sepolicy.cil" "$X/system_ext_sepolicy.cil" "$P/product_sepolicy.cil" "$V/vendor_sepolicy.cil" "$V/plat_pub_versioned.cil"; do
  [ -s "$f" ] || { bad "missing input $f"; }
done

VERS=$(cat "$V/plat_sepolicy_vers.txt" 2>/dev/null)
echo "vendor plat_sepolicy_vers: $VERS; odm_sepolicy.cil: $( [ -e "$O/odm_sepolicy.cil" ] && echo present || echo absent )"
GENFS=$(cat "$V/genfs_labels_version.txt" 2>/dev/null || echo 202404)   # init default when the file is missing
GFILE="$S/plat_sepolicy_genfs_${GENFS}.cil"; [ -e "$GFILE" ] || GFILE=""
echo "genfs labels version: $GENFS, file ${GFILE:-absent (init skips it)}"

# 1. init's compile
ARGS=("$S/plat_sepolicy.cil" -m -M true -G -N -c 30 "$S/mapping/$VERS.cil" -o "$W/policy.bin" -f /dev/null)
[ -e "$S/mapping/$VERS.compat.cil" ] && ARGS+=("$S/mapping/$VERS.compat.cil")
ARGS+=("$X/system_ext_sepolicy.cil")
[ -e "$X/mapping/$VERS.cil" ] && ARGS+=("$X/mapping/$VERS.cil")
[ -e "$X/mapping/$VERS.compat.cil" ] && ARGS+=("$X/mapping/$VERS.compat.cil")
ARGS+=("$P/product_sepolicy.cil")
[ -e "$P/mapping/$VERS.cil" ] && ARGS+=("$P/mapping/$VERS.cil")
ARGS+=("$V/plat_pub_versioned.cil" "$V/vendor_sepolicy.cil")
[ -e "$O/odm_sepolicy.cil" ] && ARGS+=("$O/odm_sepolicy.cil")
[ -n "$GFILE" ] && ARGS+=("$GFILE")
if "$H/secilc" "${ARGS[@]}" >"$W/secilc.log" 2>&1; then ok "secilc (init's command) exit 0, policy $(stat -c %s "$W/policy.bin") bytes"
else bad "secilc failed: $(head -3 "$W/secilc.log" | tr '\n' ' ')"; fi

# 2. policy version
if [ -s "$W/policy.bin" ]; then
  pv=$(python3 -c "import struct;d=open('$W/policy.bin','rb').read(32);print(struct.unpack('<I',d[16:20])[0])")
  [ "$pv" -le 30 ] && ok "policy version $pv (<= 30)" || bad "policy version $pv > 30, the 4.14 kernel cannot load it"
fi

# 3. property contexts
if [ -s "$W/policy.bin" ]; then
  PC=()
  for f in "$S/plat_property_contexts" "$X/system_ext_property_contexts" "$P/product_property_contexts" "$V/vendor_property_contexts"; do [ -e "$f" ] && PC+=("$f"); done
  if "$H/property_info_checker" "$W/policy.bin" "${PC[@]}" >"$W/prop.log" 2>&1; then ok "property_info_checker over ${#PC[@]} files"
  else bad "property_info_checker: $(head -3 "$W/prop.log" | tr '\n' ' ')"; fi

  # seapp contexts
  SC=()
  for f in "$S/plat_seapp_contexts" "$X/system_ext_seapp_contexts" "$P/product_seapp_contexts" "$V/vendor_seapp_contexts"; do [ -e "$f" ] && SC+=("$f"); done
  if "$H/checkseapp" -p "$W/policy.bin" -o "$W/seapp.out" "${SC[@]}" >"$W/seapp.log" 2>&1; then ok "checkseapp over ${#SC[@]} files"
  else bad "checkseapp: $(head -3 "$W/seapp.log" | tr '\n' ' ')"; fi

  # 4. contexts files
  chk() { # flag file
    [ -e "$2" ] || return 0
    if "$H/checkfc" $1 -e "$W/policy.bin" "$2" >"$W/checkfc.log" 2>&1; then ok "checkfc $1 $(basename "$2")"
    else bad "checkfc $1 $(basename "$2"): $(head -2 "$W/checkfc.log" | tr '\n' ' ')"; fi
  }
  for f in "$S/plat_file_contexts" "$X/system_ext_file_contexts" "$P/product_file_contexts" "$V/vendor_file_contexts"; do chk "" "$f"; done
  for f in "$S/plat_service_contexts" "$X/system_ext_service_contexts" "$P/product_service_contexts" "$V/vendor_service_contexts"; do chk -s "$f"; done
  for f in "$S/plat_hwservice_contexts" "$X/system_ext_hwservice_contexts" "$P/product_hwservice_contexts" "$V/vendor_hwservice_contexts"; do chk -l "$f"; done
  chk -v "$V/vndservice_contexts"
fi

# 5. duplicate genfscon / fs_use rules with different contexts
python3 - "$S/plat_sepolicy.cil" "$X/system_ext_sepolicy.cil" "$P/product_sepolicy.cil" "$V/vendor_sepolicy.cil" "$V/plat_pub_versioned.cil" <<'EOF' || fail=1
import re, sys, collections
seen = collections.defaultdict(set)
for f in sys.argv[1:]:
    try:
        lines = open(f, errors="replace")
    except OSError:
        continue
    for l in lines:
        l = l.strip()
        m = re.match(r"\(genfscon\s+(\S+)\s+(\S+)\s+(.*)\)$", l)
        if m:
            seen[("genfscon", m.group(1), m.group(2).strip(chr(34)))].add(m.group(3)); continue
        m = re.match(r"\((fsuse)\s+(\S+)\s+(\S+)\s+(.*)\)$", l)
        if m:
            seen[("fs_use", m.group(3).strip(chr(34)))].add((m.group(2), m.group(4)))
bad = {k: v for k, v in seen.items() if len(v) > 1}
if bad:
    print("FAIL  conflicting duplicate rules:", len(bad))
    for k, v in list(bad.items())[:10]:
        print("      ", k, v)
    sys.exit(1)
print("PASS  no genfscon/fs_use rule defined twice with different contexts")
EOF

echo
[ $fail -eq 0 ] && echo "PREFLIGHT: ALL PASS" || echo "PREFLIGHT: FAILED"
exit $fail
