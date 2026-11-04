`timescale 1ns/1ps
`default_nettype none
module ddr_trial_link #(parameter TEST_INDEX_BITS=12)(
 input wire ref_clk,rst_n,output wire ddr_clk,ddr_rst_n,pll_locked,phy_ready,memory_enable,
 output wire test_done,test_failed,output wire [31:0] test_writes,test_reads,test_errors,
 output wire [26:0] first_bad_addr,output wire [127:0] first_expected,first_actual,
 input wire [26:0] video_awaddr,input wire video_awvalid,output wire video_awready,
 input wire [127:0] video_wdata,input wire [15:0] video_wstrb,input wire video_wvalid,video_wlast,output wire video_wready,
 input wire [26:0] video_araddr,input wire video_arvalid,output wire video_arready,
 output wire [127:0] video_rdata,output wire video_rvalid,video_rlast,input wire video_rready,
 output wire ddr_ck_p,ddr_ck_n,ddr_reset_n,ddr_cke,ddr_odt,ddr_cs_n,ddr_ras_n,ddr_cas_n,ddr_we_n,
 output wire [2:0] ddr_ba,output wire [13:0] ddr_addr,
 inout wire [1:0] ddr_dqs_p,ddr_dqs_n,ddr_dm,inout wire [15:0] ddr_dq
);
 wire cfg_clk;
 wire [26:0] awaddr,araddr,test_awaddr,test_araddr;
 wire awvalid,awready,wvalid,wready,wlast,arvalid,arready,rvalid,rlast,rready;
 wire test_awvalid,test_wvalid,test_wlast,test_arvalid,test_rready;
 wire [127:0] wdata,rdata,test_wdata;
 wire [15:0] wstrb,test_wstrb;
 ddr_paxi_controller u_controller(
  .ref_clk(ref_clk),.sys_rst_n(rst_n),.clk(ddr_clk),.cfg_clk(cfg_clk),.pll_locked(pll_locked),.phy_ready(phy_ready),
  .awaddr(awaddr),.awvalid(awvalid),.awready(awready),.wdata(wdata),.wstrb(wstrb),.wvalid(wvalid),.wlast(wlast),.wready(wready),
  .araddr(araddr),.arvalid(arvalid),.arready(arready),.rdata(rdata),.rvalid(rvalid),.rlast(rlast),.rready(rready),
  .ddr_ck_p(ddr_ck_p),.ddr_ck_n(ddr_ck_n),.ddr_reset_n(ddr_reset_n),.ddr_cke(ddr_cke),.ddr_odt(ddr_odt),.ddr_cs_n(ddr_cs_n),
  .ddr_ras_n(ddr_ras_n),.ddr_cas_n(ddr_cas_n),.ddr_we_n(ddr_we_n),.ddr_ba(ddr_ba),.ddr_addr(ddr_addr),
  .ddr_dqs_p(ddr_dqs_p),.ddr_dqs_n(ddr_dqs_n),.ddr_dq(ddr_dq),.ddr_dm(ddr_dm)
 );
 (* async_reg="true" *) reg [2:0] reset_release;
 wire ready_reset_n=rst_n && pll_locked && phy_ready;
 always @(posedge ddr_clk or negedge ready_reset_n)
  if(!ready_reset_n)reset_release<=0;else reset_release<={reset_release[1:0],1'b1};
 assign ddr_rst_n=reset_release[2];
 ddr_startup_test #(.INDEX_BITS(TEST_INDEX_BITS)) u_test(
  .clk(ddr_clk),.rst_n(ddr_rst_n),.phy_ready(phy_ready),.done(test_done),.failed(test_failed),
  .writes(test_writes),.reads(test_reads),.errors(test_errors),.first_bad_addr(first_bad_addr),
  .first_expected(first_expected),.first_actual(first_actual),
  .awaddr(test_awaddr),.awvalid(test_awvalid),.awready(awready && !memory_enable),
  .wdata(test_wdata),.wstrb(test_wstrb),.wvalid(test_wvalid),.wlast(test_wlast),.wready(wready && !memory_enable),
  .araddr(test_araddr),.arvalid(test_arvalid),.arready(arready && !memory_enable),
  .rdata(rdata),.rvalid(rvalid && !memory_enable),.rlast(rlast),.rready(test_rready)
 );
 assign memory_enable=ddr_rst_n && test_done && !test_failed;
 assign awaddr=memory_enable?video_awaddr:test_awaddr;
 assign awvalid=memory_enable?video_awvalid:test_awvalid;
 assign wdata=memory_enable?video_wdata:test_wdata;
 assign wstrb=memory_enable?video_wstrb:test_wstrb;
 assign wvalid=memory_enable?video_wvalid:test_wvalid;
 assign wlast=memory_enable?video_wlast:test_wlast;
 assign araddr=memory_enable?video_araddr:test_araddr;
 assign arvalid=memory_enable?video_arvalid:test_arvalid;
 assign rready=memory_enable?video_rready:test_rready;
 assign video_awready=memory_enable && awready;
 assign video_wready=memory_enable && wready;
 assign video_arready=memory_enable && arready;
 assign video_rdata=rdata;assign video_rvalid=memory_enable && rvalid;assign video_rlast=rlast;
endmodule
`default_nettype wire
