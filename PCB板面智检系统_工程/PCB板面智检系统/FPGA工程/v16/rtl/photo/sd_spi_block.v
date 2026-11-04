// SDHC/SDXC SPI, 512-byte sectors. No SDSC byte addressing, no formatting.
// Mode0; init uses equal half periods. FAST_ODD uses a shorter HIGH phase
// only at DATA_DIV, keeping the longer LOW phase for card output settling.
// At114.75MHz/DIV3: LOW3 + HIGH2 clocks ->22.95MHz, both phases >=17.43ns.
module sd_spi_block #(parameter INIT_DIV=134,DATA_DIV=4,POWER_WAIT=666667,TIMEOUT=133333334,FAST_ODD=0)(
 input clk,rst_n,reinit,input start,write_block,input [31:0] lba,
 output reg ready,busy,done,output reg [7:0] error,
 output reg [8:0] index,output reg rx_valid,output reg [7:0] rx_data,
 output [8:0] tx_index,input [7:0] tx_data,
 output reg cs_n,output sck,mosi,input miso);
reg byte_start;reg [7:0] byte_tx;wire [7:0] byte_rx;wire byte_done;
reg fast;
spi_byte_master #(.FAST_DIV(FAST_ODD?DATA_DIV:0)) BYTE(clk,rst_n,byte_start,byte_tx,fast?DATA_DIV:INIT_DIV,sck,mosi,miso,byte_done,byte_rx);
assign tx_index=index;
localparam POWER=0,CLOCKS=1,CMD_SEND=2,CMD_R1=3,EXTRA=4,CMD_END=5,IDLE=6,
 READ_TOKEN=7,READ_DATA=8,READ_CRC1=9,READ_CRC2=10,WRITE_TOKEN=11,
 WRITE_FETCH=12,WRITE_DATA=13,WRITE_CRC1=14,WRITE_CRC2=15,WRITE_RESP=16,WRITE_BUSY=17,
 STATUS2=18,FAIL=19,BYTE_WAIT=20,FINISH=21,WRITE_LATCH=22,COMPLETE=23;
reg [5:0] state,ret;
reg [47:0] packet;reg [5:0] command;
reg [2:0] cmd_pos,extra_count;reg [7:0] r1;
reg [31:0] extra,timeout_count;reg [7:0] clocks;
reg [15:0] crc,read_crc;reg write_op;
function [15:0] crc16;input [15:0] c;input [7:0] d;reg [15:0] v;integer i;
 begin v=c;for(i=7;i>=0;i=i-1) v={v[14:0],1'b0}^((v[15]^d[i])?16'h1021:16'h0);crc16=v;end
endfunction
task send;input [7:0] b;input [5:0] next_state;begin byte_tx<=b;byte_start<=1;ret<=next_state;state<=BYTE_WAIT;end endtask
task cmd;input [5:0] c;input [31:0] arg;begin
 command<=c;packet<={2'b01,c,arg,(c==0?8'h95:c==8?8'h87:8'h01)};
 cmd_pos<=0;cs_n<=0;state<=CMD_SEND;
end endtask
task fail;input [7:0] code;begin error<=code;ready<=0;busy<=0;done<=1;cs_n<=1;state<=FAIL;end endtask
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin state<=POWER;ret<=0;ready<=0;busy<=1;done<=0;error<=0;cs_n<=1;fast<=0;byte_start<=0;byte_tx<=255;
  index<=0;rx_valid<=0;rx_data<=0;timeout_count<=0;clocks<=0;command<=0;packet<=0;cmd_pos<=0;extra<=0;extra_count<=0;r1<=255;crc<=0;read_crc<=0;write_op<=0;
 end else begin
  byte_start<=0;done<=0;rx_valid<=0;
  if(state!=IDLE && state!=FAIL) timeout_count<=timeout_count+1'b1;
  case(state)
   POWER:if(timeout_count>=POWER_WAIT) begin timeout_count<=0;clocks<=0;state<=CLOCKS;end
   CLOCKS:if(clocks==12) begin timeout_count<=0;cmd(0,0);end else begin clocks<=clocks+1'b1;send(255,CLOCKS);end
   BYTE_WAIT:if(byte_done) state<=ret;
   CMD_SEND:if(cmd_pos==6) send(255,CMD_R1);else begin cmd_pos<=cmd_pos+1'b1;packet<={packet[39:0],8'hff};send(packet[47:40],CMD_SEND);end
   CMD_R1:if(byte_rx[7]) send(255,CMD_R1);else begin
    r1<=byte_rx;extra<=0;extra_count<=0;
    case(command)
     0:if(byte_rx==1) state<=CMD_END;else fail(8'h11);
     8,58:if(byte_rx==(command==8?1:0)) send(255,EXTRA);else fail(8'h12);
     55:if(byte_rx<=1) state<=CMD_END;else fail(8'h13);
     41:if(byte_rx<=1) state<=CMD_END;else fail(8'h14);
     17:if(byte_rx==0) begin crc<=0;index<=0;send(255,READ_TOKEN);end else fail(8'h21);
     24:if(byte_rx==0) begin crc<=0;index<=0;send(255,WRITE_TOKEN);end else fail(8'h22);
     13:if(byte_rx==0) send(255,STATUS2);else fail(8'h26);
     default:fail(8'h1f);
    endcase
   end
   EXTRA:begin extra<={extra[23:0],byte_rx};extra_count<=extra_count+1'b1;if(extra_count==3) state<=CMD_END;else send(255,EXTRA);end
   CMD_END:begin
    cs_n<=1;
    case(command)
     0:begin command<=8;send(255,FINISH);end
     8:if(extra[11:0]==12'h1aa) begin command<=55;send(255,FINISH);end else fail(8'h15);
     55:begin command<=41;send(255,FINISH);end
     41:begin command<=r1==0?58:55;send(255,FINISH);end
     58:if(extra[31:30]==2'b11) begin fast<=1;ready<=1;send(255,IDLE);end else fail(8'h16);
     default:send(255,COMPLETE);
    endcase
   end
   FINISH:case(command) 8:cmd(8,32'h1aa);55:cmd(55,0);41:cmd(41,32'h40000000);58:cmd(58,0);default:fail(8'h1f);endcase
   IDLE:begin timeout_count<=0;busy<=0;if(start && ready) begin busy<=1;error<=0;write_op<=write_block;cmd(write_block?24:17,lba);end end
   READ_TOKEN:if(byte_rx==8'hfe) send(255,READ_DATA);else if(byte_rx==255) send(255,READ_TOKEN);else fail(8'h23);
   READ_DATA:begin rx_valid<=1;rx_data<=byte_rx;crc<=crc16(crc,byte_rx);
    if(index==511) send(255,READ_CRC1);else begin index<=index+1'b1;send(255,READ_DATA);end
   end
   READ_CRC1:begin read_crc[15:8]<=byte_rx;send(255,READ_CRC2);end
   READ_CRC2:if({read_crc[15:8],byte_rx}==crc) state<=CMD_END;else fail(8'h24);
   WRITE_TOKEN:send(8'hfe,WRITE_FETCH);
   WRITE_FETCH:state<=WRITE_LATCH;
   WRITE_LATCH:send(tx_data,WRITE_DATA);
   WRITE_DATA:begin crc<=crc16(crc,byte_tx);if(index==511) state<=WRITE_CRC1;else begin index<=index+1'b1;state<=WRITE_FETCH;end end
   WRITE_CRC1:send(crc[15:8],WRITE_CRC2);
   WRITE_CRC2:send(crc[7:0],WRITE_RESP);
   WRITE_RESP:begin send(255,WRITE_BUSY);clocks<=0;end
   WRITE_BUSY:begin
    if(clocks==0) begin
     if(byte_rx==255) send(255,WRITE_BUSY);
     else if(byte_rx[4:0]==5'b00101) begin clocks<=1;send(255,WRITE_BUSY);end else fail(8'h25);
    end else if(byte_rx==255) cmd(13,0);else send(255,WRITE_BUSY);
   end
   STATUS2:if(byte_rx==0) state<=CMD_END;else fail(8'h26);
   COMPLETE:begin done<=1;busy<=0;state<=IDLE;end
   FAIL:begin end
   default:fail(8'h1f);
  endcase
  if(timeout_count>=TIMEOUT && state!=IDLE && state!=FAIL) fail(8'h10);
  if(reinit && !busy) begin state<=POWER;ready<=0;busy<=1;error<=0;cs_n<=1;fast<=0;timeout_count<=0;end
 end
end
endmodule

module spi_byte_master #(parameter FAST_DIV=0)(input clk,rst_n,start,input [7:0] tx,input [31:0] half_div,
 output reg sck,mosi,input miso,output reg done,output reg [7:0] rx);
reg active;reg [15:0] div_count;reg [3:0] bits;reg [7:0] shift;
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin active<=0;sck<=0;mosi<=1;done<=0;rx<=255;div_count<=0;bits<=0;shift<=0;end
 else begin done<=0;
  if(!active) begin sck<=0;if(start) begin active<=1;shift<=tx;mosi<=tx[7];bits<=0;div_count<=0;end end
  else if(div_count==((FAST_DIV>=2 && half_div==FAST_DIV && sck)?half_div-2:half_div-1)) begin div_count<=0;sck<=~sck;
   if(!sck) begin rx<={rx[6:0],miso};bits<=bits+1'b1;end
   else if(bits==8) begin active<=0;done<=1;mosi<=1;end
   else begin shift<={shift[6:0],1'b1};mosi<=shift[6];end
  end else div_count<=div_count+1'b1;
 end
end
endmodule
