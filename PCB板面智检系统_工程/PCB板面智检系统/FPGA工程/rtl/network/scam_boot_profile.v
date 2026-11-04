`timescale 1ns/1ps
`default_nettype none
// Sample only while Ethernet is held reset. Identity cannot change mid-frame.
// No key: device 1; hold LEFT(K4): device 2; RIGHT(K5): device 3.
// Both keys, or an unsettled selection, fail closed until another board reset.
module scam_boot_profile #(
 parameter BOOT_CYCLES=12500000,DEBOUNCE_CYCLES=250000
)(input wire clk,rst_n,input wire [1:0] select_n,
 output reg [1:0] device_id,output reg done,output wire ready);
 localparam BW=BOOT_CYCLES>1?$clog2(BOOT_CYCLES+1):1;
 localparam DW=DEBOUNCE_CYCLES>1?$clog2(DEBOUNCE_CYCLES+1):1;
 (* async_reg="true" *) reg [1:0] key_meta,key_sync;
 reg [1:0] candidate,stable;
 reg [BW-1:0] boot_count;
 reg [DW-1:0] debounce;
 reg qualified;
 assign ready=done && device_id!=0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin key_meta<=3;key_sync<=3;candidate<=3;stable<=3;boot_count<=0;debounce<=0;qualified<=0;device_id<=0;done<=0;end
  else if(!done)begin
   key_meta<=select_n;key_sync<=key_meta;
   if(candidate!=key_sync)begin candidate<=key_sync;debounce<=0;qualified<=0;end
   else if(debounce<DEBOUNCE_CYCLES)begin
    debounce<=debounce+1'b1;
    if(debounce==DEBOUNCE_CYCLES-1)begin stable<=candidate;qualified<=1;end
   end
   if(boot_count==BOOT_CYCLES-1)begin
    done<=1;
    if(qualified && candidate==key_sync && stable==key_sync)begin
     case(stable)2'b11:device_id<=1;2'b10:device_id<=2;2'b01:device_id<=3;default:device_id<=0;endcase
    end else device_id<=0;
   end else boot_count<=boot_count+1'b1;
  end
 end
endmodule
`default_nettype wire
