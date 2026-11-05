# TB-J706F fastbootd / fstab 修正

目标设备：Lenovo TB-J706F Wi-Fi（`pearl_prc_wifi`，SM6150）。
目标分支：`fix/pearl-prc-wifi-fastbootd`。

## 本分支修正

1. 仓库根目录 `recovery.fstab` 使用 Android fs_mgr 五列格式，仅含 `/metadata`、`/misc`。
2. `recovery/root/etc/recovery.fstab` 与根目录 `recovery.fstab` 内容一致，确保 ramdisk 中的 init/fastbootd 读到 fs_mgr 格式。
3. 新增 `recovery/root/etc/twrp.fstab`，保留原始 TWRP 四列分区表（system/system_ext/vendor/product/data/boot/recovery 等）。
4. 新增 `patches/fastboot-slot-fallback.patch`，在没有 Boot Control HAL 时，使用 `ro.boot.slot_suffix` / `ro.boot.slot` 和 `ro.build.ab_update` 补足 fastbootd 的 slot 识别。
5. 新增应用脚本，构建前显式检查并应用补丁。

`BoardConfig.mk` 已设置 `TARGET_RECOVERY_ROOT := $(DEVICE_PATH)/recovery/root`，所以 ramdisk 下两个 fstab 会被打包；不依赖仓库根文件的隐式复制。

## fastboot 补丁应用

在 OrangeFox/AOSP 源码根目录执行：

```bash
bash device/lenovo/pearl_prc_wifi/scripts/apply-fastboot-slot-fallback.sh
```

脚本确认 `system/core/fastboot/device/` 存在，先执行 `git apply --check`，通过后才应用补丁；若检测到补丁已应用则安全退出。最后运行 `git diff --check`。

补丁按 AOSP `android-12.1.0_r27` 的 `platform_system_core` 对应源码上下文编写。实际 OrangeFox manifest 若使用不同提交，以脚本的 `git apply --check` 为准；不通过时停止构建并审查版本差异，不要强制套用。

## 只读验收

构建后先解包 recovery 镜像，确认 ramdisk 中：
- `etc/recovery.fstab` 是 fs_mgr 五列格式，且只有 metadata、misc 两条；
- `etc/twrp.fstab` 是原始 TWRP 四列格式，且包含 data、logical partitions 等条目。

设备验证必须在真正的 userspace fastbootd 中进行（`is-userspace: yes`），不要用从 recovery 直接改 `sys.usb.config=fastboot` 的方式代替正式路径。

建议只读 getvar 检查：

| 命令 | 预期 |
|---|---|
| `fastboot getvar current-slot` | `b`（以当前实际启动槽为准） |
| `fastboot getvar slot-count` | `2` |
| `fastboot getvar has-slot:system` | `yes`（host 端按当前槽拼接成 system_b 查询） |
| `fastboot getvar has-slot:system_b` | 通常 `no`（会再拼接一次后缀，不应作为验收项） |
| `fastboot getvar is-logical:system_b` | `yes` |
| `fastboot getvar is-logical:vendor_b` | `yes` |

注意：`has-slot:` 请求参数应是无后缀基础分区名。AOSP 设备端会将参数与当前槽后缀拼接；所以检查 `has-slot:system`，不要检查 `has-slot:system_b`。

## 范围与安全边界

此补丁只修复 `current-slot` / `slot-count` 的读取回退，不替代完整 Boot Control HAL，不实现 slot successful/unbootable 查询、`set_active` 等操作。不要据此进行跨槽刷写或修改 A/B 元数据。

本次源码变更不执行构建、刷机、擦除或 GSI 安装。任何设备写入操作都需另行确认。
