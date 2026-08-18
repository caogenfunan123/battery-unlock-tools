# K60 电池解锁 · 完整操作手册（从编译到扫描）

> 适用：Redmi K60 (mondrian) / android12-5.10 GKI / KernelSU 已 root
> 目录：1 电脑准备 -> 2 编译探针 -> 3 推送 -> 4 手机加载 -> 5 主动扫描 -> 6 结果解读 -> 7 排错 -> 8 安全红线

---

## 0. 你电脑上已有的东西（不用重装）

- 内核源码树：/tmp/opencode/gki136 （android12-5.10 GKI，源码已 checkout 到 g8970630c07cd）
- 编译器：/tmp/opencode/ddk/clang-r416183b （Android 12.0.5，vermagic 匹配专用）
- 编译目录：/tmp/k60build （集合所输出目录）

> 一旦换电脑/清目录，回到 BUILD.md 先重建这两件套。

## 1. 下载源码 + 设定构建目标

每次编译一个新模块就这三步：

```bash
cd /tmp/k60build

# 从仓库拉最新源码（jsdelivr 快）
curl -kL -o k60_scanprobe.c \
  https://raw.githubusercontent.com/caogenfunan123/battery-unlock-tools/main/kernel/k60_scanprobe.c

# 指定本次要编译哪个 .c（一行一个 obj-m，多个模块用空格）
echo 'obj-m := k60_scanprobe.o' > Kbuild
```

## 2. 编译（vermagic 固定公式，必须原样）

```bash
make -C /tmp/opencode/gki136 M=/tmp/k60build modules \
  LOCALVERSION="-g8970630c07cd-ab9368044" CONFIG_LOCALVERSION_AUTO=n
```

成功标志：

```bash
ls -la /tmp/k60build/k60_scanprobe.ko   # 存在且 >5KB
# 可选校验:
/tmp/opencode/ddk/clang-r416183b/bin/llvm-readelf -n k60_scanprobe.ko \
  | grep vermagic   # 必须含 5.10.136-android12-9-00003-g8970630c07cd-ab9368044
```

## 3. 推送手机

任选其一：

```bash
# A. USB adb
adb push /tmp/k60build/k60_scanprobe.ko /sdcard/Download/111111/

# B. 微信/QQ/网盘 传文件后复制到 Download/111111/
# C. 传 GitHub 仓库后让 agent 拉取
```

## 4. 手机端加载（agent 会执行，也可手打）

```bash
su
cp /sdcard/Download/111111/k60_scanprobe.ko /data/local/tmp/
chmod 755 /data/local/tmp/k60_scanprobe.ko
insmod /data/local/tmp/k60_scanprobe.ko      # 先被动模式挂载
dmesg | grep k60_scan | tail -5              # 应看到 v2 loaded
```

## 5. 主动扫描（关键一步）

确认没在充电（扫描会向每个 prop 发写，涉及 USB/VBUS 的 prop 会短暂干扰）。

```bash
echo 160 > /sys/module/k60_scanprobe/parameters/max_prop   # 扫描范围 0..160
echo 1    > /sys/module/k60_scanprobe/parameters/scan      # 开始扫描
sleep 30
dmesg | grep -E "k60_scan|Error in response" | tail -100
```

## 6. 结果解读

- 扫描日志：`k60_scan: SCAN DONE sent 2x(161) props`（约30秒完成）
- **固件接受判定**：prop 写入后 dmesg 里**没有** `Error in response for opcode 0x51 prop_id N` = 固件接受写入
- 已知接受（实证 10 个）：83,88,90,92,93,102,103,104,108,82
- **新发现 = 110~160 区那些没有报错的 prop** → 重点核对：referance_power / deltafv / night_charging / mtbf_current / shutdown_delay / fb_blank
- 把新 prop 名单发 agent → 逐个验证对 fcc/vol_max/学习的影响

## 7. 排错

| 现象 | 原因 | 解法 |
|------|------|------|
| make 报函数/变量未定义 | Kbuild 里 obj 名与 .c 名不符 | 检查 echo 行与文件名一致 |
| insmod 报 Invalid argument | vermagic 不匹配 | 重新核对编译公式 |
| insmod 报 Unknown symbol | 用了未导出函数 | 通知 agent 换实现 |
| 扫描无 SCAN DONE | workqueue 没跑 | 检查 dmesg 有无 register 失败 |

## 8. 安全红线（血泪教训）

| 节点 | 危险 | 规则 |
|------|------|------|
| fake_soc | **写 0/<10 直接强制关机** | 只写当前电量附近值，永不写 0/个位数 |
| vbus_disable | 断充 | 测试后立即写回 0 |
| ship_mode_en / shipmode_count_reset | 休眠/关机模式 | 不碰 |
| wireless_fw_update | 固件升级触发 | 不碰 |
| verify_digest / request_vdm_cmd | 认证握手 | 不碰 |
| fg1_fcc / fg1_vol_max 直写 | 固件不理（已验证） | 省时间别试 |
