# K60 高容电池容量解锁工具

**设备**: Redmi K60 (mondrian) · KernelSU 3.2.5 · 内核 5.10.136 GKI

## 项目背景

- 电池: 第三方 ~6500mAh 高容电芯（model_name=M11A_5160mah 为旧电芯残留标签）
- 问题: 固件将 fcc（满充容量）锁在 5259~5408mAh（连续循环衰减），qmax=6560 为 IC 校准真实上限
- 现状: 按 fcc 判满 → 高容电芯只充到 ~80% 就停
- 目标: fcc → 6200~6400mAh，显示电量与技术容量一致
- 约束: 不改系统分区（永久可逆）、不采纳硬件改阻方案、电压不越 4.5V 红线

## 核心机制（本项目研究发现）

### 1. fake_cycle 档位解锁（已验证生效）

- 固件按 cycle 计数查表衰减 fcc（如 cycle 157 → fcc 5290）
- 写入 fake_cycle 欺骗固件切换档位: 157→10→1 后 fcc 即时 +118（5290→5408）
- 写入值需匹配档位（写 0 越界被拒，取值范围 1..200 均显示 5408 为学习上限）

### 2. fcc 学习结算规则（实测）

- 仅在完整循环（深放 4% → 充满）结束时结算；浅充（79%→100%）不结算
- 深循环学习将 fcc 校准到「4.44V 电压下实际可充入电量」≈5300~5400（81% x 6560）
- 结论: 4.44V 判满线（fg1_vol_max）是物理瓶颈——硅碳电芯需 4.5V 以上才算满

### 3. 电压维度（突破方向）

- fg1_vol_max=4.44V / voltage_max=4.45V 由固件锁定，sysfs 写入被驱动拒绝
- 充电目标电压由 BQ2597x 副充芯片 I2C 寄存器（4.41V）控制，无 /dev/i2c 通道
- smart_batt（智能满充保护）关闭后电压无变化（10→0 驱动接受但非电压开关）
- 唯一路径: 内核 kprobe 借道写入 — 固件接受 fake_soh/fake_cycle 写入，借该通道改 prop126(FG1_VOL_MAX)=4.5V（见 kernel/k60_vol_write.c，待编译验证）

## 模块文件结构

```
k60_battery_unlock/
├── module.prop               # 模块信息 (描述: fake_cycle=1 循环解容)
├── service.sh / boot-completed.sh   # 开机: fake_cycle 锁 + 守护启动 + WebUI
├── scripts/
│   ├── charge_learn.sh       # 守护: 锁 fake_cycle=1 + 触发学习 + 锁 soh
│   ├── charge_watch.sh       # 15s 采样日志 (fcc/rm/电压/电流/温度)
│   ├── fcc_watch.sh          # 110s 监测 fcc 变化落日志
│   └── kill_sim.sh / real_soc_daemon.sh  # 显示层 (真实电量)
├── webroot/                  # Web 控制台 (http://127.0.0.1:8899, KSU WebUI 自适应)
│   ├── index.html / style.css / app.js
│   └── cgi-bin/api.sh        # 状态/锁环/学习/soh/日志 API (CORS)
└── kernel/                   # kprobe 内核模块 (需 PC 编译, 见 build_vol_write.sh)
    ├── k60_vol_write.c       # 借道写 FG1_VOL_MAX=4.5V (待编译)
    ├── k60_volt_probe.c      # 读响应改写: 显示 4.5V (仅显示层)
    ├── k60_batt_probe.c      # 拦截 BATTERY 0x31 写入改 BATT_CHG_FULL
    ├── k60_fcc_probe.c       # 借 fake_soh 通道探测容量类 prop 可写性
    └── k60_fcc_unlock.c      # (legacy)
```

## 使用说明

### 安装（KernelSU）

1. 将模块目录打包为 zip 安装进 KernelSU，或直接拷贝到 /data/adb/modules/
2. 重启后守护自动运行: fake_cycle 锁定 + 显示层修正 + WebUI
3. 浏览器打开 http://127.0.0.1:8899 或 KSU App → 模块 WebUI 查看状态

### 深度循环解容流程

1. 放电至 >=10%（不要自动关机，3.1V 保护线）
2. 插上充电器充满（不中途拔插），充满后再拔
3. 观察 fcc 是否上涨（/data/local/tmp/fcc_history.log）
4. 重复 2-3 轮后 fcc 稳定在物理上限

### 重要日志

```
/data/local/tmp/charge_learn.log    # 守护日志
/data/local/tmp/charge_watch.log    # 15s 采样
/data/local/tmp/fcc_history.log     # fcc 变化记录
/data/local/tmp/real_soc.log        # 真实电量显示
```

## 当前状态（2026-08-18）

| 项 | 值 |
|---|---|
| fcc | 5317mAh（5408 → 深循环校准后） |
| qmax | 6560mAh（IC 校准上限） |
| 真实容量占比 | 81%（4.44V 判满物理极限） |
| smart_batt | 0（已关） |
| fake_cycle | 1（锁定） |
| 解容上限 | 6200-6400 需电压抬升至 4.5V（内核钩子待验证） |

## 待办 / 突破方向

1. PC 编译 k60_vol_write.ko（scripts/build_vol_write.sh 一键）→ 借道写 4.5V → 验证固件是否接受 prop126 写入
2. 若接受: 充电 CV 目标抬高 → fcc 学习跟随上涨 → 目标 6200-6400
3. 若拒绝: 确认 4.44V 为不可突破物理上限，维持止损锁定（当前 5317 不再衰减）

## 回滚（全程不碰系统分区）

- 卸载模块 / 删除 /data/adb/modules/k60_battery_unlock/
- 删除 disable 反向恢复其它模块（battery-simulator / k60_full_test）
- 移除脚本: /data/local/tmp/{charge_learn,charge_watch,fcc_watch,real_soc,httpd}*.sh
- 恢复显示: echo 0 > /sys/class/qcom-battery/fake_soc（若有）

## 安全红线（务必遵守）

- 电压永不超 4.5V（硅碳电芯膨胀/析锂风险）
- 放电永不触自动关机（3.1V 保护线，深放损伤电芯）
- 内核模块均带 target_volt 参数，先 4480mV 渐进验证，rmmod 即时还原
