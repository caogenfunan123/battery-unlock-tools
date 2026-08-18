# 下一步作战指南（K60 容量突破 · 第二波）

> 更新于 2026-08-18。上一波结论：prop126 电压写入被固件拒收，4.44V = 物理极限；
> fake_soh(120/150) 注入无联动（fg1_soh 不动）。编译管线已打通（vermagic 完美对齐）。
> 本指南 = 用编译好的模块开两条新路线。

## 已确认事实（勿重复踩坑）

| 通道 | 结果 |
|---|---|
| syfs 直写 fg1_vol_max / voltage_max / fg1_soh | ❌ Permission denied |
| prop126 借道写电压 (k60_vol_write) | ❌ 固件静默拒收 (fg1_vol_max 不动) |
| fake_soh=120/150 注入 | ❌ 无联动 (fg1_soh 恒定 100, fcc 不动) |
| smart_batt=0 (驱动级) | ✅ **+111 (5317→5428), 稳定** |
| fake_cycle=1 锁循环 | ✅ 止损 +118 机制有效 |
| 深循环结算 | ✅ 每轮完整循环 +100~200 |

## 两条开奖路线

### 路线① FCC 直写（最优先, 秒解容预期）

原理：k60_fcc_probe 借 fake_soh 写通道(XM-SET prop93) 转发为 prop120=FG1_FCC，
如果固件像接受 fake_cycle 一样接受 FCC 写入 → fcc 直接跳到目标值。

模块参数（k60_fcc_probe 已内置）：
\`\`\`bash
insmod /data/local/tmp/k60_fcc_probe.ko \
  target_prop=118  target_value=6200000    # 118=QMAX? 120=FCC? 试 target_prop=120
# 触发(借道): echo 100 > /sys/class/qcom-battery/fake_soh
# 看: cat /sys/class/qcom-battery/fg1_fcc   → 变 6200000 = 成功!!
\`\`\`

判定：
- fg1_fcc = 6200000 → **解容成功** → 立即验证充电速率/容量百分比
- fg1_fcc 不动 → 固件同样拒收 FCC → 此路 closed，转路线②

### 路线② 读路径改写（判满点抬升）

原理：k60_volt_probe 把固件 GET 返回的 vol_max 改写成 4500000。
若驱动用该值计算判满/充电目标 → 充电真实冲高（不只是显示）。

\`\`\`bash
insmod /data/local/tmp/k60_volt_probe.ko target_volt=4500000
# 拔插充电器触发充电, 观察:
#   cat /sys/class/power_supply/battery/voltage_now  充电峰值是否 > 4.46V
#   cat /sys/class/qcom-battery/fg1_vol_max          是否显示 4500000(改写生效)
#   dmesg | grep k60_volt  确认改写日志
\`\`\`

判定：
- 充电峰值 >4.46V（如 4.50V）→ **电压实破**, 每轮循环 fcc 涨幅加大
- 充电峰值仍 4.44V → 驱动不用该值 → 此路也 closed → 转"稳态深循环"方案

### 保底方案（两条路线都失败时）

smart_batt=0 + fake_cycle=1 + 深循环常态爬升：
\`\`\`
放电到 10~15% → 插满不拔 → 结算 +100~200/轮 → 4-6 轮 → 6200± 封顶
当前 5428 → 预计 ~3 周达到 6200
\`\`\`

## 编译一次出全部模块（build_all.sh）

\`\`\`bash
# 电脑上:
curl -kL -o build_all.sh https://raw.githubusercontent.com/caogenfunan123/battery-unlock-tools/main/scripts/build_all.sh
bash build_all.sh                 # 或 --with-config 保底(需手机USB连电脑拉真实config)
# 产出: /tmp/k60build/k60_all_kos.tar.gz (5个.ko)
# 送回手机: adb push ... /data/local/tmp/  或传仓库/微信
\`\`\`

脚本自动：commit 对齐(g8970630c07cd) + LOCALVERSION(-g8970630c07cd-ab9368044) + 5模块 + vermagic 核对。

## 手机端测试序列（agent 执行, 顺序测试防干扰）

1. 卸旧模块: rmmod k60_vol_write（如有残留）
2. 路线①: fcc_probe 测试（5分钟, 即刻见分晓）
3. 路线②: volt_probe 测试（需一次完整充电观察, 半天）
4. 全失败 → 回保底深循环 + 守护锁定（当前已在跑）

## 安全红线（不变）

- 电压目标 ≤4500mV；路线②首次用 4480 渐进
- 温度 >45°C 或鼓包迹象 → 立即 rmmod + 拔充电器
- 所有操作可逆（模块可卸载, 参数可重设）
- 不碰系统分区, 不动电池硬件
