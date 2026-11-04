`timescale 1ns/1ps
`default_nettype none
// Retry only a completed calibration with a failed lane. Never retune a live
// receiver, and never substitute an unqualified tap or relax CRC/geometry.
// The 50-MHz control clock keeps running while the receiver divider is reset.
module mipi_startup_retry #(
 parameter GUARD_CYCLES=500000,RESET_CYCLES=5000,MAX_RETRIES=4
)(
 input wire clk,rst_n,configured,input wire [3:0] cal_done,cal_eye,
 output reg receiver_reset_n,output reg [2:0] retries
);
 (* async_reg="true" *) reg [7:0] status_meta,status_sync;
 reg [31:0] timer;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin status_meta<=0;status_sync<=0;end
  else begin status_meta<={cal_eye,cal_done};status_sync<=status_meta;end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin receiver_reset_n<=1;retries<=0;timer<=0;end
  else if(!configured)begin receiver_reset_n<=1;retries<=0;timer<=0;end
  else if(!receiver_reset_n)begin
   if(timer==RESET_CYCLES-1)begin receiver_reset_n<=1;timer<=0;end
   else timer<=timer+1'b1;
  end else if(status_sync[3:0]==4'hf && status_sync[7:4]!=4'hf && retries<MAX_RETRIES)begin
   if(timer==GUARD_CYCLES-1)begin receiver_reset_n<=0;retries<=retries+1'b1;timer<=0;end
   else timer<=timer+1'b1;
  end else timer<=0;
 end
endmodule
`default_nettype wire
