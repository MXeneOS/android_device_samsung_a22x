#
# Copyright (C) 2024 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit from a22x device
$(call inherit-product, device/samsung/a22x/device.mk)

# Inherit some common Lineage stuff
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

PRODUCT_DEVICE := a22x
LINEAGE_BUILD := a22x
PRODUCT_NAME := lineage_a22x
PRODUCT_BRAND := samsung
PRODUCT_MODEL := SM-A226B
PRODUCT_MANUFACTURER := samsung

PRODUCT_GMS_CLIENTID_BASE := android-samsung-ss

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="a22xnsxx-user 12 SP1A.210812.016 A226BXXSBDZC3 release-keys"

BUILD_FINGERPRINT := samsung/a22xnsxx/a22x:12/SP1A.210812.016/A226BXXSBDZC3:user/release-keys

PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false
PRODUCT_ENFORCE_VINTF_MANIFEST := false
PRODUCT_USE_DYNAMIC_PARTITIONS := true
