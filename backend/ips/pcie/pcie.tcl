create_ip -name pcie4_uscale_plus -vendor xilinx.com -library ip -version 1.3 \
    -module_name pcie4_uscale_plus_0 -dir $dir_ip_gen -force

set_property -dict [list CONFIG.PL_LINK_CAP_MAX_LINK_SPEED {8.0_GT/s} \
    CONFIG.PL_LINK_CAP_MAX_LINK_WIDTH {X16} \
    CONFIG.AXISTEN_IF_EXT_512_RQ_STRADDLE {true} \
    CONFIG.AXISTEN_IF_EXT_512_RC_4TLP_STRADDLE {false} \
    CONFIG.axisten_if_enable_client_tag {true} \
    CONFIG.PF0_DEVICE_ID {903F} \
    CONFIG.PF2_DEVICE_ID {943F} \
    CONFIG.PF3_DEVICE_ID {963F} \
    CONFIG.pf0_bar0_size {4} \
    CONFIG.pf0_bar1_enabled {true} \
    CONFIG.pf0_bar1_type {Memory} \
    CONFIG.pf0_bar1_scale {Megabytes} \
    CONFIG.pf0_bar1_size {2} \
    CONFIG.pf0_dev_cap_max_payload {512_bytes} \
    CONFIG.extended_tag_field {false} \
    CONFIG.pf1_bar0_size {4} \
    CONFIG.pf1_bar1_enabled {true} \
    CONFIG.pf1_bar1_type {Memory} \
    CONFIG.pf1_bar1_scale {Megabytes} \
    CONFIG.pf1_bar1_size {2} \
    CONFIG.axisten_if_width {512_bit} \
    CONFIG.pf2_bar0_size {4} \
    CONFIG.pf2_bar1_enabled {true} \
    CONFIG.pf2_bar1_type {Memory} \
    CONFIG.pf1_bar1_scale {Megabytes} \
    CONFIG.pf1_bar1_size {2} \
    CONFIG.pf3_bar0_size {4} \
    CONFIG.pf3_bar1_enabled {true} \
    CONFIG.pf3_bar1_type {Memory} \
    CONFIG.pf3_bar1_scale {Megabytes} \
    CONFIG.pf3_bar1_size {2} \
    CONFIG.mode_selection {Advanced} \
    CONFIG.coreclk_freq {500} \
    CONFIG.plltype {QPLL1} \
    CONFIG.axisten_freq {250}] [get_ips pcie4_uscale_plus_0]