# 固件探针使用指南（k60_idscan.ko）

> 目的：把 Redmi K60 (mondrian) 这台机器**真实固件属性表**（XM prop id 白名单）
> 从固件里挖出来——不再依赖源码枚举（源码编号会因 CONFIG 开关漂移，不可靠）。
> 探针是**只读观测**，零副作用：kprobe 抓 driver→firmware 的每一条消息并打印。

## 为什么需要它

- 之前的攻击全靠猜 prop id（fake_soh=93 实测、其余推断）——**费半天还大多被拒**
- 源码枚举（xm_property_id）在不同内核/机型间编号会偏移（有 CONFIG 开关插值）
- k60_idscan 直接观测固件流量：**哪些 prop 系统平时就写（HAL/驱动自写）＝固件白名单**
- 拿到真实 id 表 → 精确测试剩余"指令类" prop（SET_REFERANCE_POWER/DELTAFV 等）
  → 找出能影响充电功率/学习链路的真正入口

## 1. 电脑编译

```bash
cd /tmp/k60build    # 你的编译目录（管线已验证）
curl -kL -o k60_idscan.c https://raw.githubusercontent.com/caogenfunan123/battery-unlock-tools/main/kernel/k60_idscan.c
echo 'obj-m := k60_idscan.o' > Kbuild

make -C /tmp/opencode/gki136 M=/tmp/k60build modules \
  LOCALVERSION="-g8970630c07cd-ab9368044" CONFIG_LOCALVERSION_AUTO=n

# 期望: /tmp/k60build/k60_idscan.ko
ls -la /tmp/k60build/k60_idscan.ko
```

## 2. 送到手机

```bash
# 方式A: USB 直推
adb push /tmp/k60build/k60_idscan.ko /data/local/tmp/

# 方式B: 推 GitHub 仓库(commit) 让 agent 拉
# 或微信/USB 拷到 Download 后喊 agent
```

## 3. 手机端加载（agent 执行）

```bash
insmod /data/local/tmp/k60_idscan.ko             # 默认 max_lines=200 rate_ms=100
# 观察 1-3 分钟（期间 HAL 周期写、充电事件、学习结算都会被捕获）
dmesg | grep k60_scan | tail -80

# 需要更久/更快:
echo 50  > /sys/module/k60_idscan/parameters/max_lines   # 控制日志量
echo 0   > /sys/module/k60_idscan/parameters/enable      # 暂停
echo 1   > /sys/module/k60_idscan/parameters/enable      # 恢复
# 结束:
rmmod k60_idscan
```

## 4. 输出格式解读

```
k60_scan: opcode=0x51 prop=93 val=100         # 0x51=写通道 prop93=fake_soh
k60_scan: opcode=0x50 prop=120 val=0          # 0x50=读通道 prop120=FCC
k60_scan: opcode=0x31 prop=18 val=0           # 0x31=电池通道 prop18
```

重点盯：
- **system/HAL 周期性写**: 哪个 prop 被反复写 = 固件接受（白名单）
- **学习结算**: 充放电切换瞬间哪个 prop 出现 = 学习链路入口
- **SMART_BATT 写入**: HAL 写 smart_batt 的真实 id（确认我们守护打的是不是同一点）

## 5. 拿到表之后

1. 确认/纠正已知 id（smart_batt/fake_soh/fake_cycle/start_learn）
2. 测"指令类" prop（SET_CONSTANT_POWER / SET_REFERANCE_POWER / DELTAFV / CHG_DEBUG）
   用已验证管线编 k60_fcc_probe 变体，把 target_prop 设成真实 id 逐个发
3. 固件接受 + 有充电影响 → 新通道达成；全部只读 → 固件地图确认全封闭，回到深循环路线

## 注意事项

- 只观测不改写，加载无风险
- 日志会刷 dmesg（rate_ms 默认 100ms 限速，max_lines=200 封顶）
- 结束时 rmmod，不留钩子
