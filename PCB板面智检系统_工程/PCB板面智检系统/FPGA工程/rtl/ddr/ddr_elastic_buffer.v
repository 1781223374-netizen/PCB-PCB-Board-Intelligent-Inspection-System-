`timescale 1ns/1ps
// Two entries isolate upstream ready from downstream arbitration, while the
// unobstructed path sustains one beat per cycle. Both outputs hold on stalls.
module ddr_elastic_buffer #(parameter WIDTH=37)(
 input clk,rst_n,input [WIDTH-1:0] in_data,input in_valid,output in_ready,
 output reg [WIDTH-1:0] out_data,output reg out_valid,input out_ready);
 reg tail_valid;reg [WIDTH-1:0] tail_data;
 assign in_ready=!tail_valid;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin out_valid<=0;tail_valid<=0;out_data<=0;tail_data<=0;end
  else if(!out_valid || out_ready)begin
   if(tail_valid)begin out_valid<=1;out_data<=tail_data;tail_valid<=0;end
   else begin out_valid<=in_valid;if(in_valid)out_data<=in_data;end
  end else if(in_valid && in_ready)begin tail_valid<=1;tail_data<=in_data;end
 end
endmodule
