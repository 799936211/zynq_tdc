#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
code_density.py - TDC 码密度（code density）标定分析

输入：Vivado Hardware Manager 中 ILA 窗口 "Export ILA Data..." 导出的 CSV。
      导出前请把 ts0/ts1（probe1/probe3）的 radix 设为 Hex。
      可以一次传入多个 CSV（多次 capture 的结果会自动合并，统计量更足）。

用法：
  python code_density.py capture1.csv capture2.csv --channel 0
  python code_density.py run_*.csv --channel 1 --ntaps 192 --t-clk 3.3333 --out ch1

输出：
  终端打印：样本数、有效 bin 数、bin 宽 min/max (ps)、DNL/INL 范围 (LSB)、
            单发 RMS 分辨率估计
  PNG 图：  直方图 / DNL / INL 三联图 (<out>_code_density.png)
  CSV：     每 bin 的 count / width_ps / DNL / INL (<out>_bins.csv)

参考判据（原论文 350 MHz、192 taps）：
  DNL: -1 ~ +4.5 LSB, INL: +0.5 ~ +8.5 LSB, 分辨率 >11 ps
  300 MHz 下理想 LSB = 3333.3/192 ≈ 17.4 ps
"""

import argparse
import csv
import re
import sys

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def find_header_and_column(rows, col_pattern):
    """在 CSV 行中定位表头行，并返回 (表头行号, 目标列号)。"""
    pat = re.compile(col_pattern, re.IGNORECASE)
    for i, row in enumerate(rows):
        for j, cell in enumerate(row):
            if pat.search(cell.strip()):
                return i, j
    return None, None


def parse_value(text, radix):
    text = text.strip().replace(" ", "")
    if not text:
        return None
    text = re.sub(r"^(0x|0X|h)'?", "", text)
    try:
        if radix == "dec":
            return int(text, 10)
        if radix == "hex":
            return int(text, 16)
        # auto: 含 a-f 字母或长度 8 位 -> hex，否则 dec
        if re.search(r"[a-fA-F]", text) or len(text) >= 7:
            return int(text, 16)
        return int(text, 10)
    except ValueError:
        return None


def load_fine_codes(files, col_pattern, ntaps, radix):
    fines = []
    invalid = 0
    for path in files:
        with open(path, newline="", encoding="utf-8", errors="replace") as f:
            rows = list(csv.reader(f))
        hdr, col = find_header_and_column(rows, col_pattern)
        if hdr is None:
            print(f"警告: 在 {path} 中找不到匹配 '{col_pattern}' 的列，已跳过", file=sys.stderr)
            continue
        n_before = len(fines)
        for row in rows[hdr + 1:]:
            if col >= len(row):
                continue
            v = parse_value(row[col], radix)
            if v is None:
                continue
            fine = v & 0xFF          # timestamp = coarse(24b) & fine(8b)
            if fine >= ntaps:        # 编码器输出不可能超过 NTaps
                invalid += 1
                continue
            fines.append(fine)
        print(f"  {path}: 读取 {len(fines) - n_before} 个时间戳")
    if not fines:
        sys.exit("错误: 没有读到任何有效时间戳，检查列名/radix 设置")
    if invalid:
        print(f"警告: 丢弃 {invalid} 个超出 NTaps 的非法细码（可能列选错或同步异常）")
    return np.array(fines, dtype=int)


def main():
    ap = argparse.ArgumentParser(description="TDC code-density 标定分析")
    ap.add_argument("files", nargs="+", help="ILA 导出的 CSV，可多个")
    ap.add_argument("--channel", type=int, default=0, choices=[0, 1],
                    help="通道 0 -> probe1(ts0)，通道 1 -> probe3(ts3)")
    ap.add_argument("--col", default=None,
                    help="自定义列名正则（默认按 --channel 自动选择）")
    ap.add_argument("--ntaps", type=int, default=192)
    ap.add_argument("--t-clk", type=float, default=10.0 / 3.0,
                    help="TDC 时钟周期 ns（300 MHz -> 3.3333）")
    ap.add_argument("--radix", default="auto", choices=["auto", "hex", "dec"],
                    help="CSV 中时间戳的进制（建议导出时选 Hex）")
    ap.add_argument("--out", default="tdc", help="输出文件前缀")
    args = ap.parse_args()

    col_pat = args.col or (r"probe1" if args.channel == 0 else r"probe3")
    t_clk_ps = args.t_clk * 1000.0
    ntaps = args.ntaps

    print(f"读取通道 {args.channel}（列匹配 '{col_pat}'）...")
    fines = load_fine_codes(args.files, col_pat, ntaps, args.radix)
    n = len(fines)
    print(f"总样本数: {n}")

    counts = np.bincount(fines, minlength=ntaps).astype(float)
    widths = counts / n * t_clk_ps               # 每 bin 实际宽度 (ps)
    lsb = t_clk_ps / ntaps                        # 理想 LSB (ps)
    dnl = widths / lsb - 1.0
    inl = np.concatenate(([0.0], np.cumsum(dnl)))[:-1]

    used = counts > 0
    p = counts / n
    rms_ps = np.sqrt(np.sum(p * widths ** 2) / 12.0)

    print("\n===== 码密度标定结果 =====")
    print(f"时钟周期          : {t_clk_ps:.2f} ps ({1000.0 / args.t_clk:.1f} MHz)")
    print(f"理想 LSB          : {lsb:.2f} ps")
    print(f"有效 bin 数       : {int(used.sum())} / {ntaps}"
          + (f"（缺失 {int((~used).sum())} 个码！）" if (~used).any() else ""))
    print(f"bin 宽 min / max  : {widths.min():.2f} / {widths.max():.2f} ps")
    print(f"DNL  min / max    : {dnl.min():+.2f} / {dnl.max():+.2f} LSB   (论文: -1.0 / +4.5)")
    print(f"INL  min / max    : {inl.min():+.2f} / {inl.max():+.2f} LSB   (论文: +0.5 / +8.5)")
    print(f"单发 RMS 分辨率   : {rms_ps:.2f} ps")
    print(f"统计置信度参考    : 平均每 bin {n / ntaps:.1f} 个样本"
          + ("（建议 ≥100，多合并几次 capture）" if n / ntaps < 100 else ""))

    # 每 bin 明细
    bins_csv = f"{args.out}_bins.csv"
    with open(bins_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["bin", "count", "width_ps", "DNL_LSB", "INL_LSB"])
        for k in range(ntaps):
            w.writerow([k, int(counts[k]), f"{widths[k]:.3f}",
                        f"{dnl[k]:+.4f}", f"{inl[k]:+.4f}"])
    print(f"\n每 bin 明细已写入: {bins_csv}")

    # 三联图
    x = np.arange(ntaps)
    fig, axes = plt.subplots(3, 1, figsize=(10, 9), sharex=True)
    axes[0].bar(x, counts, width=1.0)
    axes[0].set_ylabel("count")
    axes[0].set_title(f"Code density - ch{args.channel}, N={n}, "
                      f"{1000.0 / args.t_clk:.0f} MHz, {ntaps} taps")
    axes[1].bar(x, dnl, width=1.0)
    axes[1].axhline(0, color="k", lw=0.8)
    axes[1].set_ylabel("DNL (LSB)")
    axes[2].bar(x, inl, width=1.0)
    axes[2].axhline(0, color="k", lw=0.8)
    axes[2].set_ylabel("INL (LSB)")
    axes[2].set_xlabel("bin (fine code)")
    fig.tight_layout()
    png = f"{args.out}_code_density.png"
    fig.savefig(png, dpi=150)
    print(f"图已保存: {png}")


if __name__ == "__main__":
    main()
