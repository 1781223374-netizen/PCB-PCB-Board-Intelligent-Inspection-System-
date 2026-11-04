// Active-low keys: qualify both edges; boot-held keys must first be released.
module ui_keys8 #(parameter DEBOUNCE_CYCLES=500000,REPEAT_DELAY=20000000,REPEAT_RATE=5000000)(
 input clk,rst_n,input [7:0] key_n,
 output reg [7:0] press,output [7:0] repeat_event,down,output armed);
(* keep=1,preserve=1,allow_backward_retiming=0,allow_forward_retiming=0 *) reg [7:0] meta,sync;
reg [7:0] stable,ready;
reg [1:0] sync_valid;
// Informational only: no key is gated by another key's readiness.
assign armed=&ready;
assign down=ready & ~stable;
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin meta<=8'hff;sync<=8'hff;sync_valid<=0;end
 else begin meta<=key_n;sync<=meta;sync_valid<={sync_valid[0],1'b1};end
end
genvar k;
generate for(k=0;k<8;k=k+1) begin:KEY
 localparam DEBOUNCE_BITS=DEBOUNCE_CYCLES>1?$clog2(DEBOUNCE_CYCLES+1):1;
 reg [DEBOUNCE_BITS-1:0] debounce_count;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin stable[k]<=1;ready[k]<=0;debounce_count<=0;press[k]<=0;end
  else begin
   press[k]<=0;
   // A boot-held key must be released stably before it can issue an event.
   // Reuse its debounce counter; the other seven keys remain operational.
   if(!ready[k]) begin
    stable[k]<=1;
    if(!sync_valid[1] || !sync[k]) debounce_count<=0;
    else if(debounce_count==DEBOUNCE_CYCLES-1) begin ready[k]<=1;debounce_count<=0;end
    else debounce_count<=debounce_count+1'b1;
   end else if(sync[k]==stable[k]) debounce_count<=0;
   else if(debounce_count==DEBOUNCE_CYCLES-1) begin
    stable[k]<=sync[k];debounce_count<=0;
    if(!sync[k]) press[k]<=1;
   end else debounce_count<=debounce_count+1'b1;
  end
 end
 if(k>=2 && k<=5) begin:ARROW
  reg [31:0] repeat_count;reg repeating,ev;
  assign repeat_event[k]=ev;
  always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin repeat_count<=0;repeating<=0;ev<=0;end
   else begin
    ev<=0;
    if(!down[k]) begin repeat_count<=0;repeating<=0;end
    else if(repeat_count==(repeating?REPEAT_RATE:REPEAT_DELAY)-1) begin
     ev<=1;repeat_count<=0;repeating<=1;
    end else repeat_count<=repeat_count+1'b1;
   end
  end
 end else begin:NO_REPEAT
  assign repeat_event[k]=1'b0;
 end
end endgenerate
endmodule
