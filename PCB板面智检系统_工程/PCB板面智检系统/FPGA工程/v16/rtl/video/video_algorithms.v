`timescale 1ns/1ps
`default_nettype none
// One raster pixel per clock -> four-pixel ISP beats -> one raster pixel.
// All eight modes share exactly 16 registered stages, including packing.
module video_algorithms #(
    parameter WIDTH=1024,HEIGHT=600
)(
    input wire clk,rst_n,
    input wire [23:0] in_rgb,
    input wire in_de,in_hs,in_vs,
    input wire [11:0] in_x,in_y,
    input wire [2:0] selected,threshold_sel,
    input wire compare_original,
    output reg [23:0] out_rgb,
    output wire out_de,out_hs,out_vs,
    output wire [11:0] out_x,out_y,
    output wire histogram_ready
);
    reg [95:0] packed_rgb;
    reg packed_valid,packed_user,packed_last;
    wire [95:0] processed;
    wire processed_valid;
    wire [3:0] mode=compare_original ? 4'd1 : {1'b0,selected}+4'd1;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin packed_rgb<=0;packed_valid<=0;packed_user<=0;packed_last<=0;end
        else begin
            if(in_de)packed_rgb<={packed_rgb[71:0],in_rgb};
            packed_valid<=in_de && in_x[1:0]==3;
            packed_user<=in_de && in_x==3 && in_y==0;
            packed_last<=in_de && in_x==WIDTH-1;
        end
    end
    vision_core96 #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT)) u_algorithms(
        .I_clk(clk),.I_rst_n(rst_n),.I_tlast(packed_last),.I_tuser(packed_user),.I_tdata(packed_rgb),.I_tvalid(packed_valid),
        .I_mode(mode),.I_th_sel(threshold_sel),.O_tlast(),.O_tuser(),.O_tvalid(processed_valid),
        .O_tdata(processed),.O_hist_ready(histogram_ready),.O_amb_gray(),.O_amb_user(),.O_amb_last(),.O_amb_valid());
    reg [71:0] remaining;
    reg [1:0] serialize_position;
    reg [15:0] de_pipe,hs_pipe,vs_pipe;
    reg [11:0] x_pipe[0:15],y_pipe[0:15];
    integer k;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            remaining<=0;serialize_position<=0;out_rgb<=0;de_pipe<=0;hs_pipe<=0;vs_pipe<=0;
            for(k=0;k<16;k=k+1)begin x_pipe[k]<=0;y_pipe[k]<=0;end
        end else begin
            de_pipe<={de_pipe[14:0],in_de};hs_pipe<={hs_pipe[14:0],in_hs};vs_pipe<={vs_pipe[14:0],in_vs};
            x_pipe[0]<=in_x;y_pipe[0]<=in_y;
            for(k=1;k<16;k=k+1)begin x_pipe[k]<=x_pipe[k-1];y_pipe[k]<=y_pipe[k-1];end
            if(processed_valid)begin out_rgb<=processed[95:72];remaining<=processed[71:0];serialize_position<=1;end
            else if(serialize_position!=0)begin
                out_rgb<=remaining[71:48];remaining<={remaining[47:0],24'd0};serialize_position<=serialize_position+1'b1;
            end else out_rgb<=0;
        end
    end
    assign out_de=de_pipe[15];assign out_hs=hs_pipe[15];assign out_vs=vs_pipe[15];
    assign out_x=x_pipe[15];assign out_y=y_pipe[15];
endmodule
`default_nettype wire
