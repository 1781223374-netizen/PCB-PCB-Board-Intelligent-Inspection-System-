`timescale 1ns/1ps
`default_nettype none
module clocking #(parameter ENABLE_CAMERA=1)(
    input wire refclk,reset,
    output wire pixel_clk,serial_clk,cam_inck,
    output wire video_lock,cam_lock
);
    wire pixel_raw,cam_raw;
    PH1P_LOGIC_BUFG u_pixel_buffer(.i(pixel_raw),.o(pixel_clk));
    // Native1080 CVT-RB: 27/2*85=1147.5 MHz VCO, /10 pixel, /2 serializer.
    ph1p_phy_pll_wrapper_ui_pll #(
        .FBKCLK("VCO_PHASE0"),.FBKCLK_INT("VCO_PHASE0"),.FIN("27.000000000"),
        .REFCLK_DIV(2),.FBCLK_DIV(85),.CLKC0_ENABLE("ENABLE"),.CLKC0_DIV(10),
        .CLKC0_CPHASE(9),.CLKC0_DUTY50("ENABLE"),.CLKC0_DUTY_INT(5),
        .CLKC1_ENABLE("ENABLE"),.CLKC1_DIV(2),.CLKC1_CPHASE(1),
        .CLKC1_DUTY50("ENABLE"),.CLKC1_DUTY_INT(1),
        .PLL_USR_RST("ENABLE"),.PLL_FEED_TYPE("INTERNAL"),.FEEDBK_MODE("NOCOMP"),.PLL_FASTLOOP("DISABLE"),
        .LPF_RES(3),.LPF_CAP(16),.ICP_CUR(0)
    ) u_video_pll(
        .refclk(cam_inck),.reset(reset || !cam_lock),.refclk_rst(1'b0),.pllpd(1'b0),.wakeup(1'b1),
        .fbclk(1'b0),.clk0_en(1'b1),.clk0_out(pixel_raw),.clk1_en(1'b1),.clk1_out(serial_clk),
        .lock(video_lock),.clkc_rst(2'b00),.clk2_en(1'b0),.clk3_en(1'b0),.clk4_en(1'b0),.clk5_en(1'b0),.clk6_en(1'b0),
        .drp_clk(1'b0),.drp_rstn(1'b1),.drp_sel(1'b0),.drp_rd(1'b0),.drp_wr(1'b0),.drp_addr(8'd0),.drp_wdata(8'd0),
        .psclk(1'b0),.psclksel(3'd0),.psstep(1'b0),.psdown(1'b0),.cps_step(1'b0),.ssc_reset(1'b0)
    );
    generate if(ENABLE_CAMERA) begin: sensor
    PH1P_LOGIC_BUFG u_cam_buffer(.i(cam_raw),.o(cam_inck));
    // No-compensation internal VCO feedback: 50*27=1350 MHz, /50=27 MHz.
    ph1p_phy_pll_wrapper_ui_pll #(
        .FBKCLK("VCO_PHASE0"),.FBKCLK_INT("VCO_PHASE0"),.FIN("50.000000000"),
        .REFCLK_DIV(1),.FBCLK_DIV(27),.CLKC0_ENABLE("ENABLE"),.CLKC0_DIV(50),
        .CLKC0_CPHASE(49),.CLKC0_DUTY50("ENABLE"),.CLKC0_DUTY_INT(25),
        .PLL_USR_RST("ENABLE"),.PLL_FEED_TYPE("INTERNAL"),.FEEDBK_MODE("NOCOMP"),.PLL_FASTLOOP("DISABLE"),
        .LPF_RES(3),.LPF_CAP(0),.ICP_CUR(0)
    ) u_sensor_pll(
        .refclk(refclk),.reset(reset),.refclk_rst(1'b0),.pllpd(1'b0),.wakeup(1'b1),
        .fbclk(1'b0),.clk0_en(1'b1),.clk0_out(cam_raw),.clk1_en(1'b0),
        .lock(cam_lock),.clkc_rst(2'b00),.clk2_en(1'b0),.clk3_en(1'b0),.clk4_en(1'b0),.clk5_en(1'b0),.clk6_en(1'b0),
        .drp_clk(1'b0),.drp_rstn(1'b1),.drp_sel(1'b0),.drp_rd(1'b0),.drp_wr(1'b0),.drp_addr(8'd0),.drp_wdata(8'd0),
        .psclk(1'b0),.psclksel(3'd0),.psstep(1'b0),.psdown(1'b0),.cps_step(1'b0),.ssc_reset(1'b0)
    );
    end else begin: no_sensor
        assign cam_inck=1'b0;
        assign cam_lock=1'b1;
    end endgenerate
endmodule
`default_nettype wire
