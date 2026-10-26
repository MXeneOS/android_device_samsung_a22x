# Opt-out of the default hardened_malloc class region size for this port.
#
# The stock kernel gives userspace a 39-bit address space (CONFIG_ARM64_VA_BITS_39 in the phone's
# /proc/config.gz, survey/proc_config.txt), so the upstream default of 32 GiB per size class cannot be
# mapped. Same value as garnet, which booted with it (garnet PINS.md, hardening2). Untested on this
# kernel (4.14, garnet is 5.10).
$(call soong_config_set,mxeneos_hardened_malloc,class_region_size,1073741824)
