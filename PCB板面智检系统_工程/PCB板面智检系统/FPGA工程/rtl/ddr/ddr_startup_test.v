`timescale 1ns/1ps
`default_nettype none
// One startup test owns pAXI before video. 4096 128-bit transfers cover the
// starts of eight 32 MiB regions. This is a smoke test, not full DDR qualification.
// The vendor's pseudo-AXI addresses are x16 locations, aligned to eight.
// Its wstrb is an active-high MASK (all zero writes every byte).
module ddr_startup_test #(parameter INDEX_BITS=12,TIMEOUT=2000000,SETTLE=4096)(
 input wire clk,rst_n,phy_ready,output wire done,output reg failed,
 output reg [31:0] writes,reads,errors,output reg [26:0] first_bad_addr,
 output reg [127:0] first_expected,first_actual,
 output wire [26:0] awaddr,output reg awvalid,input wire awready,
 output wire [127:0] wdata,output wire [15:0] wstrb,
 output reg wvalid,output wire wlast,input wire wready,
 output wire [26:0] araddr,output reg arvalid,input wire arready,
 input wire [127:0] rdata,input wire rvalid,rlast,output wire rready
);
 localparam IDLE=0,WRITE=1,PAUSE=2,READ_ADDR=3,READ_DATA=4,FINISH=5;
 reg [2:0] state;
 reg [INDEX_BITS-1:0] index;
 reg [31:0] wait_count;
 // Fixed region mapping still exercises high address bits in smaller simulations.
 wire [11:0] full_index={{(12-INDEX_BITS){1'b0}},index};
 wire [26:0] address={full_index[11:9],12'd0,full_index[8:0],3'd0};
 function [127:0] pattern;
  input [26:0] a;reg [31:0] t;
  begin t={5'd0,a}^32'h13c57bdf;pattern={~t,t^32'ha5963cc3,t+32'h27182818,t};end
 endfunction
 assign awaddr=address;assign araddr=address;
 assign wdata=pattern(address);assign wstrb=16'h0000;assign wlast=1'b1;
 assign rready=state==READ_DATA || state==FINISH;
 assign done=state==FINISH;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;index<=0;wait_count<=0;awvalid<=0;wvalid<=0;arvalid<=0;
   failed<=0;writes<=0;reads<=0;errors<=0;first_bad_addr<=0;first_expected<=0;first_actual<=0;
  end else begin
   case(state)
    IDLE:if(phy_ready)begin state<=WRITE;awvalid<=1;wvalid<=1;wait_count<=0;end
    WRITE:begin
     if(awvalid && awready)awvalid<=0;
     if(wvalid && wready)wvalid<=0;
     if((!awvalid || awready) && (!wvalid || wready))begin
      writes<=writes+1'b1;wait_count<=0;
      if(&index)begin state<=PAUSE;index<=0;end
      else begin index<=index+1'b1;awvalid<=1;wvalid<=1;end
     end else wait_count<=wait_count+1'b1;
    end
    PAUSE:begin
     if(wait_count==SETTLE-1)begin state<=READ_ADDR;arvalid<=1;wait_count<=0;end
     else wait_count<=wait_count+1'b1;
    end
    READ_ADDR:begin
     if(arvalid && arready)begin arvalid<=0;state<=READ_DATA;wait_count<=0;end
     else wait_count<=wait_count+1'b1;
    end
    READ_DATA:begin
     if(rvalid)begin
      reads<=reads+1'b1;wait_count<=0;
      if(rdata!=pattern(address) || !rlast)begin
       failed<=1;errors<=errors+1'b1;
       if(errors==0)begin first_bad_addr<=address;first_expected<=pattern(address);first_actual<=rdata;end
      end
      if(&index)state<=FINISH;
      else begin index<=index+1'b1;arvalid<=1;state<=READ_ADDR;end
     end else wait_count<=wait_count+1'b1;
    end
    FINISH:begin
     // A timed-out owner retains each request until its eventual handshake,
     // then retires it exactly once. No new commands follow a failure.
     if(awvalid && awready)awvalid<=0;
     if(wvalid && wready)wvalid<=0;
     if(arvalid && arready)arvalid<=0;
    end
    default:begin end
   endcase
   // On an interface timeout ownership is never handed to video; reset is needed.
   if(state!=IDLE && state!=PAUSE && state!=FINISH && wait_count==TIMEOUT-1 &&
      !((state==WRITE && (!awvalid || awready) && (!wvalid || wready)) ||
        (state==READ_ADDR && arvalid && arready) || (state==READ_DATA && rvalid)))begin
    failed<=1;errors<=errors+1'b1;state<=FINISH;
    if(errors==0)begin first_bad_addr<=address;first_expected<=pattern(address);first_actual<=0;end
    // Keep any asserted valid stable; the top continues routing this failed owner.
   end
  end
 end
endmodule
`default_nettype wire
