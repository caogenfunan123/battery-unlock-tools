# 编译指南（k60_vol_write.ko 与手机内核精确对齐）

> 目的：编译出能在 Redmi K60 (KernelSU) 上 **成功 insmod** 的 k60_vol_write.ko。
> 失败原因：vermagic 不匹配（源码 commit / LOCALVERSION / config 与手机内核不一致）。

## 0. 手机内核身份（本机实测）

```
uname: 5.10.136-android12-9-00003-g8970630c07cd-ab9368044
构建:  Google 官方 GKI (build-user@build-host, 2022-12-04, #1 SMP PREEMPT)
编译器: Android clang 12.0.5 (r416183b)
config: CONFIG_LOCALVERSION_AUTO=y  CONFIG_MODVERSIONS=y
        CONFIG_LTO_CLANG_FULL=y
```

**vermagic 目标串（必须 100% 一致）**：
```
5.10.136-android12-9-00003-g8970630c07cd-ab9368044 SMP preempt mod_unload modversions aarch64
```

三个要素缺一不可：
| 要素 | 值 | 说明 |
|---|---|---|
| 源码 commit | g8970630c07cd | android12-5.10 分支 |
| LOCALVERSION | -g8970630c07cd-ab9368044 | git 后缀（含源码+构建双 hash） |
| 编译器 | clang-r416183b (12.0.5) | 与官方构建同款 |
| config | 手机 /proc/config.gz | 保底方案（--with-config） |

## 1. 一键脚本（推荐）

```bash
# 下载
curl -kL -o build_vol_write.sh https://raw.githubusercontent.com/caogenfunan123/battery-unlock-tools/main/scripts/build_vol_write.sh

# 普通模式：自动对齐源码 commit + LOCALVERSION 编译
bash build_vol_write.sh

# 保底模式：先从手机拉真实 config（需 USB 调试连接）→ CRC 保证一致
bash build_vol_write.sh --with-config
```

脚本自动执行：
1. 检查 gki136 内核树 + clang-r416183b 工具链
2. 对齐源码 commit g8970630c07cd（自动 fetch android12-5.10 + checkout）
3. 从仓库下载 k60_vol_write.c
4. 带 LOCALVERSION="-g8970630c07cd-ab9368044" + CONFIG_LOCALVERSION_AUTO=n 编译
5. modinfo 自动打印 vermagic 供对照

## 2. 手工编译（不用脚本时）

```bash
cd /workspace/k60-battery-unlock/kernel   # 或任意放 Kbuild+源码的目录
make ARCH=arm64 \
  CC=/tmp/opencode/ddk/clang-r416183b/bin/clang \
  LD=/tmp/opencode/ddk/clang-r416183b/bin/ld.lld \
  NM=/tmp/opencode/ddk/clang-r416183b/bin/llvm-nm \
  AR=/tmp/opencode/ddk/clang-r416183b/bin/llvm-ar \
  -C /tmp/opencode/gki136 M=$(pwd) modules \
  LOCALVERSION="-g8970630c07cd-ab9368044" \
  CONFIG_LOCALVERSION_AUTO=n
```

## 3. 核对

```bash
modinfo k60_vol_write.ko | grep vermagic
# 必须等于目标串（见第 0 节）
```

## 4. 传回手机

```bash
adb push /tmp/k60build/k60_vol_write.ko /data/adb/modules/k60_battery_unlock/kernel/
# 或任意方式（微信/USB）传到手机，找 agent 处理
```

## 5. 设备端验证（agent 执行）

```bash
insmod k60_vol_write.ko target_volt=4480000   # 先 4.48V 渐进
echo 100 > /sys/class/qcom-battery/fake_soh    # 借固件接受的写通道触发
# 看: dmesg | grep k60_volw   +  cat /sys/class/qcom-battery/fg1_vol_max
# 固件接受 → 充电 CV 目标抬高 → fcc 继续爬升
# 固件拒绝(rc!=0) → 4.44V 为物理极限，维持当前 5428 止损稳态
```

## 6. 常见问题

| 现象 | 处理 |
|---|---|
| insmod: Invalid argument | vermagic 不匹配 → 回第 0 节核对 |
| insmod: disagrees about version of symbol | 符号 CRC 不匹配 → 跑 --with-config 保底模式 |
| fetch android12-5.10 太慢 | git fetch --depth=1000 google android12-5.10 浅拉 |
| 找不到工具链 | ls /tmp/opencode/ddk/ 确认 clang-r416183b 存在 |

## 7. 安全红线

- target_volt 先 4480mV，无异常再 4500mV
- 异常（鼓包/发热>45°C）→ rmmod 即时还原
- 全程不碰系统分区，可逆
