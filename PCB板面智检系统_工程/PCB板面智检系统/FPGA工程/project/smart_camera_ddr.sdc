create_clock -name ref50 -period 20.000 [get_ports I_sysclk]
create_clock -name csi_bitclk -period 3.367003 [get_ports I_clk_hs_p]
derive_clocks
set_false_path -from [get_ports {I_reset_n I_osd_key_n I_color_keys_n[*] I_key_n[*]}]
# Receiver and pixel domain are asynchronous. Cut only synchronized controls;
# keep physical bounds on both FIFO Gray pointers and the diagnostic mailbox.
set_false_path -from [get_clocks {csi_bitclk u_mipi/u_clock.clkout}] -to [get_clocks ref50]
set_false_path -from [get_clocks ref50] -to [get_clocks {csi_bitclk u_mipi/u_clock.clkout}]
# INCK enable, config status, exposure Gray level and exposure status use two
# synchronizer stages. Pixel and 250 MHz serializer clocks stay related/timed.
set_false_path -from [get_clocks ref50] -to [get_clocks {u_clocks/sensor$u_sensor_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -from [get_clocks ref50] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -to [get_clocks ref50]
# Bundled data remains latched until the next mailbox request (>=250 ms).
# One source period bounds the skew/flight time of each registered Gray bus.

# Existing receiver byte-counter Gray bus remains physically bounded.
# Bound each new asynchronous FIFO Gray pointer to one source-clock period.
set_max_delay 13.468 -datapath_only -from [get_clocks {u_mipi/u_clock.clkout}] -through [get_nets {*input_events/wg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_false_path -hold -from [get_clocks {u_mipi/u_clock.clkout}] -through [get_nets {*input_events/wg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_max_delay 5.000 -datapath_only -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {*input_events/rg[*]}] -to [get_clocks {u_mipi/u_clock.clkout}]
set_false_path -hold -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {*input_events/rg[*]}] -to [get_clocks {u_mipi/u_clock.clkout}]
set_max_delay 5.000 -datapath_only -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {*returned_events/wg[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -hold -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {*returned_events/wg[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_max_delay 8.714 -datapath_only -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {*returned_events/rg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_false_path -hold -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {*returned_events/rg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
# Diagnostic bundled data is held until the acknowledged mailbox transaction.
# Single-bit credit and hold controls enter two-stage synchronizers.
set_false_path -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {*cache_request hold_display}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_false_path -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {ddr_phy ddr_phy_dup_* ddr_enable ddr_enable_dup_* ddr_test_done ddr_test_done_dup_* ddr_test_failed ddr_test_failed_dup_* ddr_dma_fault ddr_dma_fault_dup_* ddr_rst_n ddr_rst_n_dup_*}] -to [get_clocks {ref50 u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0] u_mipi/u_clock.clkout}]
# DDR-cycle heartbeat output removed: HC595 now owns LED1..3; no such crossing remains.
# PHY and camera reset assertion can cross domains. Each new domain releases
# reset through its own synchronizer, whose internal same-clock paths stay timed.
set_false_path -from [get_clocks {u_mipi/u_clock.clkout}] -through [get_nets {camera_reset_n}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_false_path -from [get_clocks ref50] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_false_path -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {release_pixel[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
# Only first-stage status D inputs are asynchronous. Keep the second-stage
# paths timed, including those used by the camera application's diagnostics.
# External reset enters a pair of local release flops in every FIFO domain;
# all pointer/control state then uses that local, synchronously released reset.
# Constrain the actual global reset net, which drives only local release
# synchronizers. TD's get_cells endpoint coercion does not select ASR recovery
# checks. Downstream overflow, FIFO, DMA and cache state uses local release nets
# and retains all same-clock recovery/removal checks.
set_false_path -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {*fifo_reset_n}] -to [get_clocks {u_mipi/u_clock.clkout u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_false_path -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {*fifo_reset_n}] -to [get_clocks {u_mipi/u_clock.clkout u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -from [get_clocks {u_mipi/u_clock.clkout}] -through [get_nets {*fifo_reset_n}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0] u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]

set_max_delay 8.714 -datapath_only -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {*raster_requests/wg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_false_path -hold -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {*raster_requests/wg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]

set_max_delay 5.000 -datapath_only -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {*raster_requests/rg[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -hold -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {*raster_requests/rg[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
# V24.1-net: symmetric direction of the raster_requests gray pointer (video -> DDR).
# One endpoint (u_app/ui_page_reg -> raster_requests/rg) crosses 50 MHz -> 200 MHz
# through combinational read-enable logic; bound it like the other CDC pointers.
set_max_delay 5.000 -datapath_only -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {*raster_requests/rg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_false_path -hold -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {*raster_requests/rg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]

set_max_delay 8.714 -datapath_only -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {*playback_events/wg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_false_path -hold -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {*playback_events/wg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]

set_max_delay 5.000 -datapath_only -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {*playback_events/rg[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -hold -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {*playback_events/rg[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]

# Cut only the asynchronous PIXEL hold control into the first DDR synchronizer.
# Packed cells may be named after unrelated co-located payload registers.
# The logical input net survives packing; DDR -> DDR synchronizer stages stay timed.
# review/query_v20_1_hold.log verifies hold_display -> QB -> hold_sync[0] -> QB.
set_false_path -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {*native_path$u_buffer/hold_display}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]

# V21 AI FIFO Gray pointers: bound each crossing to one source period.

# V23: UI page decoding is packed into the hold synchronizer LUT/FF slice.
# Reviewed first-stage data inputs only: logical D, packed LUT id and imf.
# Do not select the packed slice's imb (hold_sync[0] -> hold_sync[1]),
# or ib/ie (unrelated combinational photo receive logic in the same slice).

# ===== V24.1-net: ETHA RGMII timing (restored from verified V23 design) =====
rename_clock -name {tx_clk} [get_clocks {pll0_inst/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {clk_25m} [get_clocks {pll0_inst/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[2]}]
create_clock -name {I_a_rgmii_rxc} -period 8.000 -waveform {0.000 4.000} [get_ports {I_a_rgmii_rxc}]
create_generated_clock -name {O_a_tx_clk} -source [get_pins {pll0_inst/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[0]}] -master_clock {tx_clk} -divide_by 1.000 -phase 0.000 -add [get_ports {O_a_rgmii_txc}]
set_input_delay -clock [get_clocks I_a_rgmii_rxc] -max 2.800 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks I_a_rgmii_rxc] -min 1.200 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks I_a_rgmii_rxc] -max -clock_fall -add_delay 2.800 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks I_a_rgmii_rxc] -min -clock_fall -add_delay 1.200 [get_ports {{I_a_rgmii_rxd[*]} I_a_rgmii_rx_ctl}]
create_generated_clock -name {phy_tx_sample} -source [get_pins {pll0_inst/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[0]}] -master_clock {tx_clk} -divide_by 1 -phase 90 -add [get_ports {O_a_rgmii_txc}]
set_output_delay -clock [get_clocks phy_tx_sample] -max 1.000 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks phy_tx_sample] -min -1.000 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks phy_tx_sample] -max -clock_fall -add_delay 1.000 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks phy_tx_sample] -min -clock_fall -add_delay -1.000 [get_ports {O_a_rgmii_tx_ctl {O_a_rgmii_txd[*]}}]
set_clock_groups -asynchronous -group [get_clocks {I_a_rgmii_rxc}] -group [get_clocks {tx_clk O_a_tx_clk phy_tx_sample clk_25m}]
set_clock_uncertainty -setup 0.150 [get_clocks phy_tx_sample]
set_clock_uncertainty -hold 0.150 [get_clocks phy_tx_sample]
set_max_delay 8.000 -datapath_only -from [get_clocks {tx_clk}] -through [get_nets {*net_commands/wg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_false_path -hold -from [get_clocks {tx_clk}] -through [get_nets {*net_commands/wg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_max_delay 5.000 -datapath_only -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {*net_commands/rg[*]}] -to [get_clocks {tx_clk}]
set_false_path -hold -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {*net_commands/rg[*]}] -to [get_clocks {tx_clk}]
set_max_delay 5.000 -datapath_only -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {*net_responses/wg[*]}] -to [get_clocks {tx_clk}]
set_false_path -hold -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {*net_responses/wg[*]}] -to [get_clocks {tx_clk}]
set_max_delay 8.000 -datapath_only -from [get_clocks {tx_clk}] -through [get_nets {*net_responses/rg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_false_path -hold -from [get_clocks {tx_clk}] -through [get_nets {*net_responses/rg[*]}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_false_path -through [get_nets {u_network/stream_rst_n}]

# V24.2: Do not constrain every pin of a packed rg_reg slice to 5 ns.
# The slice also contains unrelated pixel-domain write-pointer/full logic.
# Its 50 MHz synchronous paths retain the normal 20 ns clock requirement.
# The existing clock-qualified Gray-pointer bounds above remain in force.




# V26.1.1 coherent passive diagnostic mailboxes.
set_false_path -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {camera_diagnostics/request}] -to [get_clocks {u_mipi/u_clock.clkout}]
set_false_path -from [get_clocks {u_mipi/u_clock.clkout}] -through [get_nets {camera_diagnostics/acknowledge}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_max_delay 13.468 -datapath_only -from [get_clocks {u_mipi/u_clock.clkout}] -through [get_nets {camera_diagnostics/held[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -hold -from [get_clocks {u_mipi/u_clock.clkout}] -through [get_nets {camera_diagnostics/held[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {ddr_diagnostics/request}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
set_false_path -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {ddr_diagnostics/acknowledge}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_max_delay 5.000 -datapath_only -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {ddr_diagnostics/held[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -hold -from [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}] -through [get_nets {ddr_diagnostics/held[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_max_delay 13.468 -datapath_only -from [get_clocks {u_mipi/u_clock.clkout}] -through [get_nets {byte_gray[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -hold -from [get_clocks {u_mipi/u_clock.clkout}] -through [get_nets {byte_gray[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]





# V26.5.1 lift bundled-data CDC; only asynchronous first-stage controls.
set_false_path -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {lift_bridge/request}] -to [get_clocks {tx_clk}]
set_false_path -from [get_clocks {tx_clk}] -through [get_nets {lift_bridge/acknowledge}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -from [get_clocks {tx_clk}] -through [get_nets {lift_bridge/status_request}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {lift_bridge/status_ack}] -to [get_clocks {tx_clk}]
set_max_delay 8.714 -datapath_only -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {lift_bridge/held_target[*]}] -to [get_clocks {tx_clk}]
set_false_path -hold -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {lift_bridge/held_target[*]}] -to [get_clocks {tx_clk}]
set_max_delay 8.000 -datapath_only -from [get_clocks {tx_clk}] -through [get_nets {lift_bridge/held_status[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -hold -from [get_clocks {tx_clk}] -through [get_nets {lift_bridge/held_status[*]}] -to [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}]
set_false_path -through [get_nets {lift_bridge/rst_n}]




# Local autofocus ownership is a single level into stage 0 of a two-flop sync.
set_false_path -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_nets {u_network/focus_lock}] -to [get_clocks {tx_clk}]



# V26.1 physical hold CDC binding: pixel inputs to DDR stage 0 only.
set_false_path -from [get_clocks {u_clocks/u_video_pll/u_PH1P_PHY_PLL.clkc[0]}] -through [get_pins {u_pipeline/native_path$u_buffer/hold_sync_reg[0]_syn_2.ie u_pipeline/native_path$u_buffer/hold_sync_reg[0]_syn_2.ima u_pipeline/native_path$u_buffer/hold_sync_reg[0]_syn_2.imb}] -to [get_clocks {u_ddr/u_controller/u_ddrmc_x32/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_top/u_ddrphy_clk/u_pll1/u_pll_inst.clkc[0]}]
