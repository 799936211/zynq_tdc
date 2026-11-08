# ==============================================================================
# tdc_bringup constraints - ALINX AX7010 (XC7Z010-1CLG400)
# ==============================================================================

# ---- 50 MHz PL oscillator (MRCC) ----
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports clk50]
create_clock -period 20.000 -name pl_clk [get_ports clk50]

# ---- Keys (hit inputs) ----
# AX7010 PL keys are idle-high, pressed-low. The TDC is rising-edge sensitive,
# so a timestamp is generated on key RELEASE (bounce gives extra timestamps -
# expected and harmless for the smoke test).
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports key0]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports key1]

# ---- LEDs ----
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports {led[1]}]

# ---- Asynchronous inputs: no timing relationship to clk300 ----
set_false_path -from [get_ports key0]
set_false_path -from [get_ports key1]

# ---- Ring oscillator: allow the intentional combinatorial loop ----
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]

# ---- Optional: lock the start of the carry chains for reproducibility ----
# Same idea as the original ports.xdc (left commented there as well).
# Enable after checking placement in the main project; pick free slice columns.
#set_property LOC SLICE_X2Y25 [get_cells ch0/Delay_line/firstCarry]
#set_property LOC SLICE_X17Y25 [get_cells ch1/Delay_line/firstCarry]
