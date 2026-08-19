# fcc_unlock v3.1 · 编译与加载完整说明

> 适用：Redmi K60 (mondrian) / 内核 5.10.136-android12-9-00003-g8970630c07cd-ab9368044（GKI 2.0）
> 目标：把 fg1_fcc 从 ~5428mAh 解锁到 6500000 uAh（对应设计容量 6560mAh）

---

## 1. 这套方案为什么这么设计

GKI 内核（Android 12+）做了加固，以下内核 API 模块不可用：

| API | 状态 | 原因 |
|---|---|---|
| kallsyms_lookup_name | **不导出** | 已从导出符号表移除，模块加载即报 Unknown symbol |
| filp_open | 需 MODULE_IMPORT_NS | 在 VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver namespace |
| kernel_read | **不导出** | 同 VFS 加固 |

所以 v3.1 采用：**用户态取址 + insmod 传参**，模块零文件依赖。

\`\`\`
用户态(root) 读 /proc/kallsyms 拿 3 个符号地址
        │  insmod fcc_unlock.ko chg_write=0x.. prop_map=0x.. psy_get=0x..
        ▼
模块: psy_get("battery") → psy
      → power_supply_get_drvdata(psy) 拿 bcdev（qti 驱动 cfg.drv_data=bcdev）
      → 失败则 copy_from_kernel_nofault 安全扫描 psy 前 0x400 字节
      → 构造 glink 消息 → battery_chg_write(bcdev, msg, 24)
\`\`\`

## 2. 编译环境

### 2.1 交叉编译器（Android NDK）
\`\`\`bash
wget https://dl.google.com/android/repository/android-ndk-r27-linux.zip
unzip android-ndk-r27-linux.zip
export PATH=$PWD/android-ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH
export CROSS_COMPILE=aarch64-linux-android-
\`\`\`

### 2.2 GKI 内核源码（vermagic 必须匹配！）
手机的 \`uname -r\` = \`5.10.136-android12-9-00003-g8970630c07cd-ab9368044\`

模块的 vermagic 必须与运行内核一致，否则 insmod 报 \`Invalid module format\`。
用与手机同版本的 GKI sm8450 内核源码树：
\`\`\`bash
git clone <你的 GKI sm8450 内核源码仓库>
cd <内核目录>
make ARCH=arm64 gki_defconfig
make ARCH=arm64 modules_prepare
\`\`\`

### 2.3 编译
\`\`\`bash
cd /path/to/fcc_unlock
make KERNEL_SRC=/path/to/gki_kernel ARCH=arm64 CROSS_COMPILE=aarch64-linux-android-
\`\`\`
输出：\`fcc_unlock.ko\`

## 3. 源码注意事项（防断行 bug）

**历史坑**：fcc_unlock.c 里的 \`\\n\` 在传输/上传过程中曾多次被拆成真实换行，
导致 C 字符串字面量断行、编译直接报错。核对方法：

\`\`\`bash
# 每个 pr_info/pr_err/pr_warn 行应以 \"); 或 \", 结尾
grep -nE 'pr_(info|err|warn)' fcc_unlock.c
\`\`\`

仓库内当前 fcc_unlock.c（v3.1）已用 String.raw 写入修复，无需再改。

## 4. 加载

### 4.1 推送到手机
\`\`\`bash
adb push fcc_unlock.ko /data/local/tmp/
adb push load_fcc.sh /data/local/tmp/
\`\`\`

### 4.2 运行（一行搞定）
\`\`\`bash
adb shell su -c 'sh /data/local/tmp/load_fcc.sh'
\`\`\`

load_fcc.sh 自动完成：
1. \`echo 0 > /proc/sys/kernel/kptr_restrict\`（让 /proc/kallsyms 显示真实地址）
2. 从 /proc/kallsyms 提取三个地址（子串匹配，排除 .cfi_jt）
   - chg_write = battery_chg_write（带 [qti_battery_charger] 后缀）
   - prop_map = battery_prop_map
   - psy_get = power_supply_get_by_name
3. insmod 传参加载
4. 打印 dmesg + fg1_fcc

## 5. 验证

\`\`\`bash
cat /sys/class/qcom-battery/fg1_fcc       # 应显示 6500000
dmesg | grep fcc                          # 应有 SUCCESS
\`\`\`

## 6. 排错表

| dmesg 日志 | 含义 | 处理 |
|---|---|---|
| \`Unknown symbol kallsyms_lookup_name\` | 旧版用了未导出符号 | 换 v3.1 |
| \`module uses symbol from namespace VFS...\` | 用了 VFS namespace 符号 | 换 v3.1（不再读文件） |
| \`\`0x'\` invalid for parameter\` | 传参格式错/地址为空 | 用 load_fcc.sh 加载 |
| \`missing addresses\` | 没传参 | 用 load_fcc.sh |
| \`power_supply_get_by_name(battery) failed\` | psy_get 地址错 | 核对 kallsyms |
| \`drv_data ... not bcdev (map mismatch)\` | drv_data 非 bcdev | 走扫描兜底（正常） |
| \`no bcdev found\` | 扫描也失败 | 把 dmesg 发来调 0x150 偏移 |
| \`write failed ret=...\` | glink 消息被固件拒 | 核对 prop_id/owner/opcode |
| insmod \`Invalid module format\` | vermagic 不匹配 | 用同版本 GKI 树重编 |

## 7. 关键常量

\`\`\`
PMIC_GLINK_OWNER_XIAOMI_BATTERY_CHG = 0x800A   (glink owner)
PMIC_GLINK_CMD_REQ                  = 1        (消息类型)
BC_XM_STATUS_SET                    = 0x51     (opcode)
XM_PROP_FG1_FCC                     = 128      (属性 ID)
FCC_TARGET                          = 6500000  (目标容量 uAh)
BCDEV_PSY_LIST_MAP_OFF              = 0x150    (bcdev->psy_list[0].map 偏移)
\`\`\`

消息结构（24 字节）：
\`\`\`
struct battery_charger_req_msg {
    struct pmic_glink_hdr { u32 owner; u32 type; u32 opcode; }  // 12B
    int battery_id;    // 0
    int property_id;   // 128
    int value;         // 6500000
} __packed;           // 共 24B
\`\`\`

## 8. 文件结构

\`\`\`
fcc_unlock/
├── Makefile          # 编译脚本
├── fcc_unlock.c      # 模块源码 v3.1
├── load_fcc.sh       # 自动取址加载脚本
├── BUILD-GUIDE.md    # 本说明
└── README.md         # 简介
\`\`\`
