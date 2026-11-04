`timescale 1ns/1ps
`default_nettype none
module hdmi_video_phy(
    input wire pixel_clk,serial_clk,rst_n,
    input wire [23:0] rgb,
    input wire de,hs,vs,
    output wire O_hdmi_clk_p,
    output wire [2:0] O_hdmi_tx_p
);
    wire [9:0] symbols[0:2];
    tmds_encode u_blue(.clk(pixel_clk),.rst_n(rst_n),.de(de),.data(rgb[7:0]),.control({vs,hs}),.symbol(symbols[0]));
    tmds_encode u_green(.clk(pixel_clk),.rst_n(rst_n),.de(de),.data(rgb[15:8]),.control(2'b00),.symbol(symbols[1]));
    tmds_encode u_red(.clk(pixel_clk),.rst_n(rst_n),.de(de),.data(rgb[23:16]),.control(2'b00),.symbol(symbols[2]));
    genvar i;
    generate for(i=0;i<3;i=i+1) begin: tx
        PH1P_LOGIC_HR_OSERDES #(.ODDRMODE("DDRX5")) u_serializer(
            .sclk(serial_clk),.pclk(pixel_clk),.rst(!rst_n),
            .idata(symbols[i]),.odata(O_hdmi_tx_p[i])
        );
    end endgenerate
    PH1P_LOGIC_HR_OSERDES #(.ODDRMODE("DDRX5")) u_clock_serializer(
        .sclk(serial_clk),.pclk(pixel_clk),.rst(!rst_n),
        .idata(10'b0000011111),.odata(O_hdmi_clk_p)
    );
endmodule
`default_nettype wire
