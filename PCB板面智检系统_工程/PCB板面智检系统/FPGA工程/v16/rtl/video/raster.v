`timescale 1ns/1ps
`default_nettype none
module raster #(
    parameter H_ACTIVE=1920,H_TOTAL=2080,H_START=1968,H_END=2000,
    parameter V_ACTIVE=1080,V_TOTAL=1106,V_START=1083,V_END=1088
)(
    input wire clk,rst_n,
    output reg [11:0] x,y,
    output wire de,hs,vs,buffer_boundary
);
    assign de=x<H_ACTIVE && y<V_ACTIVE;
    assign hs=x>=H_START && x<H_END;
    // CVT reduced blanking uses positive H sync and negative V sync.
    assign vs=!(y>=V_START && y<V_END);
    // Swap in vertical blanking, before the next active frame's first pixel.
    assign buffer_boundary=x==0 && y==V_ACTIVE;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin x<=0;y<=0;end
        else if(x==H_TOTAL-1) begin x<=0;y<=y==V_TOTAL-1 ? 12'd0 : y+1'b1;end
        else x<=x+1'b1;
    end
endmodule
`default_nettype wire
