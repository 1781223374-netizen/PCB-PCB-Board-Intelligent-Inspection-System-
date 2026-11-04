`timescale 1ns/1ps
`default_nettype none
// Preserve the existing sender's busy handshake. Status may interleave only
// between UDP packets. Both packet types use the board's existing image port.
module scam_servo_arbiter(input wire clk,rst_n,link_ready,
 input wire image_req,image_valid,input wire [7:0] image_data,input wire [15:0] image_len,
 output wire image_busy,input wire [255:0] status_packet,input wire status_valid,output wire status_take,
 input wire udp_busy,output wire udp_req,udp_valid,output wire [7:0] udp_data,output wire [15:0] udp_len);
 localparam IDLE=0,IMAGE=1,STATUS_REQ=2,STATUS_SEND=3,STATUS_END=4;
 reg [2:0] state;reg saw_busy,last_status;reg [5:0] index;reg [255:0] snapshot;
 assign status_take=state==IDLE && !udp_busy && link_ready && status_valid && (!image_req || !last_status);
 assign image_busy=state==IMAGE && udp_busy;
 assign udp_req=state==IMAGE?image_req:state==STATUS_REQ;
 assign udp_valid=state==IMAGE?image_valid:state==STATUS_SEND;
 assign udp_len=state==IMAGE?image_len:16'd32;
 assign udp_data=state==IMAGE?image_data:snapshot[255-index*8-:8];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;saw_busy<=0;last_status<=0;index<=0;snapshot<=0;end
  else case(state)
   IDLE:if(!udp_busy && link_ready)begin
    if(status_take)begin snapshot<=status_packet;state<=STATUS_REQ;last_status<=1;end
    else if(image_req)begin state<=IMAGE;saw_busy<=0;last_status<=0;end
   end
   IMAGE:begin if(udp_busy)saw_busy<=1;if(saw_busy && !udp_busy)state<=IDLE;end
   STATUS_REQ:if(udp_busy)begin index<=0;state<=STATUS_SEND;end
   STATUS_SEND:if(index==31)state<=STATUS_END;else index<=index+1'b1;
   STATUS_END:if(!udp_busy)state<=IDLE;
   default:state<=IDLE;
  endcase
 end
endmodule
`default_nettype wire
