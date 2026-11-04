`timescale 1ns/1ps
`default_nettype none
// The unmodified manufacturer IP supplies its own ROM/DRAM initialization and
// hardware training. Debug APB is idle; the original demo also supports skipping
// its UART MCU. Traffic must wait for phy_ready (training complete).
module ddr_paxi_controller(
 input wire ref_clk,sys_rst_n,output wire clk,cfg_clk,pll_locked,phy_ready,
 input wire [26:0] awaddr,input wire awvalid,output wire awready,
 input wire [127:0] wdata,input wire [15:0] wstrb,input wire wvalid,wlast,output wire wready,
 input wire [26:0] araddr,input wire arvalid,output wire arready,
 output wire [127:0] rdata,output wire rvalid,rlast,input wire rready,
 output wire ddr_ck_p,ddr_ck_n,ddr_reset_n,ddr_cke,ddr_odt,ddr_cs_n,ddr_ras_n,ddr_cas_n,ddr_we_n,
 output wire [2:0] ddr_ba,output wire [13:0] ddr_addr,
 inout wire [1:0] ddr_dqs_p,ddr_dqs_n,ddr_dm,inout wire [15:0] ddr_dq
);
 ddrmc_x32 u_ddrmc_x32(
  .ref_clk(ref_clk),.sys_rst_n(sys_rst_n),.dhi_clk(clk),.cfg_clk(cfg_clk),
  .ddrphy_rst_n(pll_locked),.ddrphy_rdy(phy_ready),
  .apb_pclk(),.apb_prst_n(pll_locked),.apb_psel(1'b0),.apb_penable(1'b0),
  .apb_pwrite(1'b0),.apb_paddr(16'd0),.apb_pwdata(32'd0),.apb_prdata(),.apb_pready(),
  .paxi_awaddr(awaddr),.paxi_awvalid(awvalid),.paxi_awready(awready),
  .paxi_wdata(wdata),.paxi_wstrb(wstrb),.paxi_wvalid(wvalid),.paxi_wlast(wlast),.paxi_wready(wready),
  .paxi_araddr(araddr),.paxi_arvalid(arvalid),.paxi_arready(arready),
  .paxi_rdata(rdata),.paxi_rvalid(rvalid),.paxi_rlast(rlast),.paxi_rready(rready),
  .usr_ref_req(1'b0),.usr_ref_type(2'b00),.usr_ref_ack(),.ecc_err_sig(),.ecc_err_mul(),
  .ddr_ck_p(ddr_ck_p),.ddr_ck_n(ddr_ck_n),.ddr_reset_n(ddr_reset_n),
  .ddr_cke(ddr_cke),.ddr_odt(ddr_odt),.ddr_cs_n(ddr_cs_n),
  .ddr_ras_n(ddr_ras_n),.ddr_cas_n(ddr_cas_n),.ddr_we_n(ddr_we_n),
  .ddr_ba(ddr_ba),.ddr_addr(ddr_addr),.ddr_dqs_p(ddr_dqs_p),.ddr_dqs_n(ddr_dqs_n),.ddr_dq(ddr_dq),.ddr_dm(ddr_dm)
 );
endmodule
`default_nettype wire
