`timescale 1ns/1ps
`default_nettype none
// Serialize CRC calculation; latest queued snapshot wins if UDP is stalled.
module servo_status_packet(input wire clk,rst_n,input wire request,
 input wire [239:0] header,output reg [255:0] packet,output reg valid,input wire take);
 function [15:0] crc_byte;
  input [15:0] crc;input [7:0] value;integer i;reg [15:0] c;
  begin c=crc^{value,8'd0};for(i=0;i<8;i=i+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc_byte=c;end
 endfunction
 reg queued,busy;reg [239:0] latest,active;reg [4:0] index;reg [15:0] crc;
 wire [15:0] next_crc=crc_byte(crc,active[239-index*8-:8]);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin queued<=0;busy<=0;valid<=0;latest<=0;active<=0;index<=0;crc<=16'hffff;packet<=0;end
  else begin
   if(take)valid<=0;
   if(!busy && !valid && queued)begin active<=latest;queued<=0;busy<=1;index<=0;crc<=16'hffff;end
   if(busy)begin
    crc<=next_crc;
    if(index==29)begin packet<={active,next_crc};valid<=1;busy<=0;end
    else index<=index+1'b1;
   end
   if(request)begin latest<=header;queued<=1;end
  end
 end
endmodule
`default_nettype wire
