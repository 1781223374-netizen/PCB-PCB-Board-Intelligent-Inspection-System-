// One 3x3 operation, four bits/beat; two registered stages.
module binary_morph4 #(parameter WIDTH=1024,HEIGHT=600,DILATE=1)(
 input clk,rst_n,valid,user,input [3:0] pixels,
 output reg out_valid,out_user,output reg [3:0] out_pixels);
localparam GROUPS=WIDTH/4;
reg [10:0] x,y,x0,y0;
reg v0,u0;
(* ram_style="bram" *) reg [3:0] row1[0:GROUPS-1],row2[0:GROUPS-1];
reg [3:0] top,mid,bot;
reg [1:0] ht,hm,hb;
wire [5:0] t={top,x0==0?2'b0:ht},m={mid,x0==0?2'b0:hm},b={bot,x0==0?2'b0:hb};
wire [10:0] ax=user?0:x,ay=user?0:y;
always @(posedge clk) if(valid) begin
 top<=row2[ax];mid<=row1[ax];bot<=pixels;
 row2[ax]<=row1[ax];row1[ax]<=pixels;
end
integer i;
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin x<=0;y<=0;x0<=0;y0<=0;v0<=0;u0<=0;out_valid<=0;out_user<=0;out_pixels<=0;ht<=0;hm<=0;hb<=0;end
 else begin
  v0<=valid;u0<=user;x0<=ax;y0<=ay;out_valid<=v0;out_user<=u0;
  if(user) begin x<=valid?1:0;y<=0;end
  else if(valid) begin
   if(x==GROUPS-1) begin x<=0;y<=y==HEIGHT-1?0:y+1'b1;end else x<=x+1'b1;
  end
  if(v0) begin ht<=top[3:2];hm<=mid[3:2];hb<=bot[3:2];end
  for(i=0;i<4;i=i+1)
   if(y0<2 || (x0==0 && i<2)) out_pixels[i]<=0;
   else if(DILATE) out_pixels[i]<=|{t[i+:3],m[i+:3],b[i+:3]};
   else out_pixels[i]<=&{t[i+:3],m[i+:3],b[i+:3]};
 end
end
endmodule
