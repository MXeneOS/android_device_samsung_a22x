# MXeneOS build of the LineageOS a22x product. Expected to be checked out at
# device/mxeneos/a22x in the source tree (see manifests/mxeneos_a22x.xml).

# Branding first: its overlays must outrank vendor/lineage's (see core/features/branding/README.md).
$(call inherit-product, vendor/mxeneos/core/features/branding/product.mk)

$(call inherit-product, device/samsung/a22x/lineage_a22x.mk)

# Compulsory core features, then this port's configuration of them.
$(call inherit-product, vendor/mxeneos/core/product.mk)
$(call inherit-product, device/mxeneos/a22x/hardened-malloc.mk)

PRODUCT_NAME := mxeneos_a22x
