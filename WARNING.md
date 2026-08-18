# 危险节点警告（实战血泪）

## fake_soc —— 会干关机！
- 节点：/sys/class/qcom-battery/fake_soc（可写）
- **写入 0 或 <10 → 固件认为电池 0% → 触发低电强制关机（立即断电）**
- 实测事故：调试时 echo 0 > fake_soc 直接把手机关机
- **规则：只允许写当前 fg1_rsoc 附近的真实值，永不写 0 / 1 / 个位数**
- 用途不明：写 50/80 不影响 fg1_rsoc（66 保持），但 fake_soc 属性本身改变——固件/HAL 可能读它当真实电量

## 其它安全注意
- vbus_disable=1：断 VBUS（充电中会断充）——测后立即写回 0
- ship_mode_en / shipmode_count_reset：休眠模式相关——不要乱开
- wireless_fw_update / wireless_fw_force_update：固件升级触发器——不要碰
- verify_digest / request_vdm_cmd：认证握手相关——不要乱发

## 当前白名单（实测可写，安全）
83 thermal_remove / 88 smart_batt / 90 sport_mode / 92 fake_cycle /
93 fake_soh / 102 start_learn / 103 stop_learn / 104 set_learn_power /
108 constant_power / 82 fake_temp