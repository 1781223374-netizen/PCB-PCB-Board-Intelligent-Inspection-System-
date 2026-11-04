`timescale 1ns/1ps
`default_nettype none
// BMP is a complete top-down RGB24 raster. Retain the top-left sample in
// every 4x4 display cell as RGB565; write two pixels per framebuffer word.
module playback_rgb565 #(parameter WIDTH=1024,HEIGHT=600,SCALE=4,ADDR_BITS=17)(
    input wire clk,rst_n,enable,start,input wire [7:0] data,input wire valid,
    output wire ready,output reg done,write_enable,
    output reg [ADDR_BITS-1:0] write_addr,output reg [31:0] write_data,input wire store_ready
);
    reg active;reg [1:0] channel;reg [7:0] b,g;
    reg [15:0] first;reg [11:0] x,y;reg [ADDR_BITS-1:0] words;
    wire [15:0] pixel={data[7:3],g[7:2],b[7:3]};
    assign ready=enable && active && (SCALE!=1 || store_ready);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            active<=0;channel<=0;b<=0;g<=0;first<=0;x<=0;y<=0;words<=0;
            done<=0;write_enable<=0;write_addr<=0;write_data<=0;
        end else begin
            write_enable<=0;
            if(!enable)begin active<=0;done<=0;end
            else if(start)begin active<=1;channel<=0;x<=0;y<=0;words<=0;done<=0;end
            else if(valid && ready)begin
                if(channel==0)begin b<=data;channel<=1;end
                else if(channel==1)begin g<=data;channel<=2;end
                else begin
                    channel<=0;
                    if(SCALE==1 || (y[1:0]==0 && x[1:0]==0))begin
                        if(SCALE==1?!x[0]:!x[2])first<=pixel;
                        else begin write_enable<=1;write_addr<=words;write_data<={pixel,first};words<=words+1'b1;end
                    end
                    if(x==WIDTH-1)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
                    if(x==WIDTH-1 && y==HEIGHT-1)begin active<=0;done<=1;end
                end
            end
        end
    end
endmodule
`default_nettype wire
