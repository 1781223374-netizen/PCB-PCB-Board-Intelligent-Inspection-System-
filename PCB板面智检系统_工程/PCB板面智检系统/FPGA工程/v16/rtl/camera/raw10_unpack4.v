`timescale 1ns/1ps
`default_nettype none
module raw10_unpack4(
    input wire clk,rst_n,
    input wire line_start_in,line_end_in,
    input wire payload_valid,
    input wire [2:0] payload_bytes,
    input wire [31:0] payload_data,
    output reg line_start,line_end,
    output reg pixels_valid,
    output reg [39:0] pixels,
    output reg format_error
);
    reg [63:0] reservoir,work_data;
    reg [3:0] count,work_count;
    integer j;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            reservoir<=0;count<=0;line_start<=0;line_end<=0;
            pixels_valid<=0;pixels<=0;format_error<=0;
        end else begin
            line_start<=line_start_in;line_end<=line_end_in;
            pixels_valid<=0;format_error<=0;
            work_data=line_start_in ? 64'd0 : reservoir;
            work_count=line_start_in ? 4'd0 : count;
            if(payload_valid) begin
                if(payload_bytes==0 || payload_bytes>4) format_error<=1;
                else for(j=0;j<4;j=j+1) if(j<payload_bytes) begin
                    work_data[work_count*8+:8]=payload_data[j*8+:8];
                    work_count=work_count+1'b1;
                end
            end
            if(work_count>=5) begin
                pixels[9:0]<={work_data[7:0],work_data[33:32]};
                pixels[19:10]<={work_data[15:8],work_data[35:34]};
                pixels[29:20]<={work_data[23:16],work_data[37:36]};
                pixels[39:30]<={work_data[31:24],work_data[39:38]};
                pixels_valid<=1;
                work_data=work_data>>40;work_count=work_count-5;
            end
            if(line_end_in && work_count!=0) begin
                format_error<=1;work_count=0;work_data=0;
            end
            reservoir<=work_data;count<=work_count;
        end
    end
endmodule
`default_nettype wire
