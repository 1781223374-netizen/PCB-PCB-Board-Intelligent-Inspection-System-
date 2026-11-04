`timescale 1ns/1ps
`default_nettype none
// Board KEY3 selects CFA; KEY4 requests one white-card calibration.
// Byte clock is 74.25 MHz; the default debounce interval is 20 ms.
module preview_color_control #(parameter DEBOUNCE_CYCLES=1485000,COUNT_BITS=21)(
 input wire clk,rst_n,input wire [1:0] key_n,
 output reg [1:0] pattern_setting,output reg wb_request_toggle
);
 (* async_reg="true" *) reg [1:0] key_meta,key_sync;
 reg [1:0] stable;
 reg [COUNT_BITS-1:0] count0,count1;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin key_meta<=3;key_sync<=3;stable<=3;count0<=0;count1<=0;pattern_setting<=1;wb_request_toggle<=0;end
  else begin
   key_meta<=key_n;key_sync<=key_meta;
   if(key_sync[0]==stable[0])count0<=0;
   else if(count0==DEBOUNCE_CYCLES-1)begin count0<=0;stable[0]<=key_sync[0];if(!key_sync[0])pattern_setting<=pattern_setting+1'b1;end
   else count0<=count0+1'b1;
   if(key_sync[1]==stable[1])count1<=0;
   else if(count1==DEBOUNCE_CYCLES-1)begin count1<=0;stable[1]<=key_sync[1];if(!key_sync[1])wb_request_toggle<=!wb_request_toggle;end
   else count1<=count1+1'b1;
  end
 end
endmodule
`default_nettype wire
