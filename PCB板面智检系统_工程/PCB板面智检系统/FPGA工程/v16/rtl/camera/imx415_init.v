`timescale 1ns/1ps
`default_nettype none
module imx415_init #(
    parameter POWER_WAIT=12500000,
    parameter CLOCK_WAIT=50,
    parameter CONFIG_WAIT=1500,
    parameter STANDBY_WAIT=1200000,
    parameter HALF_CYCLES=250,
    parameter RETRIES=2
)(
    input wire clk,rst_n,
    output reg sensor_rst_n,clock_enable,configured,init_error,
    output reg [8:0] config_index,
    inout wire scl,sda
);
    localparam POWER=0,CLOCK=1,WAIT_CFG=2,SEND=3,WAIT_ACK=4,
               WAIT_REGULATOR=5,DONE=6,ERROR=7;
    reg [3:0] state;
    reg [31:0] timer;
    reg [2:0] retry_count;
    reg request;
    wire busy,transaction_done,transaction_failed;
    wire [23:0] entry;
    wire [8:0] rom_count;
    wire [23:0] command=config_index<rom_count ? entry :
                         config_index==rom_count ? 24'h300000 : 24'h300200;
    imx415_regs u_regs(.index(config_index),.entry(entry),.count(rom_count));
    i2c_write16 #(.HALF_CYCLES(HALF_CYCLES)) u_i2c(
        .clk(clk),.rst_n(rst_n),.start(request),.reg_address(command[23:8]),.reg_data(command[7:0]),
        .busy(busy),.done(transaction_done),.failed(transaction_failed),.scl(scl),.sda(sda));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=POWER;timer<=0;retry_count<=0;request<=0;
            sensor_rst_n<=0;clock_enable<=0;configured<=0;init_error<=0;config_index<=0;
        end else begin
            request<=0;
            case(state)
                POWER: if(timer>=POWER_WAIT-1) begin timer<=0;sensor_rst_n<=1;state<=CLOCK;end else timer<=timer+1'b1;
                CLOCK: if(timer>=CLOCK_WAIT-1) begin timer<=0;clock_enable<=1;state<=WAIT_CFG;end else timer<=timer+1'b1;
                WAIT_CFG: if(timer>=CONFIG_WAIT-1) begin timer<=0;state<=SEND;end else timer<=timer+1'b1;
                SEND: if(!busy) begin request<=1;state<=WAIT_ACK;end
                WAIT_ACK: if(transaction_done) begin
                    if(transaction_failed) begin
                        if(retry_count>=RETRIES) begin init_error<=1;state<=ERROR;end
                        else begin retry_count<=retry_count+1'b1;state<=SEND;end
                    end else begin
                        retry_count<=0;
                        if(config_index==rom_count+1) begin configured<=1;state<=DONE;end
                        else if(config_index==rom_count) begin config_index<=config_index+1'b1;timer<=0;state<=WAIT_REGULATOR;end
                        else begin config_index<=config_index+1'b1;state<=SEND;end
                    end
                end
                WAIT_REGULATOR: if(timer>=STANDBY_WAIT-1) begin timer<=0;state<=SEND;end else timer<=timer+1'b1;
                DONE: configured<=1;
                ERROR:init_error<=1;
                default:state<=ERROR;
            endcase
        end
    end
endmodule
`default_nettype wire
