`timescale 1ns/1ps
`default_nettype none
// Q8 ratio of two accumulated RAW channels. Iterative unsigned division.
module color_ratio_solver #(parameter SUM_BITS=28,MIN_GAIN=128,MAX_GAIN=1024)(
 input wire clk,rst_n,start,
 input wire [SUM_BITS-1:0] numerator_sum,denominator_sum,
 output reg busy,done,valid,output reg [12:0] gain
);
 localparam N=SUM_BITS+8;
 reg [N-1:0] numerator,quotient;
 reg [SUM_BITS:0] remainder;
 reg [SUM_BITS-1:0] denominator;
 reg [6:0] remaining;
 wire [SUM_BITS:0] trial={remainder[SUM_BITS-1:0],numerator[N-1]};
 wire take=trial>={1'b0,denominator};
 wire [N-1:0] next_q={quotient[N-2:0],take};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin busy<=0;done<=0;valid<=0;gain<=256;numerator<=0;quotient<=0;remainder<=0;denominator<=0;remaining<=0;end
  else begin
   done<=0;
   if(start && !busy)begin
    valid<=0;
    if(denominator_sum==0 || numerator_sum==0)done<=1;
    else begin busy<=1;numerator<={numerator_sum,8'd0};denominator<=denominator_sum;quotient<=0;remainder<=0;remaining<=N;end
   end else if(busy)begin
    numerator<=numerator<<1;quotient<=next_q;remainder<=take?trial-{1'b0,denominator}:trial;remaining<=remaining-1'b1;
    if(remaining==1)begin
     gain<=next_q>MAX_GAIN?MAX_GAIN:next_q<MIN_GAIN?MIN_GAIN:next_q[12:0];
     busy<=0;done<=1;valid<=1;
    end
   end
  end
 end
endmodule
`default_nettype wire
