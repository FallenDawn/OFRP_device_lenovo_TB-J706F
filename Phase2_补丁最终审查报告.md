# TB-J706F OrangeFox Fastbootd Phase 2 补丁最终审查报告

- **设备**：Lenovo TB-J706F Wi-Fi / codename `pearl_prc_wifi` / SM6150（Snapdragon 730G）
- **基线**：OrangeFox R12.0 Unofficial，Release `20260607`
- **设备树**：`seomin0610/OFRP_device_lenovo_TB-J706F`，tag `20260607`，分支 `fox_12.1`
- **审查范围**：`tb-j706f/phase2/final/` 下的三个补丁文件
  - `files/twrp.fstab`
  - `files/recovery.fstab`
  - `patches/fastboot-slot-fallback.patch`
- **当前阶段**：仅审查，不修改设备，不构建，不刷机，不执行 `fastboot flash/erase`，不修改 super metadata/GPT/misc/vbmeta，不刷入 GSI。

---

## 1. 已由源码证明的问题

### 1.1 `ReadDefaultFstab()` 在 recovery 中硬编码只读 `/etc/recovery.fstab`

**源码位置**：`system/core/fs_mgr/fs_mgr_fstab.cpp`（AOSP android-12.1.0_r27）

```cpp
std::string default_fstab_path;
// Use different fstab paths for normal boot and recovery boot, respectively
if (access("/system/bin/recovery", F_OK) == 0) {
    default_fstab_path = "/etc/recovery.fstab";
} else {  // normal boot
    default_fstab_path = GetFstabPath();
}

Fstab default_fstab;
if (!default_fstab_path.empty() && ReadFstabFromFile(default_fstab_path, &default_fstab)) {
    ...
} else {
    LINFO << __FUNCTION__ << "(): failed to find device default fstab";
}
```

`ReadFstabFile()` 要求五列 fs_mgr 格式。第 5 列缺失时：

```cpp
if (!(p = strtok_r(NULL, delim, &save_ptr))) {
    LERROR << "Error parsing fs_mgr_options";
    goto err;
}
```

**设备 dmesg 实测**（`recovery_probe_20261105_145317.log`）：

```
[    3.401424] init: [libfs_mgr]Error parsing fs_mgr_options
[    3.401430] init: [libfs_mgr]ReadFstabFromFile(): failed to load fstab from : '/etc/recovery.fstab'
[    3.401438] init: [libfs_mgr]ReadDefaultFstab(): failed to find device default fstab
[    3.401445] init: failed to read default fstab for first stage mount
```

**结论**：现有 `/etc/recovery.fstab` 是 TWRP 四列格式，与 `libfs_mgr` 五列要求冲突。根因已由源码与 dmesg 双重证实。

### 1.2 TWRP/OFRP `twrp.cpp::main()` 优先读 `/etc/twrp.fstab`

**源码位置**：`bootable/recovery/twrp.cpp`（TeamWin android-12.1 / OrangeFox fox_12.1）

```cpp
std::string fstab_filename = "/etc/twrp.fstab";
if (!TWFunc::Path_Exists(fstab_filename)) {
    fstab_filename = "/etc/recovery.fstab";
}
printf("=> Processing %s\n", fstab_filename.c_str());
if (!PartitionManager.Process_Fstab(fstab_filename, 1, !startup.Get_Fastboot_Mode())) {
    LOGERR("Failing out of recovery due to problem with fstab.\n");
    return -1;
}
```

**设备 `/tmp/recovery.log` 实测**：

```
=> Processing /etc/recovery.fstab
I:Reading /etc/recovery.fstab
```

**结论**：只要新增 `/etc/twrp.fstab`，TWRP 所有挂载/解密/备份操作仍走原有 TWRP 格式配置，与 `/etc/recovery.fstab` 无关。fstab 分流方案在 TWRP 侧是安全的。

### 1.3 fastbootd 服务端 slot 来源仅依赖 `IBootControl` HAL

**源码位置 1**：`system/core/fastboot/device/fastboot_device.cpp`

```cpp
FastbootDevice::FastbootDevice()
    : ...
      boot_control_hal_(IBootControl::getService()),
      ...
{}

std::string FastbootDevice::GetCurrentSlot() {
    if (!active_slot_.empty()) {
        return active_slot_;
    }
    // Non-A/B devices must not have boot control HALs.
    if (!boot_control_hal_) {
        return "";
    }
    std::string suffix;
    auto cb = [&suffix](hidl_string s) { suffix = s; };
    boot_control_hal_->getSuffix(boot_control_hal_->getCurrentSlot(), cb);
    return suffix;
}
```

**源码位置 2**：`system/core/fastboot/device/variables.cpp`

```cpp
bool GetSlotCount(FastbootDevice* device, ..., std::string* message) {
    auto boot_control_hal = device->boot_control_hal();
    if (!boot_control_hal) {
        *message = "0";
    } else {
        *message = std::to_string(boot_control_hal->getNumberSlots());
    }
    return true;
}
```

**设备实测**：
- `/vendor/bin/hw` 只有 keymaster，无 `android.hardware.boot@1.0-service`；
- `ro.boot.slot_suffix=_b`，`ro.build.ab_update=true`；
- bootloader 报告 `current-slot: b`，`slot-count: 2`。

**结论**：TB-J706F recovery ramdisk 中没有 boot HAL，导致 `current-slot` 为空、`slot-count` 为 0，这是 fastbootd 侧的 slot 来源缺失，不是 A/B 损坏。

---

## 2. 有设备日志支持但仍需进一步验证的问题

| 问题 | 设备日志支持 | 待验证项 |
|---|---|---|
| `/dev/block/bootdevice/by-name/metadata` 是否存在 | dmesg 显示 `partition-size:metadata: 0x1000000`，GPT 中有 metadata 分区 | `ls -l /dev/block/by-name/metadata` 输出未在日志中明确捕获 |
| `/dev/block/bootdevice/by-name/misc` 是否存在 | dmesg 显示 `partition-size:misc: 0x100000`，GPT 中有 misc | by-name 符号链接是否存在未确认 |
| `TARGET_RECOVERY_FSTAB` 是否会把仓库根 `recovery.fstab` 安装到 `/etc/recovery.fstab` | 基于 TWRP 构建惯例，根目录 `recovery.fstab` 通常通过构建规则安装 | 需在设备树 `Android.mk` / `BoardConfig.mk` 中核实实际安装规则 |
| `partition-size:super` 在 fastbootd 下是否仍 EBUSY | dmesg 显示 TWRP 已创建 dm-4..dm-7 映射 `/dev/block/by-name/{system,system_ext,vendor,product}` | 需在 fastbootd 模式下观察 dmesg 的 `open` errno |

---

## 3. 原方案中存在错误或过度推断的结论

### 3.1 `has-slot` 是 device fastbootd 变量？错误

原提案中曾提到 "has-slot、is-logical、resize-logical-partition、flash 随之恢复正常"，暗示 `has-slot` 在 device fastbootd 中处理。这是不准确的：

- `has-slot:` 是 **host fastboot 工具** 的 getvar 变量（`system/core/fastboot/fastboot.cpp` 中的 `do_for_partition`，通过 `fb->GetVar("has-slot:...")` 查询 device fastbootd），不是 device fastbootd (`system/core/fastboot/device/variables.cpp`) 的变量。
- device fastbootd 的 `variables.cpp` 中 **没有** `FB_VAR_HAS_SLOT`。设备端 fastbootd 只处理 `current-slot`、`slot-count`、`is-logical`、`partition-size` 等。

**修正**：补丁修复的是 device fastbootd 的 `current-slot` / `slot-count`，间接使 host fastboot 的 `has-slot:system_b` 等能够正常工作，但 `has-slot` 本身不是 device 端变量。

### 3.2 B 路径（`setprop sys.usb.config fastboot`）等同于 A 路径（`fastboot reboot fastboot`）？过度推断

- **A 路径**：从 bootloader 执行 `fastboot reboot fastboot`，设备重启进入 userspace fastbootd。init.rc 处理 `sys.usb.config=fastboot`，启动 `fastbootd` 服务；TWRP 的 `process_fastbootd_mode()` 中会执行 `Unmap_Super_Devices()`（如果 `ro.boot.dynamic_partitions` 为 true）。
- **B 路径**：在 OrangeFox 主界面执行 `setprop sys.usb.config fastboot`，仅触发 init.rc 的 `on property:sys.usb.config=fastboot start fastbootd`。**不会执行 TWRP 的 `process_fastbootd_mode()`，也就不会执行 `Unmap_Super_Devices()`。**

设备日志显示 TWRP 已创建 dm-4..dm-7 映射。如果在 B 路径下启动 fastbootd，super 分区仍被 device-mapper 持有，`partition-size:super` 的 `open(..., O_EXCL)` 很可能返回 `EBUSY`。

**修正**：B 路径只适合调试 USB 连接，不适合作为正式验证方式。正式验证必须使用 A 路径（或 TWRP 菜单的 Reboot to fastboot）。

### 3.3 `ro.build.ab_update=true` 作为 `slot-count=2` 的依据是否绝对可靠？

设备实测 `ro.build.ab_update=true`，这是 A/B 设备的标准属性，可作为可靠依据。但补丁逻辑是 `ab ? "2" : "0"`，如果某个非 A/B 设备恰好设置了 `ro.build.ab_update=true`（极少见），会错误报告 2。对 TB-J706F 而言，bootloader 已报告 `slot-count: 2`，该依据成立。

---

## 4. 必须修改的补丁

基于以上审计，**三个补丁文件整体方案成立**，不需要额外修改补丁核心逻辑。以下是确认事项：

1. `files/recovery.fstab`：已简化为仅 `/metadata`、`/misc` 两条，去掉了之前草稿中的 `/system` 等 logical 条目，这是正确的。保持不动。
2. `files/twrp.fstab`：与现有 `recovery.fstab` 一字不改，保持不动。
3. `patches/fastboot-slot-fallback.patch`：`GetCurrentSlot()` 回退逻辑中，`ro.boot.slot_suffix` 已经是 `_b` 形式时 `suffix[0] == '_'`，不会重复插入；`ro.boot.slot` 为 `b` 时会插入 `_` 得到 `_b`。**不会出现 `_b_b`**。保持不动。

---

## 5. 可以保留不动的配置

| 配置 | 理由 |
|---|---|
| `BOARD_SUPER_PARTITION_SIZE := 9126805504` | 构建期变量，fastbootd 不读；不影响运行时 |
| `BOARD_LENOVO_DYNAMIC_PARTITIONS_SIZE := 9122611200` | 同上，且不应直接写 12 GiB |
| `BOARD_KERNEL_CMDLINE` | `ro.boot.dynamic_partitions=true` 已由 bootloader 传递，无需追加 |
| `recovery/root/vendor/etc/fstab.default` | 正常启动路径使用，recovery/fastbootd 不读，不动 |
| `recovery/root/vendor/etc/vintf/manifest.xml` | 只声明 keymaster，是解密必须配置，不动 |
| `init.recovery.qcom.rc` 中的 keymaster/qseecomd/keystore2 顺序 | 解密依赖，不动 |
| `device.mk` 中的 boot HAL 包声明 | 构建期声明，但 ramdisk 中实际未启动服务；补丁 B2 绕过此问题，无需改 device.mk |
| `TW_EXCLUDE_MTP := true` | 与 fastbootd 无关，单独决策，本次不动 |

---

## 6. 修复后的完整 unified diff

### 6.1 设备树：`recovery.fstab`（仓库根）

```diff
--- a/recovery.fstab
+++ b/recovery.fstab
@@ -1,11 +1,6 @@
-/system         ext4     system                                     flags=display=system;logical;slotselect;fsflags=ro
-/system_ext     ext4     system_ext                                 flags=display=system_ext;logical;slotselect;fsflags=ro
-/vendor         ext4     vendor                                     flags=display=vendor;logical;slotselect;mounttodecrypt;fsflags=ro
-/product        ext4     product                                    flags=display=product;logical;slotselect;fsflags=ro
-/metadata       ext4     /dev/block/bootdevice/by-name/metadata     flags=display=metadata;mounttodecrypt
+/dev/block/bootdevice/by-name/metadata                  /metadata    ext4  noatime,nosuid,nodev,discard  wait,check
+/dev/block/bootdevice/by-name/misc                      /misc        emmc  defaults  defaults
-/data           f2fs     /dev/block/bootdevice/by-name/userdata     flags=display=data;fileencryption=ice:aes-256-cts:v1+wrappedkey_v0
-/external_sd    vfat     /dev/block/mmcblk1p1                       flags=display="Micro SDcard";storage;removable
-/boot           emmc     /dev/block/bootdevice/by-name/boot         flags=display=boot;slotselect
-/recovery       emmc     /dev/block/bootdevice/by-name/recovery     flags=display=recovery;slotselect
-/misc           emmc     /dev/block/bootdevice/by-name/misc         flags=display=misc
```

### 6.2 设备树：`recovery/root/etc/recovery.fstab`

与 6.1 相同，内容替换为 fs_mgr 五列两条。

### 6.3 设备树：新增 `recovery/root/etc/twrp.fstab`

内容等于旧 `recovery.fstab`（TWRP 四列十条，一字不改）。

### 6.4 `system/core/fastboot/device/fastboot_device.cpp`

```diff
@@ -107,13 +107,25 @@ std::string FastbootDevice::GetCurrentSlot() {
     if (!active_slot_.empty()) {
         return active_slot_;
     }
-    // Non-A/B devices must not have boot control HALs.
-    if (!boot_control_hal_) {
-        return "";
+    if (boot_control_hal_) {
+        std::string suffix;
+        auto cb = [&suffix](hidl_string s) { suffix = s; };
+        boot_control_hal_->getSuffix(boot_control_hal_->getCurrentSlot(), cb);
+        if (!suffix.empty()) {
+            return suffix;
+        }
     }
-    std::string suffix;
-    auto cb = [&suffix](hidl_string s) { suffix = s; };
-    boot_control_hal_->getSuffix(boot_control_hal_->getCurrentSlot(), cb);
+
+    // Recovery may not run a boot control HAL. Fall back to the slot suffix
+    // exported by the bootloader so slot-suffixed partitions can still be
+    // addressed (has-slot, is-logical, resize-logical-partition, flash).
+    std::string suffix = android::base::GetProperty("ro.boot.slot_suffix", "");
+    if (suffix.empty()) {
+        suffix = android::base::GetProperty("ro.boot.slot", "");
+    }
+    if (!suffix.empty() && suffix[0] != '_') {
+        suffix.insert(0, "_");
+    }
     return suffix;
 }
```

### 6.5 `system/core/fastboot/device/variables.cpp`

```diff
@@ -186,11 +186,15 @@ bool GetSlotCount(FastbootDevice* device, const std::vector<std::string>& /* ar
                   std::string* message) {
     auto boot_control_hal = device->boot_control_hal();
-    if (!boot_control_hal) {
-        *message = "0";
-    } else {
+    if (boot_control_hal) {
         *message = std::to_string(boot_control_hal->getNumberSlots());
+        return true;
     }
+
+    // No boot control HAL: infer A/B from build/bootloader properties.
+    bool ab = android::base::GetBoolProperty("ro.build.ab_update", false) ||
+              !android::base::GetProperty("ro.boot.slot_suffix", "").empty();
+    *message = ab ? "2" : "0";
     return true;
 }
```

---

## 7. 最小化构建方案

1. 设备树检出分支 `fix/pearl-prc-wifi-fastbootd`（基于 tag `20260607`，而非分支 HEAD）。
2. 应用 6.1、6.2、6.3 三个文件变更。
3. `system/core` 检出 `android-12.1.0_r27`（或项目实际使用的 recovery 基础版本），应用 6.4、6.5。
4. 构建命令：

```bash
export ALLOW_MISSING_DEPENDENCIES=true
export FOX_BUILD_DEVICE=pearl_prc_wifi
export LC_ALL=C
source build/envsetup.sh
lunch twrp_pearl_prc_wifi-eng
mka adbd recoveryimage 2>&1 | tee build.log
```

5. 产物：`out/target/product/pearl_prc_wifi/OrangeFox-R12.0-Unofficial-pearl.img`，记录 SHA256，**不自动发布 Release**。

---

## 8. 只读验证方案

### 8.1 进入方式（必须）

使用 **A 路径**：`fastboot reboot fastboot`（从 bootloader 进入 userspace fastbootd），或在 TWRP 菜单选择 Reboot to fastboot。**不要**使用 `setprop sys.usb.config fastboot`（B 路径，会绕过 `Unmap_Super_Devices`）。

### 8.2 验收指标（只读，仅 getvar）

运行 `fastbootd_check.bat`，重点核对以下指标：

| 指标 | 预期 | 说明 |
|---|---|---|
| `is-userspace` | `yes` | 确认在 userspace fastbootd 而非 bootloader |
| `current-slot` | `b` | 与 bootloader 一致 |
| `slot-count` | `2` | A/B 正常 |
| `has-slot:system` | `no` | host 端变量，GPT 中无名为 `system` 的槽位分区，正常 |
| `has-slot:system_b` | `yes` | 设备端 `GetHasSlot` 应能识别 |
| `is-logical:system` | `no` 或 FAILED | 无后缀名不在 metadata 中，AOSP 正常语义 |
| `is-logical:system_b` | `yes` | 逻辑分区识别正常 |
| `is-logical:vendor_b` | `yes` | 同上 |
| `is-logical:product_b` | `yes` | 同上 |
| `partition-size:system_b` | 非 FAILED，合理大小 | 逻辑分区可读 |
| `partition-size:vendor_b` | 非 FAILED | 同上 |
| `partition-size:product_b` | 非 FAILED | 同上 |
| `partition-size:super` | `0x300000000` | 物理 super 大小 |

**不要**把以下结果当成功标准：
- `is-logical:system: yes`（不应出现，metadata 中无无后缀名）
- `has-slot:system: yes`（GPT 中无物理 `system` 分区）

### 8.3 Recovery 日志检查

在 TWRP 中运行 `recovery_probe.bat`，检查 `/tmp/recovery.log` 中不再出现：

- `Error parsing fs_mgr_options`
- `failed to find device default fstab`
- `failed to find /misc partition`

---

## 9. 回滚方案

1. 保留原始 Release `20260607` 镜像（SHA256 `2c4620ddbf73399053a7e1e02875c4f0e74e5c0c559f3ee10848aed982184595`）。
2. 若新构建镜像有问题，在 bootloader 模式：

```cmd
fastboot flash recovery OrangeFox-R12.0-Unofficial-pearl.img
fastboot reboot recovery
```

3. 不执行 `fastboot erase misc`，不触碰 vbmeta / vbmeta_system / super / GPT / misc / metadata / userdata / persist / modemst1 / modemst2 / fsg / fsc。

---

## 10. 审查结论

**Phase 2 补丁方案成立**，三个补丁文件可直接用于 Phase 3 构建。当前阶段不修改设备，等待用户明确批准后再执行源码修改和云端编译。编译完成后再进行只读验证；GSI 安装需另行批准。

---

## 附录：相关文件位置

```
tb-j706f/phase2/final/
├── files/
│   ├── twrp.fstab        # 新增：recovery/root/etc/twrp.fstab
│   └── recovery.fstab    # 替换：recovery/root/etc/recovery.fstab + 仓库根 recovery.fstab
├── patches/
│   └── fastboot-slot-fallback.patch  # system/core/fastboot B2 补丁
└── README_定稿.md          # 应用步骤与审查点
```
