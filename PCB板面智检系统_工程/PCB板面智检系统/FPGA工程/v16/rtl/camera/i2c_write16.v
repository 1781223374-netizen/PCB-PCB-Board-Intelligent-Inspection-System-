`timescale 1ns/1ps
`default_nettype none
module i2c_write16 #(
    parameter HALF_CYCLES=250,
    parameter TIMEOUT_CYCLES=1000000,
    parameter DEVICE_ADDRESS=7'h1a
)(
    input wire clk,rst_n,start,
    input wire [15:0] reg_address,
    input wire [7:0] reg_data,
    output reg busy,done,failed,
    inout wire scl,sda
);
    localparam IDLE=0,START_H=1,START_L=2,BIT_L=3,BIT_H=4,
               ACK_L=5,ACK_H=6,STOP_L=7,STOP_H=8,STOP_DONE=9;
    reg [3:0] state;
    reg scl_release,sda_release;
    reg [31:0] bytes;
    reg [1:0] byte_index;
    reg [2:0] bit_index;
    reg [31:0] timer,elapsed;
    wire [7:0] current_byte=bytes[byte_index*8+:8];
    wire high_wait=state==START_H || state==BIT_H || state==ACK_H || state==STOP_H;
    assign scl=scl_release ? 1'bz : 1'b0;
    assign sda=sda_release ? 1'bz : 1'b0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;scl_release<=1;sda_release<=1;busy<=0;done<=0;failed<=0;
            bytes<=0;byte_index<=0;bit_index<=7;timer<=0;elapsed<=0;
        end else begin
            done<=0;
            if(state==IDLE) begin
                timer<=0;elapsed<=0;
                if(start) begin
                    bytes<={reg_data,reg_address[7:0],reg_address[15:8],DEVICE_ADDRESS,1'b0};
                    byte_index<=0;bit_index<=7;busy<=1;failed<=0;
                    scl_release<=1;sda_release<=1;state<=START_H;
                end
            end else if(elapsed>=TIMEOUT_CYCLES-1) begin
                // Release a stuck bus; caller can retry after a reset.
                state<=IDLE;scl_release<=1;sda_release<=1;busy<=0;done<=1;failed<=1;
            end else begin
                elapsed<=elapsed+1'b1;
                if(high_wait && scl!==1'b1) timer<=0;
                else if(timer<HALF_CYCLES-1) timer<=timer+1'b1;
                else begin
                    timer<=0;
                    case(state)
                        START_H: if(sda===1'b1) begin sda_release<=0;state<=START_L;end
                        START_L: begin scl_release<=0;sda_release<=current_byte[7];state<=BIT_L;end
                        BIT_L: begin scl_release<=1;state<=BIT_H;end
                        BIT_H: begin
                            scl_release<=0;
                            if(bit_index==0) begin sda_release<=1;state<=ACK_L;end
                            else begin bit_index<=bit_index-1'b1;sda_release<=current_byte[bit_index-1'b1];state<=BIT_L;end
                        end
                        ACK_L: begin scl_release<=1;state<=ACK_H;end
                        ACK_H: begin
                            scl_release<=0;
                            if(sda!==1'b0 || byte_index==3) begin
                                if(sda!==1'b0) failed<=1;
                                sda_release<=0;state<=STOP_L;
                            end else begin
                                byte_index<=byte_index+1'b1;bit_index<=7;
                                sda_release<=bytes[(byte_index+1)*8+7];state<=BIT_L;
                            end
                        end
                        STOP_L: begin scl_release<=1;state<=STOP_H;end
                        STOP_H: begin sda_release<=1;state<=STOP_DONE;end
                        STOP_DONE: begin state<=IDLE;busy<=0;done<=1;end
                        default:state<=IDLE;
                    endcase
                end
            end
        end
    end
endmodule
`default_nettype wire
