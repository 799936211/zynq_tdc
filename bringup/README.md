# TDC 板级烧录验证 + 码密度标定方案（AX7010 冒烟测试工程）

对应项目待办的第 1 步「板子烧录验证」。这是一个**纯 PL、独立于主 BD 工程**的冒烟验证工程：
不依赖 PS、不需要 xsa/Vitis，JTAG 下载 bit 即可验证 TDC 核心链路，并顺手完成
DNL/INL 码密度标定（趁 SPAD 信号还没接进来，这是唯一能做干净标定的窗口）。

## 设计要点

- 直接例化仓库里**未修改**的 `TDCchannel`（`AXITDC/src/*.vhd`），NTaps=192，
  时钟用板上 50 MHz 晶振（U18）经 MMCM 升到 **300 MHz**，与主工程降频后的目标一致。
- 双通道同时验证。hit 源由 VIO 切换：
  - `hit_sel=0`：KEY1/KEY2（N15/N16）——按键冒烟测试
  - `hit_sel=1`：片上**环形振荡器**激励——与 TDC 时钟完全不相关，是码密度测试的标准激励
- LED：M14 = 心跳（~1.1 Hz，验证 300 MHz 时钟域活着），M15 = 每写一个时间戳翻转一次。
- ILA 带存储限定（storage qualification）：只在 `we=x"FF"`（时间戳写 BRAM 的那个周期）
  采样，4096 深度 = 4096 个时间戳，与时间跨度无关。
- 时间戳格式（`control.vhd`）：`ts(31:0) = coarse(24b) & fine(8b)`，fine 即延迟链 bin 号。

## 文件清单

| 文件 | 作用 |
|---|---|
| `src/tdc_bringup_top.vhd` | 冒烟验证顶层（双通道 + VIO + ILA + LED） |
| `src/hit_gen.vhd` | 环形振荡器异步激励（码密度用） |
| `src/tdc_bringup.xdc` | 引脚/时钟约束 + LUTLP-1 降级 |
| `tcl/make_bringup_project.tcl` | 一键建工程（Vivado 2025.2） |
| `analysis/code_density.py` | ILA 导出 CSV → 直方图 / DNL / INL / RMS 分辨率 |

## 一、建工程、生成 bit

把整个 `bringup` 目录拷到仓库根目录下（与 `AXITDC/` 同级），然后：

```tcl
# Vivado Tcl Console
cd <repo>/bringup/tcl
source make_bringup_project.tcl
launch_runs impl_1 -to_step write_bitstream -jobs 8
```

预期：WNS > 0（主工程同频率同核心已收敛，新增逻辑很少，正常应余量更大）；
BRAM 增加约 12 块 BRAM36（ILA），总占用仍在 30% 以内。

> 若 300 MHz 不收敛，先把 `make_bringup_project.tcl` 里 `CLKOUT1_REQUESTED_OUT_FREQ`
> 降到 250 跑通流程再排查——但主工程已证明 300 可收敛，大概率不需要。

## 二、三级冒烟验证（每级通过再进下一级）

**Level 1 — 时钟与烧录**
JTAG 下载 bit。M14 心跳灯 ~1.1 Hz 闪烁 → 50 MHz 晶振、MMCM、300 MHz 时钟域全部正常。
不闪：检查 bit 是否下载成功（DONE 灯）、JTAG 链、U18 约束。

**Level 2 — 按键 hit 链路（VIO `hit_sel=0`）**
按动 KEY1，观察：
- M15 每按一次翻转（按键抖动 → 可能多写几条，属正常现象）；
- ILA 触发 `probe0 == 1`，应看到 `addr0` 递增、`ts0` 的 coarse 部分递增；
- VIO `probe_in0`（hit 计数器）递增。
KEY2 / `ts1`（probe2/probe3）同理。
> 注意：AX7010 按键按下为低、**松手产生上升沿**，TDC 是上升沿敏感，所以松手才记时间戳。

**Level 3 — 环形振荡器激励（VIO `hit_sel=1`）**
切到内部激励后，VIO 里两个 hit 计数器应持续自增（ch0 约 1 MHz、ch1 约 250 kHz 量级）。
ILA 连续触发应能瞬间抓满 4096 个时间戳。
> 若计数器不动：确认 bit 里确实包含 LUTLP-1 waiver（xdc 已带），
> 且综合后环形振荡器没被优化（查 synthesis log 中 `hit_gen` 的 KEEP 属性）。

## 三、ILA 抓取设置（Hardware Manager）

1. 连接后选中 `hw_ila_1`，Trigger Setup：
   - 触发条件：`probe0 == 1`（ch0 标定）或 `probe2 == 1`（ch1）；
   - Capture Setup：存储限定条件同样设 `probe0 == 1`（→ 每个样本都是一个有效时间戳）。
2. 把 `probe1`(ts0)、`probe3`(ts1) 的 radix 设为 **Hex**。
3. 触发位置设为靠后（如 window 的 90%），按 Run Trigger。
4. 抓满后右键 → **Export ILA Data...** 存 CSV。

## 四、码密度标定（DNL / INL）

单次 capture = 4096 个时间戳，192 个 bin 平均每 bin 才 ~21 个样本，统计噪声大。
**重复抓取 5 次以上**（VIO 里 `clr` 打一下再放开即可复位地址，重新触发），
把所有 CSV 一起喂给脚本，自动合并：

```bash
cd bringup/analysis
python code_density.py cap1.csv cap2.csv cap3.csv cap4.csv cap5.csv --channel 0 --out ch0
python code_density.py cap1.csv cap2.csv cap3.csv cap4.csv cap5.csv --channel 1 --out ch1
```

输出：终端统计 + `ch0_code_density.png`（直方图/DNL/INL 三联图）+ `ch0_bins.csv`（每 bin 明细）。

**判据**（对照原论文 350 MHz 数据，300 MHz 下理想 LSB ≈ 17.4 ps）：

| 指标 | 论文值 (350 MHz) | 验收参考 |
|---|---|---|
| DNL | −1.0 ~ +4.5 LSB | 无系统性缺失码，max ≲ +5 LSB |
| INL | +0.5 ~ +8.5 LSB | 单调累积形态，量级相当 |
| 单发 RMS 分辨率 | >11 ps | 20 ps 量级即正常（300 MHz 更粗） |

**把两次标定的原始 CSV 和图归档**（建议 `doc/calibration/2026-11-板号-ch0/`）。
接 SPAD 后前端噪声会淹没码密度分布，这组数据就是后续所有性能评估的基线。

## 五、常见问题

- **full 之后不再记数**：缓冲 2048 条写满后 FSM 停在 `RUN_DONE`（`control.vhd` 的行为），
  VIO 把 `run` 拉低再拉高（或打一次 `clr`）即可恢复。
- **综合报 combinatorial loop / bitgen 报 LUTLP-1**：xdc 里已把 LUTLP-1 降为 Warning，
  这是环形振荡器的预期告警，不是错误。
- **想提高单次 capture 深度**：把 `make_bringup_project.tcl` 中 `C_DATA_DEPTH` 改 8192/16384
  重建（注意 BRAM 预算，XC7Z010 共 60 块 BRAM36）。
- **想复现主工程的进位链布局**：xdc 尾部留了 `firstCarry` 的 LOC 模板，按需启用。

## 六、与后续待办的衔接

| 待办 | 本工程的铺垫 |
|---|---|
| 导出 xsa → Vitis 驱动 | 冒烟通过后回主 BD 工程 `write_hw_platform`；ILA/VIO 的调试手段可直接搬进主工程（mark_debug 或 BD 里加 ILA） |
| 接 SPAD 信号 | 外部信号接到哪个引脚，就把该引脚加进主工程 ports.xdc；先用本工程的 ILA 流程观察信号质量（脉宽、计数率）再接 TDC |
| 多通道扩展 | 本顶层就是 `TDCchannel` 多实例的模板；BRAM 缓冲改为独立例化即可绕开 AXI |
