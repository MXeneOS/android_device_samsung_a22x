#!/usr/bin/env bash
# Clean kernel: Samsung OSS base 05a32cd5f (first commit of the a22x fork), a22x_defconfig, clang r383902.
# Built from a git-archive export (no .git) so the release string has no "+"; LOCALVERSION matches the vermagic
# of the vendor modules (4.14.186-27218697).
A=/mnt/nvme/mxeneos-build/a22x
rm -rf $A/src/kernel-export $A/src/out-oss2 && mkdir -p $A/src/kernel-export $A/src/out-oss2 || exit 1
git -C $A/src/kernel archive 05a32cd5f | tar -x -C $A/src/kernel-export || exit 1
cd $A/src/kernel-export || exit 1
export PATH=$A/tc/clang-r383902/bin:/mnt/nvme/mxeneos-build/lineage/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin:$PATH
M="make O=../out-oss2 ARCH=arm64 CC=clang CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-android- LOCALVERSION=-27218697 KBUILD_BUILD_USER=mxeneos KBUILD_BUILD_HOST=mxeneos"
$M a22x_defconfig && $M -j20 Image.gz dtbs modules
echo "KBUILD_EXIT=$?"
