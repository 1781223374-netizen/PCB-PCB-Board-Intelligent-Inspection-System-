// Exact 256-bin gray histogram, four independent lane RAMs with write forwarding.
// Build the CDF LUT after the last beat; never switch mappings within a frame.
// If blanking is too short, bypass that entire frame and skip its statistics.
module hist_equal4 #(parameter WIDTH=1024,HEIGHT=600)(
 input clk,rst_n,valid,user,input [31:0] gray,
 output reg [31:0] mapped,output ready);
localparam N=WIDTH*HEIGHT,GROUPS=N/4;
localparam LB=$clog2(GROUPS+1),PB=$clog2(N+1),DB=PB+8;
localparam INIT=0,COLLECT=1,DRAIN=2,READ=3,SUM=4,PREP=5,CDF=6,SETUP=7,LOAD=8,DIVIDE=9,WRITE=10;
reg [3:0] state;
reg [7:0] bin;
reg [LB-1:0] groups;reg [PB-1:0] cdf,base;
reg base_valid,collect_frame,map_ready,use_map,flat_map;
reg [1:0] drain;
reg [DB-1:0] dividend,quotient;
reg [PB:0] remainder;
reg [PB-1:0] denominator;
reg [4:0] steps;
reg [7:0] result;
reg [31:0] gray_d,map_read;
wire [LB-1:0] lane_count[0:3];
reg [LB:0] sum01,sum23;
reg [PB-1:0] bin_sum,delta;
wire [PB-1:0] cdf_next=cdf+bin_sum;
wire [PB:0] trial={remainder[PB-1:0],dividend[DB-1]};
wire subtract=trial>={1'b0,denominator};
wire [DB-1:0] next_q={quotient[DB-2:0],subtract};
wire take=state==COLLECT && (user || collect_frame) && valid;
assign ready=map_ready;
genvar i;
generate for(i=0;i<4;i=i+1) begin:H
 (* ram_style="bram" *) reg [LB-1:0] hist[0:255];
 (* ram_style="bram" *) reg [7:0] lut[0:255];
 reg [LB-1:0] rd,last_value;
 reg [7:0] addr,last_addr;
 reg pending,last_write;
 wire [LB-1:0] updated=((last_write && addr==last_addr)?last_value:rd)+1'b1;
 always @(posedge clk) begin
  rd<=hist[state==COLLECT?gray[8*i+:8]:bin];
  if(pending) hist[addr]<=updated;
  else if(state==INIT || state==WRITE) hist[bin]<=0;
  if(state==WRITE) lut[bin]<=result;
  map_read[8*i+:8]<=lut[gray[8*i+:8]];
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin pending<=0;addr<=0;last_addr<=0;last_value<=0;last_write<=0;end
  else begin
   pending<=take;addr<=gray[8*i+:8];last_write<=pending;
   if(pending) begin last_addr<=addr;last_value<=updated;end
  end
 end
 assign lane_count[i]=rd;
end endgenerate
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
  state<=INIT;bin<=0;groups<=0;cdf<=0;base<=0;base_valid<=0;collect_frame<=0;
  map_ready<=0;use_map<=0;flat_map<=0;drain<=0;dividend<=0;quotient<=0;remainder<=0;
  denominator<=0;steps<=0;result<=0;gray_d<=0;mapped<=0;
  sum01<=0;sum23<=0;bin_sum<=0;delta<=0;
 end else begin
  gray_d<=gray;mapped<=use_map?map_read:gray_d;
  if(user) begin
   use_map<=map_ready && state==COLLECT && !flat_map;
   collect_frame<=state==COLLECT;
   groups<=valid?1:0;
  end else if(take) groups<=groups+1'b1;
  case(state)
   INIT: if(bin==255) begin bin<=0;state<=COLLECT;end else bin<=bin+1'b1;
   COLLECT: if(take && (user?0:groups)==GROUPS-1) begin
    state<=DRAIN;drain<=0;collect_frame<=0;map_ready<=0;
   end
   DRAIN: if(drain==2) begin state<=READ;bin<=0;cdf<=0;base<=0;base_valid<=0;end else drain<=drain+1'b1;
   READ: state<=SUM;
   SUM: begin
    sum01<={1'b0,lane_count[0]}+{1'b0,lane_count[1]};
    sum23<={1'b0,lane_count[2]}+{1'b0,lane_count[3]};state<=PREP;
   end
   PREP: begin bin_sum<={1'b0,sum01}+{1'b0,sum23};state<=CDF;end
   CDF: begin
    cdf<=cdf_next;
    if(!base_valid && bin_sum!=0) begin base<=cdf_next;base_valid<=1;end
    state<=SETUP;
   end
   SETUP: begin delta<=cdf-base;denominator<=N-base;state<=LOAD;end
   LOAD: begin
    if(!base_valid || denominator==0) begin
     result<=denominator==0?bin:0;state<=WRITE;
    end else begin
     dividend<=({8'd0,delta}<<8)-{8'd0,delta};
     remainder<=0;quotient<=0;steps<=DB-1;state<=DIVIDE;
    end
   end
   DIVIDE: begin
    remainder<=subtract?trial-{1'b0,denominator}:trial;
    dividend<={dividend[DB-2:0],1'b0};quotient<=next_q;
    if(steps==0) begin result<=next_q[7:0];state<=WRITE;end else steps<=steps-1'b1;
   end
   WRITE: if(bin==255) begin bin<=0;state<=COLLECT;map_ready<=1;flat_map<=base==N;end
          else begin bin<=bin+1'b1;state<=READ;end
   default: state<=INIT;
  endcase
 end
end
endmodule
