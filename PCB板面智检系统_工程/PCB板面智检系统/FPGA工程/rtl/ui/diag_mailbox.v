`timescale 1ns/1ps
`default_nettype none
// Bundled-data request/ack mailbox. Source holds each coherent snapshot until
// the next request; the sink allows additional settling cycles after ack.
module diag_mailbox #(parameter WIDTH=1408,PERIOD=12500000,FREQ_PERIOD=50000000)(
 input wire src_clk,src_rst_n,input wire [WIDTH-1:0] source,
 input wire [31:0] byte_gray,
 input wire dst_clk,dst_rst_n,
 output reg [WIDTH-1:0] snapshot,
 output reg [31:0] snapshot_count,byte_per_second
);
 reg request,acknowledge;
 (* async_reg="true" *)reg [1:0] request_sync,ack_sync;
 (* keep="true" *)reg [WIDTH-1:0] held;
 always @(posedge src_clk or negedge src_rst_n)begin
  if(!src_rst_n)begin request_sync<=0;acknowledge<=0;held<=0;end
  else begin
   request_sync<={request_sync[0],request};
   if(request_sync[1]!=acknowledge)begin held<=source;acknowledge<=request_sync[1];end
  end
 end
 (* async_reg="true" *)reg [31:0] gray_meta,gray_sync;
 reg [31:0] previous_cycles,period_count,freq_count;
 reg pending,observed_ack;
 reg [2:0] settling;
 function [31:0] gray_binary;
  input [31:0] g;integer n;
  begin gray_binary[31]=g[31];for(n=30;n>=0;n=n-1)gray_binary[n]=gray_binary[n+1]^g[n];end
 endfunction
 wire [31:0] current_cycles=gray_binary(gray_sync);
 always @(posedge dst_clk or negedge dst_rst_n)begin
  if(!dst_rst_n)begin
   request<=0;ack_sync<=0;gray_meta<=0;gray_sync<=0;previous_cycles<=0;
   period_count<=0;freq_count<=0;pending<=0;observed_ack<=0;settling<=0;
   snapshot<=0;snapshot_count<=0;byte_per_second<=0;
  end else begin
   ack_sync<={ack_sync[0],acknowledge};gray_meta<=byte_gray;gray_sync<=gray_meta;
   if(period_count==PERIOD-1)begin
    period_count<=0;
    if(!pending)begin request<=~request;pending<=1;settling<=0;end
   end else period_count<=period_count+1'b1;
   if(pending && ack_sync[1]!=observed_ack)begin
    if(settling==3)begin snapshot<=held;snapshot_count<=snapshot_count+1'b1;observed_ack<=ack_sync[1];pending<=0;settling<=0;end
    else settling<=settling+1'b1;
   end
   if(freq_count==FREQ_PERIOD-1)begin
    freq_count<=0;byte_per_second<=current_cycles-previous_cycles;previous_cycles<=current_cycles;
   end else freq_count<=freq_count+1'b1;
  end
 end
endmodule
`default_nettype wire
