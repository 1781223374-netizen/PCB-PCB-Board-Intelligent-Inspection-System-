`timescale 1ns/1ps
`default_nettype none
// Registered read port with one output holding register. Gray pointers alone
// cross the clock boundary; valid/data stay stable until the consumer accepts.
module ddr_async_fifo #(parameter WIDTH=37, AW=9)(
 input wire wclk,rclk,rst_n,input wire wvalid,
 input wire [WIDTH-1:0] wdata,output wire wready,
 output reg rvalid,output reg [WIDTH-1:0] rdata,input wire rready
);
 (* ram_style="bram" *) reg [WIDTH-1:0] mem[0:(1<<AW)-1];
 reg [AW:0] wp,rp;
 (* keep="true" *) reg [AW:0] wg,rg;
 (* async_reg="true" *) reg [AW:0] rm1,rm2,wm1,wm2;
 reg full;
 (* async_reg="true" *) reg [1:0] wr_release,rd_release;
 always @(posedge wclk or negedge rst_n)
  if(!rst_n)wr_release<=0;else wr_release<={wr_release[0],1'b1};
 always @(posedge rclk or negedge rst_n)
  if(!rst_n)rd_release<=0;else rd_release<={rd_release[0],1'b1};
 assign wready=wr_release[1] && !full;
 wire push=wvalid && wready;
 wire empty=rg==wm2;
 wire pop=rd_release[1] && (!rvalid || rready) && !empty;
 wire [AW:0] wn=wp+push;
 // Compute the next read pointer without the pop/reset enable in the carry
 // chain. Commit only on pop; Gray and binary pointers remain unchanged
 // together when stalled. This keeps reset-release -> pop off the adder path.
 wire [AW:0] rn=rp+1'b1;
 wire [AW:0] wgn=(wn>>1)^wn,rgn=(rn>>1)^rn;
 always @(posedge wclk)if(push)mem[wp[AW-1:0]]<=wdata;
 always @(posedge rclk)if(pop)rdata<=mem[rp[AW-1:0]];
 always @(posedge wclk or negedge wr_release[1])begin
  if(!wr_release[1])begin wp<=0;wg<=0;rm1<=0;rm2<=0;full<=0;end
  else begin
   rm1<=rg;rm2<=rm1;wp<=wn;wg<=wgn;
   full<=wgn=={~rm2[AW:AW-1],rm2[AW-2:0]};
  end
 end
 always @(posedge rclk or negedge rd_release[1])begin
  if(!rd_release[1])begin rp<=0;rg<=0;wm1<=0;wm2<=0;rvalid<=0;end
  else begin
   wm1<=wg;wm2<=wm1;
   if(pop)begin rp<=rn;rg<=rgn;end
   if(pop)rvalid<=1;else if(rready)rvalid<=0;
  end
 end
endmodule
`default_nettype wire
