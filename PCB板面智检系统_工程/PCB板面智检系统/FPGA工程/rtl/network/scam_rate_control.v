`timescale 1ns/1ps
`default_nettype none
// Same 125 MHz user clock as uiudp_stack's R_udp_* interface. A complete,
// exact-length packet is required; partial/extra/padded/malformed commands
// cannot change the stream rate. This controls transport only, never the AI.
module scam_rate_control #(parameter DEFAULT_FPS=2)(
 input wire clk,rst_n,rx_valid,input wire [7:0] rx_data,
 input wire [15:0] rx_len,output reg [7:0] requested_fps);
 (* async_reg="true" *) reg [1:0] release_sync;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)release_sync<=0;else release_sync<={release_sync[0],1'b1};
 reg previous_valid;reg [3:0] count;reg [15:0] packet_len;reg [63:0] packet;
 wire [7:0] fps=packet[23:16];
 wire supported=fps==1 || fps==2 || fps==3 || fps==4;
 always @(posedge clk or negedge release_sync[1])begin
  if(!release_sync[1])begin previous_valid<=0;count<=0;packet_len<=0;packet<=0;requested_fps<=DEFAULT_FPS;end
  else begin
   previous_valid<=rx_valid;
   if(rx_valid)begin
    packet<={packet[55:0],rx_data};
    if(!previous_valid)begin count<=1;packet_len<=rx_len;end
    else if(count!=15)count<=count+1'b1;
   end else begin
    if(previous_valid && count==8 && packet_len==8 && packet[63:32]==32'h53465053 &&
       packet[31:24]==8'd1 && packet[15:8]==(fps^8'hff) && packet[7:0]==8'ha5 && supported)
       requested_fps<=fps;
    count<=0;
   end
  end
 end
endmodule
`default_nettype wire
