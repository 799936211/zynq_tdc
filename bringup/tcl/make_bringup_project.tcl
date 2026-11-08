# ==============================================================================
# Vivado project script: TDC board bring-up (pure PL, no PS)
# Tested flow target: Vivado 2025.2
#
# Usage (copy the whole "bringup" folder into the zynq_tdc repo root first,
# so that ../AXITDC resolves):
#   1. Open Vivado Tcl Console, cd to zynq_tdc/bringup/tcl
#   2. source make_bringup_project.tcl
#   3. launch_runs impl_1 -to_step write_bitstream -jobs 8
#      (or click Generate Bitstream in the GUI)
#
# The script reuses the UNMODIFIED channel sources from ../../AXITDC/src,
# creates clk_wiz (50 -> 300 MHz), VIO and ILA IPs, and sets the top.
# ==============================================================================

set script_dir  [file dirname [file normalize [info script]]]
set bringup_dir [file normalize [file join $script_dir ..]]
set repo_root   [file normalize [file join $bringup_dir ..]]

set proj_name tdc_bringup
set part      xc7z010clg400-1

if {![file exists [file join $repo_root AXITDC src TDCchannel.vhd]]} {
   puts "ERROR: AXITDC/src not found next to the bringup folder."
   puts "       Copy the bringup folder into the zynq_tdc repo root and re-run."
   return 1
}

create_project $proj_name [file join $bringup_dir $proj_name] -part $part -force
set_property target_language VHDL [current_project]

# ---- TDC channel sources (reuse as-is) ----
foreach f [glob -nocomplain [file join $repo_root AXITDC src *.vhd]] {
   add_files -norecurse $f
}

# ---- Bring-up sources & constraints ----
add_files -norecurse [file join $bringup_dir src hit_gen.vhd]
add_files -norecurse [file join $bringup_dir src tdc_bringup_top.vhd]
add_files -fileset constrs_1 -norecurse [file join $bringup_dir src tdc_bringup.xdc]

# ---- Clock wizard: 50 MHz -> 300 MHz (MMCM, VCO = 900 MHz) ----
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_0
set_property -dict [list \
   CONFIG.PRIMITIVE {MMCM} \
   CONFIG.PRIM_IN_FREQ {50.000} \
   CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {300.000} \
   CONFIG.MMCM_DIVCLK_DIVIDE {1} \
   CONFIG.MMCM_CLKFBOUT_MULT_F {18.000} \
   CONFIG.MMCM_CLKOUT0_DIVIDE_F {3.000} \
   CONFIG.USE_RESET {false} \
   CONFIG.USE_LOCKED {true} \
] [get_ips clk_wiz_0]

# ---- VIO: 2 x 32b inputs (hit counters), 3 x 1b outputs (sel/clr/run) ----
create_ip -name vio -vendor xilinx.com -library ip -module_name vio_0
set_property -dict [list \
   CONFIG.C_NUM_PROBE_IN {2} \
   CONFIG.C_PROBE_IN0_WIDTH {32} \
   CONFIG.C_PROBE_IN1_WIDTH {32} \
   CONFIG.C_NUM_PROBE_OUT {3} \
   CONFIG.C_PROBE_OUT0_WIDTH {1} \
   CONFIG.C_PROBE_OUT1_WIDTH {1} \
   CONFIG.C_PROBE_OUT2_WIDTH {1} \
   CONFIG.C_PROBE_OUT0_INIT_VAL {0x0} \
   CONFIG.C_PROBE_OUT1_INIT_VAL {0x0} \
   CONFIG.C_PROBE_OUT2_INIT_VAL {0x1} \
] [get_ips vio_0]

# ---- ILA: 6 probes, 4096 samples, storage qualification on we ----
# BRAM estimate: 84-bit x 4096 -> ~12 BRAM36 (20% of the 60 on XC7Z010).
# Raise C_DATA_DEPTH to 8192/16384 later for finer DNL statistics.
create_ip -name ila -vendor xilinx.com -library ip -module_name ila_0
set_property -dict [list \
   CONFIG.C_NUM_OF_PROBES {6} \
   CONFIG.C_DATA_DEPTH {4096} \
   CONFIG.C_PROBE0_WIDTH {1} \
   CONFIG.C_PROBE1_WIDTH {32} \
   CONFIG.C_PROBE2_WIDTH {1} \
   CONFIG.C_PROBE3_WIDTH {32} \
   CONFIG.C_PROBE4_WIDTH {4} \
   CONFIG.C_PROBE5_WIDTH {11} \
   CONFIG.C_EN_STRG_QUAL {1} \
   CONFIG.C_ADV_TRIGGER {false} \
   CONFIG.C_PROBE0_MU_CNT {2} \
   CONFIG.C_PROBE2_MU_CNT {2} \
   CONFIG.C_INPUT_PIPE_STAGES {1} \
] [get_ips ila_0]

generate_target all [get_ips]
set_property top tdc_bringup_top [current_fileset]
update_compile_order -fileset sources_1

puts "==============================================================="
puts " Project '$proj_name' created. Next:"
puts "   launch_runs impl_1 -to_step write_bitstream -jobs 8"
puts "==============================================================="
