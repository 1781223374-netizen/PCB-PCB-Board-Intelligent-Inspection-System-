`timescale 1ns/1ps
`default_nettype none
// One immutable DDR frame per SCAM transaction. One row request at a time:
// 128 return beats fit wholly in the 256-entry response FIFO even while UDP
// is stalled. No Ethernet backpressure is propagated into the HDMI reader.
module scam_camera_sender #(
 parameter WIDTH=1920,HEIGHT=1080,FRAME_INTERVAL=62500000,PACKET_GAP=12500,DEFAULT_FPS=2
)(input wire clk,rst_n,link_ready,udp_busy,
 output wire [12:0] cmd,output wire cmd_valid,input wire cmd_ready,
 input wire [129:0] response,input wire response_valid,output wire response_ready,
 output wire udp_req,udp_valid,output wire [7:0] udp_data,output wire [15:0] udp_len,
 input wire [7:0] requested_fps);
 localparam FRAME_BYTES=WIDTH*HEIGHT*2,CHUNK_BYTES=1408,PACKETS=(FRAME_BYTES+1407)/1408;
 localparam [15:0] HEADER_WIDTH=WIDTH,HEADER_HEIGHT=HEIGHT,HEADER_PACKETS=PACKETS;
 localparam [31:0] HEADER_BYTES=FRAME_BYTES;
 localparam WAIT_FRAME=0,PIN=1,PIN_ACK=2,FILL=3,ROW=4,REQUEST=5,SEND=6,WAIT_END=7,GAP=8,RELEASE=9,END_ACK=10;
 reg [3:0] state;
 (* async_reg="true" *) reg [1:0] release_sync,link_sync;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)release_sync<=0;else release_sync<={release_sync[0],1'b1};
 always @(posedge clk or negedge release_sync[1])
  if(!release_sync[1])link_sync<=0;else link_sync<={link_sync[0],link_ready};
 reg [26:0] timer;
 reg [13:0] gap_timer;
 reg [26:0] effective_interval;reg [13:0] effective_gap;reg [7:0] effective_fps;
 reg [26:0] selected_interval;reg [13:0] selected_gap;reg rate_supported;
 always @* begin
  selected_interval=FRAME_INTERVAL;selected_gap=PACKET_GAP;rate_supported=1'b1;
  case(requested_fps)
   1:begin selected_interval=125000000;selected_gap=15000;end
   2:begin selected_interval=62500000;selected_gap=12500;end
   3:begin selected_interval=41666667;selected_gap=7500;end
   4:begin selected_interval=31250000;selected_gap=5000;end
   default:rate_supported=1'b0;
  endcase
 end
 reg [31:0] frame_id,offset;
 reg [15:0] packet_id;
 reg [10:0] byte_index;
 reg [10:0] next_row;
 reg [8:0] row_remaining;
 reg [6:0] filled;
 wire [15:0] payload_len=offset+CHUNK_BYTES>FRAME_BYTES ? FRAME_BYTES-offset : CHUNK_BYTES;
 // Upper flag byte acknowledges the applied rate. Existing SCAM v1 receivers
 // still read armed/active from bits 0/1. Rate changes never split a frame.
 wire [255:0] header={32'h5343414d,8'd1,8'd1,{effective_fps,8'd0},frame_id,
                     HEADER_WIDTH,HEADER_HEIGHT,packet_id,HEADER_PACKETS,
                     offset,HEADER_BYTES,payload_len,16'd0};
 (* ram_style="bram" *) reg [127:0] packet_memory[0:87];
 reg [127:0] packet_q;
 wire [6:0] prefetch=(byte_index>=31)?((byte_index-31)>>4):0;
 wire fill_take=state==FILL && row_remaining!=0 && filled<(payload_len>>4) && response_valid;
 always @(posedge clk)begin
  if(fill_take && response[129:128]==0)packet_memory[filled]<=response[127:0];
  packet_q<=packet_memory[prefetch];
 end
 assign cmd=state==PIN?13'h1000:state==RELEASE?13'h1800:{2'b00,next_row};
 assign cmd_valid=state==PIN || state==ROW || state==RELEASE;
 assign response_ready=state==PIN_ACK || state==END_ACK || (state==FILL && row_remaining!=0 && filled<(payload_len>>4));
 assign udp_req=state==REQUEST;
 assign udp_valid=state==SEND;
 assign udp_len=32+payload_len;
 assign udp_data=byte_index<32 ? header[255-byte_index*8 -: 8] : packet_q[byte_index[3:0]*8+:8];
 always @(posedge clk or negedge release_sync[1])begin
  if(!release_sync[1])begin
   state<=WAIT_FRAME;timer<=0;gap_timer<=0;frame_id<=0;offset<=0;packet_id<=0;byte_index<=0;
   next_row<=0;row_remaining<=0;filled<=0;
   effective_interval<=FRAME_INTERVAL;effective_gap<=PACKET_GAP;effective_fps<=DEFAULT_FPS;
  end else begin
   if(timer<effective_interval)timer<=timer+1'b1;
   case(state)
    WAIT_FRAME:begin
     if(rate_supported && requested_fps!=effective_fps)begin
      effective_interval<=selected_interval;effective_gap<=selected_gap;effective_fps<=requested_fps;timer<=0;
     end else if(timer>=effective_interval && link_sync[1] && !udp_busy)begin timer<=0;state<=PIN;end
    end
    PIN:if(cmd_ready)state<=PIN_ACK;
    PIN_ACK:if(response_valid)begin
     if(response[129:128]==1 && response[0])begin
      frame_id<=frame_id+1'b1;offset<=0;packet_id<=0;byte_index<=0;
      next_row<=0;row_remaining<=0;filled<=0;state<=FILL;
     end else state<=WAIT_FRAME;
    end
    FILL:begin
     if(filled==(payload_len>>4))state<=REQUEST;
     else if(row_remaining==0)state<=ROW;
     else if(response_valid)begin
      if(response[129:128]!=0)state<=RELEASE;
      else begin filled<=filled+1'b1;row_remaining<=row_remaining-1'b1;end
     end
    end
    ROW:if(cmd_ready)begin next_row<=next_row+1'b1;row_remaining<=WIDTH/8;state<=FILL;end
    REQUEST:if(udp_busy)begin byte_index<=0;state<=SEND;end
    SEND:if(byte_index==udp_len-1)begin byte_index<=0;state<=WAIT_END;end
         else byte_index<=byte_index+1'b1;
    WAIT_END:if(!udp_busy)begin
     if(packet_id==PACKETS-1)begin state<=RELEASE;end
     else begin offset<=offset+CHUNK_BYTES;packet_id<=packet_id+1'b1;filled<=0;gap_timer<=0;state<=GAP;end
    end
    GAP:if(gap_timer==effective_gap-1)state<=FILL;else gap_timer<=gap_timer+1'b1;
    RELEASE:if(cmd_ready)state<=END_ACK;
    END_ACK:if(response_valid)begin
     state<=WAIT_FRAME;
    end
    default:state<=WAIT_FRAME;
   endcase
  end
 end
endmodule
`default_nettype wire
