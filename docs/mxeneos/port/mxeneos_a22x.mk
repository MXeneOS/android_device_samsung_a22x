# MXeneOS build of the LineageOS a22x product. Expected to be checked out at
# device/mxeneos/a22x in the source tree (see manifests/mxeneos_a22x.xml).

# Branding first: its overlays must outrank vendor/lineage's (see core/features/branding/README.md).
$(call inherit-product, vendor/mxeneos/core/features/branding/product.mk)

$(call inherit-product, device/samsung/a22x/lineage_a22x.mk)

# Compulsory core features, then this port's configuration of them.
$(call inherit-product, vendor/mxeneos/core/product.mk)
$(call inherit-product, device/mxeneos/a22x/hardened-malloc.mk)

# device/samsung/a22x/device.mk sets PRODUCT_ENFORCE_RRO_TARGETS := *, which turns every overlay directory that is
# not listed as excluded into a runtime overlay. The branding overlay is excluded (static, merged into framework-res),
# vendor/lineage/overlay/common was not, so its default_wallpaper came back as a runtime overlay that outranks the
# static one (v7 showed the Lineage wallpaper). Exclude it too: that is how the garnet product builds.
PRODUCT_ENFORCE_RRO_EXCLUDED_OVERLAYS += vendor/lineage/overlay/common

# a22x display: the panel has rounded corners that the stock vendor does not report (radius 0), so the status bar
# clock sat inside the corner. See overlay/frameworks/base/core/res/res/values/dimens.xml.
DEVICE_PACKAGE_OVERLAYS += device/mxeneos/a22x/overlay
PRODUCT_ENFORCE_RRO_EXCLUDED_OVERLAYS += device/mxeneos/a22x/overlay

PRODUCT_NAME := mxeneos_a22x
