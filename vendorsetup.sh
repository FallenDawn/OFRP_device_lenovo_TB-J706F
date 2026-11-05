#
# OrangeFox build environment for Lenovo TB-J706F (pearl_prc_wifi)
# FOX_* and OF_* variables must be exported from this shell script.
#
export FOX_BUILD_DEVICE=pearl_prc_wifi
export FOX_AB_DEVICE=1
export FOX_VANILLA_BUILD=1
export FOX_TARGET_DEVICES="pearl_prc_wifi,J706F,LenovoTB-J706F_PRC"

export OF_AB_DEVICE_WITH_RECOVERY_PARTITION=1
export OF_RECOVERY_AB_FULL_REFLASH_RAMDISK=0
export OF_ADVANCED_SECURITY=0
export OF_FORCE_PREBUILT_KERNEL=1
export OF_ENABLE_ALL_PARTITION_TOOLS=1
export OF_FBE_METADATA_MOUNT_IGNORE=0
export OF_NO_ADDITIONAL_MIUI_PROPS_CHECK=1
export OF_SCREEN_H=1728
export OF_ALLOW_DISABLE_NAVBAR=0

export OF_USE_MAGISKBOOT=1
export OF_USE_MAGISKBOOT_FOR_ALL_PATCHES=1

# TB-J706F stock reports Keymaster HIDL 4.0; recovery VINTF manifest
# deliberately declares 4.0 only. Preserve wrapped-key FBE support.
export OF_USE_LZMA_COMPRESSION=1
export OF_SUPPORT_ALL_DECRYPTION=1
export FOX_USE_BUGGED_CRYPTO_POLICY=1
export OF_SKIP_DECRYPTED_ADOPTED_STORAGE=1
export OF_USE_KEYMASTER_4=1
export OF_DEFAULT_KEYMASTER_VERSION=4.0
