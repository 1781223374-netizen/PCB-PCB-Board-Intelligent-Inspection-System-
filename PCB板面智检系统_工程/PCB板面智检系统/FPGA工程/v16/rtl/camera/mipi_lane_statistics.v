`timescale 1ns/1ps
`default_nettype none
// Passive statistics. The three alternative aligners never feed the receiver.
module mipi_lane_statistics(
 input wire clk,rst_n,
 input wire [31:0] samples,lane_data,
 input wire [3:0] stop_state,normal_locked,normal_valid,overflow_event,
 input wire combined_valid,
 output wire [1023:0] statistics,
 output reg [31:0] byte_gray,
 input wire capture_enable,output reg [767:0] burst_head
);
 wire [3:0] reversed_locked,inverted_locked,both_locked;
 genvar g;
 generate for(g=0;g<4;g=g+1) begin: alternative
  wire [7:0] v=samples[g*8+:8];
  wire [7:0] r={v[0],v[1],v[2],v[3],v[4],v[5],v[6],v[7]};
  lane_byte_align #(.SEARCH_CYCLES(0),.QUALIFY_ZERO(0)) r_align(clk,rst_n,stop_state[g],r, , ,reversed_locked[g]);
  lane_byte_align #(.SEARCH_CYCLES(0),.QUALIFY_ZERO(0)) i_align(clk,rst_n,stop_state[g],~v, , ,inverted_locked[g]);
  lane_byte_align #(.SEARCH_CYCLES(0),.QUALIFY_ZERO(0)) x_align(clk,rst_n,stop_state[g],~r, , ,both_locked[g]);
 end endgenerate
 reg [31:0] sync_count[0:15],byte_count[0:3],overflow_count[0:3],stop_count[0:3];
 reg [15:0] prev_locked;
 reg [3:0] prev_stop,first_pending;
 reg [31:0] first_bytes,cycles;
 reg capturing;
 reg [4:0] capture_index;
 reg [191:0] capture_shift[0:3];
 integer n;
 // Commit all lanes together after 24 samples. The display never sees a
 // partially replaced burst. Each lane's earliest sample is in its low byte.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   capturing<=0;capture_index<=0;burst_head<=0;
   for(n=0;n<4;n=n+1)capture_shift[n]<=0;
  end else if(!capture_enable)begin capturing<=0;capture_index<=0;end
  else if(!capturing)begin
   if(prev_stop==4'hf && stop_state!=4'hf)begin
    capturing<=1;capture_index<=1;
    for(n=0;n<4;n=n+1)capture_shift[n]<={samples[n*8+:8],184'd0};
   end
  end else begin
   for(n=0;n<4;n=n+1)begin
    capture_shift[n]<={samples[n*8+:8],capture_shift[n][191:8]};
    if(capture_index==23)burst_head[n*192+:192]<={samples[n*8+:8],capture_shift[n][191:8]};
   end
   if(capture_index==23)capturing<=0;
   else capture_index<=capture_index+1'b1;
  end
 end
 wire [31:0] next_cycles=cycles+1'b1;
 wire [15:0] locks={both_locked,inverted_locked,reversed_locked,normal_locked};
 integer k,c;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   prev_locked<=0;prev_stop<=15;first_pending<=0;first_bytes<=0;cycles<=0;byte_gray<=0;
   for(k=0;k<16;k=k+1)sync_count[k]<=0;
   for(k=0;k<4;k=k+1)begin byte_count[k]<=0;overflow_count[k]<=0;stop_count[k]<=0;end
  end else begin
   prev_locked<=locks;prev_stop<=stop_state;cycles<=next_cycles;byte_gray<=next_cycles^(next_cycles>>1);
   for(k=0;k<4;k=k+1)begin
    for(c=0;c<4;c=c+1)if(locks[c*4+k]&&!prev_locked[c*4+k])sync_count[k*4+c]<=sync_count[k*4+c]+1'b1;
    if(normal_locked[k]&&!prev_locked[k])first_pending[k]<=1;
    if(normal_valid[k])begin
     byte_count[k]<=byte_count[k]+1'b1;
     if(first_pending[k])begin first_bytes[k*8+:8]<=lane_data[k*8+:8];first_pending[k]<=0;end
    end
    if(overflow_event[k])overflow_count[k]<=overflow_count[k]+1'b1;
    if(stop_state[k]&&!prev_stop[k])stop_count[k]<=stop_count[k]+1'b1;
   end
  end
 end
 generate for(g=0;g<16;g=g+1)begin: count_pack
  assign statistics[g*32+:32]=sync_count[g];
 end
 for(g=0;g<4;g=g+1)begin: lane_pack
  assign statistics[(16+g)*32+:32]=byte_count[g];
  assign statistics[(20+g)*32+:32]=overflow_count[g];
  assign statistics[(24+g)*32+:32]=stop_count[g];
 end endgenerate
 assign statistics[28*32+:32]=samples;
 assign statistics[29*32+:32]=first_bytes;
 assign statistics[30*32+:32]={19'd0,combined_valid,normal_valid,stop_state,normal_locked};
 assign statistics[31*32+:32]=cycles;
endmodule
`default_nettype wire
