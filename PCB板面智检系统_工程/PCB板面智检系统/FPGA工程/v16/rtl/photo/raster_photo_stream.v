`timescale 1ns/1ps
// Credit-counted pixel ring overlaps raster collection with SD byte consumption.
// Consumers may start after the first pixel; producers resume on any free credit.
// This avoids waiting for an entire bank to be filled or drained. Capacity must
// be a power-of-two number of RGB pixels (98304 bytes = 32768 pixels).
// The source remains frozen until FAT32 publishes the completed file.
module raster_photo_stream #(parameter WIDTH=1024,HEIGHT=600,BUFFER_BYTES=4096)(
 input clk,rst_n,hold_frame,stream_start,input [23:0] rgb,
 input de,input [11:0] x,y,input byte_ready,
 output [7:0] byte_data,output byte_valid,output reg [7:0] error);
 localparam TOTAL_PIXELS=WIDTH*HEIGHT;
 localparam PIXELS=BUFFER_BYTES/3;
 localparam AB=PIXELS>1?$clog2(PIXELS):1;
 localparam CB=$clog2(PIXELS+1);
 reg [20:0] written,consumed;
 reg [AB-1:0] write_pointer,read_pointer;
 reg [CB-1:0] count;
 reg [1:0] channel,read_wait;
 reg active,ready;
 localparam SEG_AW=AB>11?11:AB;
 localparam SEGMENTS=1<<(AB-SEG_AW);
 localparam SEL_BITS=SEGMENTS>1?$clog2(SEGMENTS):1;
 reg [AB-1:0] ram_read_address;
 reg [SEL_BITS-1:0] read_segment;
 wire [AB-1:0] ram_write_address=write_pointer;
 wire [23:0] ram_q[0:SEGMENTS-1];
 wire [23:0] read_q=ram_q[read_segment];
 wire [20:0] position=y*WIDTH+x;
 wire capture=active && hold_frame && !stream_start && written<TOTAL_PIXELS &&
              count<PIXELS && de && position==written;
 wire pop=byte_valid && byte_ready && channel==2;
 always @(posedge clk)begin
  ram_read_address<=read_pointer;
  read_segment<=ram_read_address>>SEG_AW;
 end
 genvar segment,lane;
 generate for(segment=0;segment<SEGMENTS;segment=segment+1)begin:ram_segment
  for(lane=0;lane<3;lane=lane+1)begin:byte_lane
   PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),
    .ADDR_WIDTH_A(SEG_AW),.ADDR_WIDTH_B(SEG_AW),.DATA_DEPTH_A(1<<SEG_AW),.DATA_DEPTH_B(1<<SEG_AW),
    .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.CLKMODE("SYNC")) memory(
    .clka(clk),.cea(1'b1),.ocea(1'b1),.rsta(1'b0),.bea(1'b1),
    .addra(ram_write_address[SEG_AW-1:0]),.dia(rgb[lane*8+:8]),
    .wea(capture && (ram_write_address>>SEG_AW)==segment),.doa(),
    .clkb(clk),.ceb(1'b1),.oceb(1'b1),.rstb(1'b0),.beb(1'b1),
    .addrb(ram_read_address[SEG_AW-1:0]),.dib(8'd0),.web(1'b0),.dob(ram_q[segment][lane*8+:8]),
    .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
  end
 end endgenerate
 assign byte_data=channel==0?read_q[7:0]:channel==1?read_q[15:8]:read_q[23:16];
 assign byte_valid=active && ready && hold_frame && !stream_start;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   written<=0;consumed<=0;write_pointer<=0;read_pointer<=0;count<=0;
   channel<=0;read_wait<=0;active<=0;ready<=0;error<=0;
  end else if(!hold_frame)begin
   active<=0;ready<=0;count<=0;read_wait<=0;error<=0;
  end else if(stream_start)begin
   written<=0;consumed<=0;write_pointer<=0;read_pointer<=0;count<=0;
   channel<=0;read_wait<=0;active<=1;ready<=0;error<=0;
  end else if(active)begin
   if(capture)begin written<=written+1'b1;write_pointer<=write_pointer+1'b1;end
   case({capture,pop})
    2'b10:count<=count+1'b1;
    2'b01:count<=count-1'b1;
   endcase
   if(!ready && read_wait==0 && count!=0)read_wait<=2;
   if(read_wait!=0)begin
    read_wait<=read_wait-1'b1;
    if(read_wait==1)ready<=1;
   end
   if(byte_valid && byte_ready)begin
    if(channel==2)begin
     channel<=0;ready<=0;consumed<=consumed+1'b1;read_pointer<=read_pointer+1'b1;
     if(consumed+1==TOTAL_PIXELS)active<=0;
     else if(count>1 || capture)read_wait<=2;
    end else channel<=channel+1'b1;
   end
  end
 end
endmodule
