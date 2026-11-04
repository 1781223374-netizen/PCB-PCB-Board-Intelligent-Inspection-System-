`timescale 1ns/1ps
`default_nettype none
// V26.3.1: native1080, CVT-RB ~49.88Hz at114.75MHz; raw SCAM default2fps.
// External DDR triple frame store, eight-line prefetch, native photo playback.
module smart_camera_ddr_top #(parameter BAYER_PATTERN=1,GRAYSCALE=0,ENABLE_FRAME_GUARD=1)(
    output wire O_phy_rst,
    input wire [3:0] I_a_rgmii_rxd,input wire I_a_rgmii_rx_ctl,I_a_rgmii_rxc,
    output wire [3:0] O_a_rgmii_txd,output wire O_a_rgmii_tx_ctl,O_a_rgmii_txc,
    input wire I_sysclk,I_reset_n,I_clk_hs_p,I_osd_key_n,
    input wire [7:0] I_key_n,
    input wire [1:0] I_color_keys_n,
    input wire [3:0] I_data_hs_p,I_data_lp_p,I_data_lp_n,
    inout wire IO_cam_scl,IO_cam_sda,
    output wire O_cam_rst_n,O_cam_inck,O_fep_power,
    output wire ddr_ck_p,ddr_ck_n,ddr_reset_n,ddr_cke,ddr_odt,ddr_cs_n,ddr_ras_n,ddr_cas_n,ddr_we_n,
    output wire [2:0] ddr_ba,output wire [13:0] ddr_addr,
    inout wire [1:0] ddr_dqs_p,ddr_dqs_n,ddr_dm,inout wire [15:0] ddr_dq,
    output wire O_hdmi_clk_p,
    output wire [2:0] O_hdmi_tx_p,
    output wire [3:0] O_led,
    input wire I_sd_miso,output wire O_sd_cs_n,O_sd_sck,O_sd_mosi,O_light,O_buzzer_n,O_servo_pwm
);
    // V24.1-net: Ethernet restored (ETHA) for PC image streaming and alarm flags.
    wire net_clk,net_clk90,net_clk25,net_lock;
    net_ui_pll pll0_inst(.refclk(I_sysclk),.reset(!I_reset_n),.lock(net_lock),
        .clk0_out(net_clk),.clk1_out(net_clk90),.clk2_out(net_clk25));
    wire [12:0] net_cmd;wire net_cmd_valid,net_cmd_ready;
    wire [129:0] net_response;wire net_response_valid,net_response_ready;
    wire [1:0] network_identity;wire network_profile_done;
    wire lift_apply_pixel,lift_ready_pixel,lift_apply_net,lift_enabled_net,lift_enabled_pixel,lift_control_ready;
    wire [15:0] lift_setting,lift_target_net,lift_applied_net,lift_applied_pixel;
    wire pixel_clk,serial_clk,inck,video_lock,cam_lock;
    clocking u_clocks(.refclk(I_sysclk),.reset(!I_reset_n),.pixel_clk(pixel_clk),.serial_clk(serial_clk),
        .cam_inck(inck),.video_lock(video_lock),.cam_lock(cam_lock));
    wire camera_ready=I_reset_n && cam_lock;
    wire display_ready=I_reset_n && video_lock;
    reg [3:0] release_sys=0,release_pixel=0;
    always @(posedge I_sysclk or negedge camera_ready)
        if(!camera_ready) release_sys<=0;else release_sys<={release_sys[2:0],1'b1};
    always @(posedge pixel_clk or negedge display_ready)
        if(!display_ready) release_pixel<=0;else release_pixel<={release_pixel[2:0],1'b1};
    wire cfg_done,cfg_error,clock_enable;
    wire [8:0] config_index;
    imx415_init u_init(.clk(I_sysclk),.rst_n(release_sys[3]),.sensor_rst_n(O_cam_rst_n),
        .clock_enable(clock_enable),.configured(cfg_done),.init_error(cfg_error),.config_index(config_index),
        .scl(IO_cam_scl),.sda(IO_cam_sda));
    reg [1:0] clock_enable_sync;
    always @(posedge inck or negedge camera_ready)
        if(!camera_ready) clock_enable_sync<=0;else clock_enable_sync<={clock_enable_sync[0],clock_enable};
    PH1P_LOGIC_HR_OSERDES #(.ODDRMODE("DDRX1")) u_inck_output(
        .sclk(inck),.pclk(inck),.rst(!clock_enable_sync[1]),.idata(10'b0000000001),.odata(O_cam_inck));
    // Newer FEP circuit: low input leaves the module power enabled.
    assign O_fep_power=1'b0;
    wire byte_clk,hs_valid,mipi_overflow,burst_error;
    wire [31:0] missing_sot_bursts;
    wire [383:0] fault_diagnostic;
    wire [31:0] hs_data,byte_gray;wire [1023:0] lane_statistics;wire [767:0] burst_head;
    wire mipi_retry_reset_n;wire [2:0] mipi_retries;
    wire [3:0] cal_done_mask={lane_statistics[451],lane_statistics[323],lane_statistics[195],lane_statistics[67]};
    wire [3:0] cal_eye_mask={lane_statistics[452],lane_statistics[324],lane_statistics[196],lane_statistics[68]};
    mipi_startup_retry u_mipi_retry(I_sysclk,release_sys[3],cfg_done,cal_done_mask,cal_eye_mask,mipi_retry_reset_n,mipi_retries);
    wire camera_reset_n=camera_ready && !cfg_error && mipi_retry_reset_n;
    mipi_hr_rx_diag u_mipi(.rst_n(camera_reset_n),.I_clk_hs_p(I_clk_hs_p),.I_data_hs_p(I_data_hs_p),
        .I_data_lp_p(I_data_lp_p),.I_data_lp_n(I_data_lp_n),.byte_clk(byte_clk),.valid(hs_valid),.data(hs_data),
        .overflow(mipi_overflow),.statistics(lane_statistics),.byte_gray(byte_gray),.configured(cfg_done),
        .burst_head(burst_head),.burst_error(burst_error),.missing_sot_bursts(missing_sot_bursts),.fault_diagnostic(fault_diagnostic));
    wire [31:0] csi_errors,accepted,dropped,good_headers,bad_headers,bad_crc,truncated,raw_lines,fs_count,fe_count,last_header;
    wire [15:0] last_wc;
    wire [31:0] geometry_rejected;
    wire [12:0] last_frame_lines;
    wire [575:0] pipeline_diag;
    wire [31:0] displayed_frames;
    wire [1:0] color_pattern;wire wb_request;
    wire [63:0] calibration_diagnostic;wire [1:0] view_mode;
    wire [127:0] color_diagnostic;wire [31:0] busy_skips;
    preview_color_control u_color_control(byte_clk,camera_reset_n,I_color_keys_n,color_pattern,wb_request);
    wire read_enable,buffer_boundary,image_available,display_line_end,play_ready;
    wire hold_display,buffer_held,play_start,play_write,play_commit;
    wire [20:0] play_addr;wire [31:0] play_data,hold_skips,fifo_errors;
    wire [2:0] exposure;
    wire [2:0] exposure_gray=exposure^(exposure>>1);
    (* async_reg="true" *) reg [2:0] exp_meta,exp_sync;
    wire [2:0] exposure_request={exp_sync[2],exp_sync[2]^exp_sync[1],exp_sync[2]^exp_sync[1]^exp_sync[0]};
    wire exposure_busy,exposure_error;
    (* async_reg="true" *) reg [1:0] exp_status_meta,exp_status;
    always @(posedge I_sysclk or negedge release_sys[3])
        if(!release_sys[3])begin exp_meta<=5;exp_sync<=5;end
        else begin exp_meta<=exposure_gray;exp_sync<=exp_meta;end
    always @(posedge pixel_clk or negedge release_pixel[3])
        if(!release_pixel[3])begin exp_status_meta<=0;exp_status<=0;end
        else begin exp_status_meta<={exposure_busy,exposure_error};exp_status<=exp_status_meta;end
    imx415_exposure u_exposure(.clk(I_sysclk),.rst_n(release_sys[3]),.configured(cfg_done),.level(exposure_request),
        .busy(exposure_busy),.error(exposure_error),.applied(),.scl(IO_cam_scl),.sda(IO_cam_sda));
    // DDR initialization and training run independently of the camera PLLs.
    wire ddr_clk;
    (* keep="true" *) wire ddr_rst_n,ddr_enable,ddr_pll,ddr_phy,ddr_test_done,ddr_test_failed,ddr_dma_fault;
    wire [31:0] ddr_test_writes,ddr_test_reads,ddr_test_errors;
    wire [191:0] ddr_pipeline_diag;
    wire [127:0] ddr_first_fault;
    wire [26:0] ddr_awaddr,ddr_araddr;
    wire [127:0] ddr_wdata,ddr_rdata;wire [15:0] ddr_wstrb;
    wire ddr_awvalid,ddr_awready,ddr_wvalid,ddr_wlast,ddr_wready,ddr_arvalid,ddr_arready,ddr_rvalid,ddr_rlast,ddr_rready;
    ddr_trial_link u_ddr(
        .ref_clk(I_sysclk),.rst_n(I_reset_n),.ddr_clk(ddr_clk),.ddr_rst_n(ddr_rst_n),.pll_locked(ddr_pll),.phy_ready(ddr_phy),.memory_enable(ddr_enable),
        .test_done(ddr_test_done),.test_failed(ddr_test_failed),.test_writes(ddr_test_writes),.test_reads(ddr_test_reads),.test_errors(ddr_test_errors),
        .first_bad_addr(),.first_expected(),.first_actual(),
        .video_awaddr(ddr_awaddr),.video_awvalid(ddr_awvalid),.video_awready(ddr_awready),
        .video_wdata(ddr_wdata),.video_wstrb(ddr_wstrb),.video_wvalid(ddr_wvalid),.video_wlast(ddr_wlast),.video_wready(ddr_wready),
        .video_araddr(ddr_araddr),.video_arvalid(ddr_arvalid),.video_arready(ddr_arready),
        .video_rdata(ddr_rdata),.video_rvalid(ddr_rvalid),.video_rlast(ddr_rlast),.video_rready(ddr_rready),
        .ddr_ck_p(ddr_ck_p),.ddr_ck_n(ddr_ck_n),.ddr_reset_n(ddr_reset_n),.ddr_cke(ddr_cke),.ddr_odt(ddr_odt),.ddr_cs_n(ddr_cs_n),
        .ddr_ras_n(ddr_ras_n),.ddr_cas_n(ddr_cas_n),.ddr_we_n(ddr_we_n),.ddr_ba(ddr_ba),.ddr_addr(ddr_addr),
        .ddr_dqs_p(ddr_dqs_p),.ddr_dqs_n(ddr_dqs_n),.ddr_dq(ddr_dq),.ddr_dm(ddr_dm));
    reg [31:0] ddr_cycles,sys_cycles;
    always @(posedge ddr_clk or negedge I_reset_n)if(!I_reset_n)ddr_cycles<=0;else ddr_cycles<=ddr_cycles+1'b1;
    always @(posedge I_sysclk or negedge I_reset_n)if(!I_reset_n)sys_cycles<=0;else sys_cycles<=sys_cycles+1'b1;
    // One bidirectional pAXI connection: request outputs and DDR return outputs share the same nets.
    wire [20:0] read_addr;
    wire [31:0] read_data;
    session_image_pipeline_rgb565 #(.ENABLE_NETWORK(1),.DOWNSAMPLE(1),.ADDR_BITS(21),.CROP_WIDTH(1920),.CROP_HEIGHT(1080),.X_START(972),.Y_START(556),.BAYER_PATTERN(BAYER_PATTERN),.GRAYSCALE(GRAYSCALE),.ENABLE_FRAME_GUARD(ENABLE_FRAME_GUARD),.ENABLE_COLOR_CONTROL(1)) u_pipeline(
        .net_cmd(net_cmd),.net_cmd_valid(net_cmd_valid),.net_cmd_ready(net_cmd_ready),
        .net_response(net_response),.net_response_valid(net_response_valid),.net_response_ready(net_response_ready),
        .cam_clk(byte_clk),.cam_rst_n(camera_reset_n),.hs_valid(hs_valid),.hs_data(hs_data),
        .csi_errors(csi_errors),.accepted_frames(accepted),.dropped_frames(dropped),.burst_error(burst_error),
        .pixel_clk(pixel_clk),.pixel_rst_n(release_pixel[3]),.display_frame_start(buffer_boundary),
        .read_enable(read_enable),.read_addr(read_addr),.read_data(read_data),.image_available(image_available),.display_line_end(display_line_end),.play_ready(play_ready),
        .good_headers(good_headers),.bad_headers(bad_headers),.bad_crc(bad_crc),.truncated(truncated),
        .raw_lines(raw_lines),.fs_count(fs_count),.fe_count(fe_count),.last_header(last_header),.last_wc(last_wc),
        .geometry_rejected(geometry_rejected),.last_frame_lines(last_frame_lines),
        .diagnostic(pipeline_diag),.displayed_frames(displayed_frames),.color_pattern(color_pattern),.wb_request(wb_request),.color_diagnostic(color_diagnostic),.calibration_diagnostic(calibration_diagnostic),.busy_skips(busy_skips),.hold_display(hold_display),.play_start(play_start),.play_write(play_write),.play_commit(play_commit),
        .play_addr(play_addr),.play_data(play_data),.held(buffer_held),.hold_skips(hold_skips),.fifo_errors(fifo_errors),
        .ddr_clk(ddr_clk),.ddr_rst_n(ddr_rst_n),.ddr_enable(ddr_enable),.ddr_diagnostic(ddr_pipeline_diag),.ddr_fault(ddr_dma_fault),
        .ddr_fault_diagnostic(ddr_first_fault),
        .ddr_awaddr(ddr_awaddr),.ddr_awvalid(ddr_awvalid),.ddr_awready(ddr_awready),
        .ddr_wdata(ddr_wdata),.ddr_wstrb(ddr_wstrb),.ddr_wvalid(ddr_wvalid),.ddr_wlast(ddr_wlast),.ddr_wready(ddr_wready),
        .ddr_araddr(ddr_araddr),.ddr_arvalid(ddr_arvalid),.ddr_arready(ddr_arready),
        .ddr_rdata(ddr_rdata),.ddr_rvalid(ddr_rvalid),.ddr_rlast(ddr_rlast),.ddr_rready(ddr_rready));
    wire [23:0] rgb;
    wire de,hs,vs;
    wire [11:0] preview_x,preview_y;
    preview_display_rgb565 #(.WIDTH(1920),.HEIGHT(1080),.ADDR_BITS(21)) u_display(.clk(pixel_clk),.rst_n(release_pixel[3]),.image_available(image_available),.test_pattern(1'b0),
        .framebuffer_data(read_data),.read_enable(read_enable),.read_addr(read_addr),
        .buffer_boundary(buffer_boundary),.display_line_end(display_line_end),.rgb(rgb),.de(de),.hs(hs),.vs(vs),
        .pixel_x(preview_x),.pixel_y(preview_y));
    wire photo_beep;wire [3:0] file_status;wire [7:0] file_error;
    wire app_hold_display;
    assign hold_display=app_hold_display;
    wire focus_busy,focus_beep,photo_buzzer_n,focus_buzzer_n;
    // Register the ownership level before CDC: a binary FSM decode can glitch.
    reg focus_lock_pixel;
    always @(posedge pixel_clk or negedge release_pixel[3])
      if(!release_pixel[3])focus_lock_pixel<=0;else focus_lock_pixel<=focus_busy;
    focus_buzzer #(.CLOCK_HZ(114750000)) u_focus_buzzer(pixel_clk,release_pixel[3],focus_beep,focus_buzzer_n);
    assign O_buzzer_n=photo_buzzer_n && focus_buzzer_n;
    photo_buzzer #(.CLOCK_HZ(114750000)) u_buzzer(pixel_clk,release_pixel[3],
        photo_beep,file_status,file_error,photo_buzzer_n);
    // SCAM RGB565 stream, default 2 fps; no FPGA detection verdict.
    camera_ethernet #(.WIDTH(1920),.HEIGHT(1080)) u_network(.focus_lock(focus_lock_pixel),.servo_pwm(O_servo_pwm),
        .lift_apply(lift_apply_net),.lift_target(lift_target_net),.lift_control_ready(lift_control_ready),
        .lift_applied(lift_applied_net),.lift_enabled(lift_enabled_net),.boot_select_n(I_key_n[5:4]),.device_id(network_identity),.profile_done(network_profile_done),.I_sys_clk(I_sysclk),.O_phy_rst(O_phy_rst),
        .pll_locked(net_lock && I_reset_n),.clk_125(net_clk),.clk_125_90(net_clk90),.clk_25(net_clk25),
        .I_a_rgmii_rxd(I_a_rgmii_rxd),.I_a_rgmii_rx_ctl(I_a_rgmii_rx_ctl),.I_a_rgmii_rxc(I_a_rgmii_rxc),
        .O_a_rgmii_txd(O_a_rgmii_txd),.O_a_rgmii_tx_ctl(O_a_rgmii_tx_ctl),.O_a_rgmii_txc(O_a_rgmii_txc),
        .ddr_clk(ddr_clk),.stream_rst_n(camera_reset_n && release_pixel[3] && ddr_rst_n && ddr_enable),
        .net_cmd(net_cmd),.net_cmd_valid(net_cmd_valid),.net_cmd_ready(net_cmd_ready),
        .net_response(net_response),.net_response_valid(net_response_valid),.net_response_ready(net_response_ready));

    servo_ui_bridge lift_bridge(.rst_n(release_pixel[3] && lift_control_ready),
        .ui_clk(pixel_clk),.ui_apply(lift_apply_pixel),.ui_target(lift_setting),.ui_ready(lift_ready_pixel),
        .net_clk(net_clk),.net_apply(lift_apply_net),.net_target(lift_target_net),
        .net_applied(lift_applied_net),.net_enabled(lift_enabled_net),
        .ui_applied(lift_applied_pixel),.ui_enabled(lift_enabled_pixel));
    wire [23:0] app_rgb;wire app_de,app_hs,app_vs;wire [11:0] app_x,app_y;
    // 114.75MHz host; retain key timing. SD init247.3kHz, data22.95MHz (3/2 host-cycle low/high).
    smart_app #(.CLOCK_HZ(114750000),.WIDTH(1920),.HEIGHT(1080),
        .DEBOUNCE_CYCLES(1147500),.REPEAT_DELAY(45900000),.REPEAT_RATE(11475000),
        .SD_POWER_WAIT(1147500),.SD_TIMEOUT(229500000),.SD_INIT_DIV(232),.SD_DATA_DIV(3),
        .PHOTO_BUFFER_BYTES(98304),.BUFFER_ADDR_BITS(21),.DENOISE_DEFAULT(2)) u_app(
        .clk(pixel_clk),.rst_n(release_pixel[3]),.key_n(I_key_n),
        .camera_frame_id(displayed_frames),.focus_busy(focus_busy),.focus_beep(focus_beep),
        .lift_ready(lift_ready_pixel),.lift_applied(lift_applied_pixel),.lift_enabled(lift_enabled_pixel),
        .lift_apply(lift_apply_pixel),.lift_setting(lift_setting),
        .image_available(image_available),.buffer_held(buffer_held),.play_store_ready(play_ready),
        .sd_miso(I_sd_miso),.exposure_busy(exp_status[1]),.exposure_error(exp_status[0]),
        .sd_cs_n(O_sd_cs_n),.sd_sck(O_sd_sck),.sd_mosi(O_sd_mosi),.light_on(O_light),
        .hold_display(app_hold_display),.play_start(play_start),.play_write(play_write),
        .play_commit(play_commit),.play_addr(play_addr),.play_data(play_data),
        .exposure_level(exposure),.file_status(file_status),.file_error(file_error),.photo_beep(photo_beep),
        .in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),.in_x(preview_x),.in_y(preview_y),
        .out_rgb(app_rgb),.out_de(app_de),.out_hs(app_hs),.out_vs(app_vs),.out_x(app_x),.out_y(app_y));

    // Coherent, passive startup evidence remains readable when the camera is absent.
    (* async_reg="true" *) reg [15:0] cfg_status_meta,cfg_status_sync;
    always @(posedge pixel_clk or negedge release_pixel[3])
        if(!release_pixel[3])begin cfg_status_meta<=0;cfg_status_sync<=0;end
        else begin cfg_status_meta<={1'b0,mipi_retries,cfg_done,cfg_error,clock_enable,config_index};cfg_status_sync<=cfg_status_meta;end
    wire [415:0] camera_debug_source={raw_lines,missing_sot_bursts,truncated,bad_crc,bad_headers,
        24'd0,cal_eye_mask,cal_done_mask,
        lane_statistics[423:416],lane_statistics[295:288],lane_statistics[167:160],lane_statistics[39:32],
        pipeline_diag[287:256],8'd0,pipeline_diag[31:24],3'd0,last_frame_lines,
        geometry_rejected,csi_errors,fe_count,fs_count};
    wire [415:0] camera_debug;wire [31:0] camera_debug_count,camera_byte_hz;
    diag_mailbox #(.WIDTH(416),.PERIOD(11475000),.FREQ_PERIOD(114750000)) camera_diagnostics(
        byte_clk,camera_reset_n,camera_debug_source,byte_gray,pixel_clk,release_pixel[3],camera_debug,camera_debug_count,camera_byte_hz);
    wire [351:0] ddr_debug;wire [31:0] ddr_debug_count,unused_ddr_hz;
    wire [351:0] ddr_debug_source={26'd0,ddr_dma_fault,ddr_test_failed,ddr_test_done,ddr_enable,ddr_phy,ddr_pll,ddr_first_fault,ddr_pipeline_diag};
    diag_mailbox #(.WIDTH(352),.PERIOD(11475000),.FREQ_PERIOD(114750000)) ddr_diagnostics(
        ddr_clk,ddr_rst_n,ddr_debug_source,32'd0,pixel_clk,release_pixel[3],ddr_debug,ddr_debug_count,unused_ddr_hz);
    wire [23:0] diagnostic_rgb;wire diagnostic_de,diagnostic_hs,diagnostic_vs;
    wire id_sclk,id_mosi,id_latch;
    board_id_hc595 id_display(net_clk25,net_lock && I_reset_n,network_identity,network_profile_done,
        id_sclk,id_mosi,id_latch);
    camera_startup_overlay startup_overlay(pixel_clk,release_pixel[3],app_rgb,app_de,app_hs,app_vs,app_x,app_y,
        image_available,cfg_status_sync,camera_debug,camera_byte_hz,ddr_debug,
        diagnostic_rgb,diagnostic_de,diagnostic_hs,diagnostic_vs);

    // Isolate the diagnostic glyph/overlay path from TMDS disparity encoding.
    // Delay RGB and all timing signals together, preserving raster alignment.
    reg [23:0] hdmi_rgb_q;
    reg hdmi_de_q,hdmi_hs_q,hdmi_vs_q;
    always @(posedge pixel_clk or negedge release_pixel[3])
        if(!release_pixel[3])begin hdmi_rgb_q<=0;hdmi_de_q<=0;hdmi_hs_q<=0;hdmi_vs_q<=0;end
        else begin hdmi_rgb_q<=diagnostic_rgb;hdmi_de_q<=diagnostic_de;hdmi_hs_q<=diagnostic_hs;hdmi_vs_q<=diagnostic_vs;end
    hdmi_video_phy u_hdmi(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.rst_n(release_pixel[3]),
        .rgb(hdmi_rgb_q),.de(hdmi_de_q),.hs(hdmi_hs_q),.vs(hdmi_vs_q),.O_hdmi_clk_p(O_hdmi_clk_p),.O_hdmi_tx_p(O_hdmi_tx_p));
    // LED1 system heartbeat; LED2 DDR clock; LED3 startup PASS; LED4 error.
    (* async_reg="true" *) reg [3:0] ddr_led_meta,ddr_led_sync;
    always @(posedge I_sysclk or negedge I_reset_n)
        if(!I_reset_n)begin ddr_led_meta<=0;ddr_led_sync<=0;end
        else begin ddr_led_meta<={ddr_test_failed|ddr_dma_fault,ddr_enable,ddr_cycles[26],sys_cycles[24]};ddr_led_sync<=ddr_led_meta;end
    // E21/D21/E22 also drive onboard HC595 DATA/LATCH/SCLK.
    // LED1..3 now follow serial activity; LED4 retains active-low DDR fault.
    assign O_led={~ddr_led_sync[3],id_sclk,id_latch,id_mosi};
endmodule
`default_nettype wire
