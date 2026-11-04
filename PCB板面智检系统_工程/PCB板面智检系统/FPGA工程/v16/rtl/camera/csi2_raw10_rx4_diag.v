`timescale 1ns/1ps
`default_nettype none
// Contract: four deskewed bytes per clock, earliest byte in [7:0].
// One CSI packet per HS burst. No backpressure on the sensor.
module csi2_raw10_rx4_diag #(
    parameter VC = 0
)(
    input wire clk, rst_n,
    input wire hs_valid,
    input wire [31:0] hs_data,
    output reg frame_start, frame_end, frame_error,
    output reg line_start, line_end,
    output reg [15:0] line_bytes,
    output reg payload_valid,
    output reg [2:0] payload_bytes,
    output reg [31:0] payload_data,
    output reg [31:0] error_count,
    output reg [31:0] good_headers,bad_headers,bad_crc,truncated,raw_lines,fs_count,fe_count,last_header,
    output reg [15:0] last_wc,
    output reg [31:0] bad_raw_wc,
    output reg [15:0] last_bad_raw_wc
);
    localparam HEADER=0, DATA=1, DROP=2;
    reg [1:0] state;
    reg [15:0] remaining, crc;
    reg [1:0] crc_count;
    reg [15:0] rx_crc;
    reg raw_packet, own_packet;
    reg [15:0] wc_tmp, rem_tmp, crc_tmp, rx_tmp;
    reg [1:0] crc_n_tmp;
    reg [2:0] n_tmp;
    integer i;
    function [5:0] header_ecc;
        input [23:0] d;
        begin
            header_ecc[0]=d[0]^d[1]^d[2]^d[4]^d[5]^d[7]^d[10]^d[11]^d[13]^d[16]^d[20]^d[21]^d[22]^d[23];
            header_ecc[1]=d[0]^d[1]^d[3]^d[4]^d[6]^d[8]^d[10]^d[12]^d[14]^d[17]^d[20]^d[21]^d[22]^d[23];
            header_ecc[2]=d[0]^d[2]^d[3]^d[5]^d[6]^d[9]^d[11]^d[12]^d[15]^d[18]^d[20]^d[21]^d[22];
            header_ecc[3]=d[1]^d[2]^d[3]^d[7]^d[8]^d[9]^d[13]^d[14]^d[15]^d[19]^d[20]^d[21]^d[23];
            header_ecc[4]=d[4]^d[5]^d[6]^d[7]^d[8]^d[9]^d[16]^d[17]^d[18]^d[19]^d[20]^d[22]^d[23];
            header_ecc[5]=d[10]^d[11]^d[12]^d[13]^d[14]^d[15]^d[16]^d[17]^d[18]^d[19]^d[21]^d[22]^d[23];
        end
    endfunction
    function [15:0] crc_byte;
        input [15:0] c;
        input [7:0] b;
        reg [15:0] v;
        integer bit_index;
        begin
            v=c;
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)
                v=(v[0]^b[bit_index]) ? (v>>1)^16'h8408 : v>>1;
            crc_byte=v;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=HEADER;remaining<=0;crc<=16'hffff;crc_count<=0;rx_crc<=0;
            raw_packet<=0;own_packet<=0;frame_start<=0;frame_end<=0;frame_error<=0;
            line_start<=0;line_end<=0;line_bytes<=0;
            payload_valid<=0;payload_bytes<=0;payload_data<=0;error_count<=0;
            good_headers<=0;bad_headers<=0;bad_crc<=0;truncated<=0;raw_lines<=0;
            fs_count<=0;fe_count<=0;last_header<=0;last_wc<=0;bad_raw_wc<=0;last_bad_raw_wc<=0;
        end else begin
            frame_start<=0;frame_end<=0;line_start<=0;line_end<=0;
            payload_valid<=0;payload_bytes<=0;
            if(!hs_valid) begin
                if(state==DATA && own_packet) begin
                    truncated<=truncated+1'b1;
                    frame_error<=1;error_count<=error_count+1'b1;
                end
                state<=HEADER;
            end else case(state)
                HEADER: begin
                    last_header<=hs_data;last_wc<={hs_data[23:16],hs_data[15:8]};
                    wc_tmp={hs_data[23:16],hs_data[15:8]};
                    own_packet<=hs_data[7:6]==VC;
                    if(header_ecc(hs_data[23:0])!=hs_data[29:24] || hs_data[31:30]!=0) begin
                        bad_headers<=bad_headers+1'b1;frame_error<=1;error_count<=error_count+1'b1;state<=DROP;
                    end else if(hs_data[5:0]<=6'h0f) begin
                        good_headers<=good_headers+1'b1;state<=DROP;
                        if(hs_data[7:6]==VC) begin
                            if(hs_data[5:0]==0) begin frame_start<=1;frame_error<=0;fs_count<=fs_count+1'b1;end
                            if(hs_data[5:0]==1) begin frame_end<=1;fe_count<=fe_count+1'b1;end
                        end
                    end else begin
                        good_headers<=good_headers+1'b1;
                        raw_packet<=hs_data[5:0]==6'h2b && hs_data[7:6]==VC;
                        remaining<=wc_tmp;crc<=16'hffff;crc_count<=0;rx_crc<=0;state<=DATA;
                        if(hs_data[5:0]==6'h2b && hs_data[7:6]==VC) begin
                            if(wc_tmp==0 || wc_tmp%5!=0) begin
                                bad_raw_wc<=bad_raw_wc+1'b1;last_bad_raw_wc<=wc_tmp;
                                frame_error<=1;error_count<=error_count+1'b1;raw_packet<=0;
                            end else begin raw_lines<=raw_lines+1'b1;line_start<=1;line_bytes<=wc_tmp;end
                        end
                    end
                end
                DATA: begin
                    rem_tmp=remaining;crc_tmp=crc;rx_tmp=rx_crc;crc_n_tmp=crc_count;n_tmp=0;
                    for(i=0;i<4;i=i+1) begin
                        if(rem_tmp!=0) begin
                            crc_tmp=crc_byte(crc_tmp,hs_data[i*8+:8]);
                            rem_tmp=rem_tmp-1'b1;n_tmp=n_tmp+1'b1;
                        end else if(crc_n_tmp<2) begin
                            if(crc_n_tmp==0) rx_tmp[7:0]=hs_data[i*8+:8];
                            else rx_tmp[15:8]=hs_data[i*8+:8];
                            crc_n_tmp=crc_n_tmp+1'b1;
                        end
                    end
                    remaining<=rem_tmp;crc<=crc_tmp;rx_crc<=rx_tmp;crc_count<=crc_n_tmp;
                    if(raw_packet && n_tmp!=0) begin
                        payload_valid<=1;payload_bytes<=n_tmp;payload_data<=hs_data;
                    end
                    if(rem_tmp==0 && crc_n_tmp==2) begin
                        state<=DROP;
                        if(raw_packet) line_end<=1;
                        if(own_packet && rx_tmp!=crc_tmp) begin
                            bad_crc<=bad_crc+1'b1;
                            frame_error<=1;error_count<=error_count+1'b1;
                        end
                    end
                end
                default: state<=DROP;
            endcase
        end
    end
endmodule
`default_nettype wire
