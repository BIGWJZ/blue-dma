##-----------------------------------------------------------------------------
##
## (c) Copyright 2012-2012 Xilinx, Inc. All rights reserved.
##
## This file contains confidential and proprietary information
## of Xilinx, Inc. and is protected under U.S. and
## international copyright and other intellectual property
## laws.
##
## DISCLAIMER
## This disclaimer is not a license and does not grant any
## rights to the materials distributed herewith. Except as
## otherwise provided in a valid license issued to you by
## Xilinx, and to the maximum extent permitted by applicable
## law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
## WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
## AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
## BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
## INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
## (2) Xilinx shall not be liable (whether in contract or tort,
## including negligence, or under any other theory of
## liability) for any loss or damage of any kind or nature
## related to, arising under or in connection with these
## materials, including for any direct, or any indirect,
## special, incidental, or consequential loss or damage
## (including loss of data, profits, goodwill, or any type of
## loss or damage suffered as a result of any action brought
## by a third party) even if such damage or loss was
## reasonably foreseeable or Xilinx had been advised of the
## possibility of the same.
##
## CRITICAL APPLICATIONS
## Xilinx products are not designed or intended to be fail-
## safe, or for use in any application requiring fail-safe
## performance, such as life-support or safety devices or
## systems, Class III medical devices, nuclear facilities,
## applications related to the deployment of airbags, or any
## other applications that could lead to death, personal
## injury, or severe property or environmental damage
## (individually and collectively, "Critical
## Applications"). Customer assumes the sole risk and
## liability of any use of Xilinx products in Critical
## Applications, subject only to applicable laws and
## regulations governing limitations on product liability.
##
## THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
## PART OF THIS FILE AT ALL TIMES.
##
##-----------------------------------------------------------------------------
##
## Project    : UltraScale+ FPGA PCI Express v4.0 Integrated Block
## File       : xilinx_pcie4_uscale_plus_x1y2.xdc
## Version    : 1.3 
##-----------------------------------------------------------------------------
#
###############################################################################
# Vivado - PCIe GUI / User Configuration 
###############################################################################
#
# Family              # virtexuplus
# Part                # xcu200
# Package             # fsgd2104
# Speed grade         # -2
# PCIe Block          # X1Y2
# Xilinx BNo          # 15
#
# Link Speed          # Gen3 - 8.0 Gb/s
# Link Width          # X16
# AXIST Width         # 512-bit
# AXIST Frequ         # 250 MHz = User Clock
# Core Clock          # 500 MHz
# Pipe Clock          # 125 MHz (Gen1) : 250 MHz (Gen2/Gen3/Gen4)
# PLL TYPE            # QPLL1
# MSI-X TYPE          # HARD
#
# master_gt_quad_inx  # 3
# master_gt_container # 32
# gt_type             # gtye4
#
# Xilinx Reference Board is AU200
#
###############################################################################
# User Time Names / User Time Groups / Time Specs
###############################################################################
create_clock -name sys_clk -period 10 [get_ports sys_clk_p]
#
#set_false_path -from [get_ports sys_rst_n]
#set_property PULLUP true [get_ports sys_rst_n]

set_property IOSTANDARD POD12 [get_ports sys_rst_n]

set_property PACKAGE_PIN BD21 [get_ports sys_rst_n]

#
set_property PACKAGE_PIN AM10 [get_ports sys_clk_n]
set_property PACKAGE_PIN AM11 [get_ports sys_clk_p]
#

# LEDs for ZCU117
set_property PACKAGE_PIN BC21 [get_ports led_0]   
# sys_reset
set_property PACKAGE_PIN BB21 [get_ports led_1]   
# user_link_up 
set_property PACKAGE_PIN BA20 [get_ports led_2]   
#

set_property IOSTANDARD LVCMOS12 [get_ports led_0]
set_property IOSTANDARD LVCMOS12 [get_ports led_1]
set_property IOSTANDARD LVCMOS12 [get_ports led_2]
#
set_property DRIVE 8 [get_ports led_0]
set_property DRIVE 8 [get_ports led_1]
set_property DRIVE 8 [get_ports led_2]

#
#
# Clock for the 300 MHz clock is already created in the Clock Wizard IP.
# 300 MHz clock pin constraints.
set_property IOSTANDARD DIFF_SSTL12 [get_ports clk_300MHz_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports clk_300MHz_n]
set_property PACKAGE_PIN AY37 [get_ports clk_300MHz_p]
set_property PACKAGE_PIN AY38 [get_ports clk_300MHz_n]
#
#
# CLOCK_ROOT LOCKing to Reduce CLOCK SKEW
# Add/Edit  Clock Routing Option to improve clock path skew
#
# BITFILE/BITSTREAM compress options
# ##############################################################################
# Flash Programming Example Settings: These should be modified to match the target board.
# ##############################################################################
#
#
# sys_clk vs TXOUTCLK
set_clock_groups -name async18 -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gen_channel_container[32].*gen_gtye4_channel_inst[3].GTYE4_CHANNEL_PRIM_INST/TXOUTCLK}]]
set_clock_groups -name async19 -asynchronous -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gen_channel_container[32].*gen_gtye4_channel_inst[3].GTYE4_CHANNEL_PRIM_INST/TXOUTCLK}]] -group [get_clocks {sys_clk}]
#
#
#
#
#
#
# ASYNC CLOCK GROUPINGS
# sys_clk vs user_clk
set_clock_groups -name async5 -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks -of_objects [get_pins pcie4_uscale_plus_0_i/inst/pcie4_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_userclk/O]]
set_clock_groups -name async6 -asynchronous -group [get_clocks -of_objects [get_pins pcie4_uscale_plus_0_i/inst/pcie4_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_userclk/O]] -group [get_clocks {sys_clk}]
# sys_clk vs pclk
set_clock_groups -name async1 -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks -of_objects [get_pins pcie4_uscale_plus_0_i/inst/pcie4_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_pclk/O]]
set_clock_groups -name async2 -asynchronous -group [get_clocks -of_objects [get_pins pcie4_uscale_plus_0_i/inst/pcie4_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_pclk/O]] -group [get_clocks {sys_clk}]
#
#
#
# Add/Edit Pblock slice constraints for 512b soft logic to improve timing
#create_pblock soft_512b; add_cells_to_pblock [get_pblocks soft_512b] [get_cells {pcie4_uscale_plus_0_i/inst/pcie4_uscale_plus_0_pcie_4_0_pipe_inst/pcie_4_0_init_ctrl_inst pcie4_uscale_plus_0_i/inst/pcie4_uscale_plus_0_pcie_4_0_pipe_inst/pcie4_0_512b_intfc_mod}]
# Keep This Logic Left/Right Side Of The PCIe Block (Whichever is near to the FPGA Boundary)
#resize_pblock [get_pblocks soft_512b] -add {SLICE_X157Y300:SLICE_X168Y370}
#set_property EXCLUDE_PLACEMENT 1 [get_pblocks soft_512b]
#
set_clock_groups -name async24 -asynchronous -group [get_clocks -of_objects [get_pins pcie4_uscale_plus_0_i/inst/pcie4_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_intclk/O]] -group [get_clocks {sys_clk}]
#
#create_waiver -type METHODOLOGY -id {LUTAR-1} -user "pcie4_uscale_plus" -desc "user link up is synchroized in the user clk so it is safe to ignore"  -internal -scoped -tags 1024539  -objects [get_cells { pcie_app_uscale_i/PIO_i/len_i[5]_i_4 }] -objects [get_pins { pcie4_uscale_plus_0_i/inst/user_lnk_up_cdc/arststages_ff_reg[0]/CLR pcie4_uscale_plus_0_i/inst/user_lnk_up_cdc/arststages_ff_reg[1]/CLR }] 

