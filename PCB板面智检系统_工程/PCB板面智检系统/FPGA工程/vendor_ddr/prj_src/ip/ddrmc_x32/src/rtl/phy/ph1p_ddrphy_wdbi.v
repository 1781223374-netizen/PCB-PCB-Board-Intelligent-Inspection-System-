
`timescale 1ps/1ps
module ph1p_ddrphy_wdbi #(
    parameter DX_NUM = 8,
    parameter WDBI   = 1
)(
    input   [DX_NUM*8*8 - 1 : 0]  wrdata_in   , // per_byte
    input   [DX_NUM*8   - 1 : 0]  wrdata_mask ,
    output  [DX_NUM*8   - 1 : 0]  wrdata_dbi  ,
    output  [DX_NUM*8*8 - 1 : 0]  wrdata_out
);

wire  [DX_NUM*8   - 1 : 0]  wrdata_dbi_tmp;
wire  [DX_NUM*8*8 - 1 : 0]  wrdata_out_tmp;

wire  [DX_NUM*8*4 - 1 : 0]  high_level_num;

genvar n, p;

generate
    for (n = 0; n <= DX_NUM - 1; n = n+1) begin : encode_nIdx
        for (p = 0; p <= 7; p = p+1) begin : encode_pIdx
            assign high_level_num[(p*(DX_NUM*4) + 4*n) +: 4] = {3'b0,wrdata_in[(p*(DX_NUM*8) + n*8) + 0]} +
                                                               {3'b0,wrdata_in[(p*(DX_NUM*8) + n*8) + 1]} +
                                                               {3'b0,wrdata_in[(p*(DX_NUM*8) + n*8) + 2]} +
                                                               {3'b0,wrdata_in[(p*(DX_NUM*8) + n*8) + 3]} +
                                                               {3'b0,wrdata_in[(p*(DX_NUM*8) + n*8) + 4]} +
                                                               {3'b0,wrdata_in[(p*(DX_NUM*8) + n*8) + 5]} +
                                                               {3'b0,wrdata_in[(p*(DX_NUM*8) + n*8) + 6]} +
                                                               {3'b0,wrdata_in[(p*(DX_NUM*8) + n*8) + 7]} ;
            
            assign wrdata_dbi_tmp[(p*(DX_NUM*1) + n*1)] = {high_level_num[(p*(DX_NUM*4) + 4*n) +: 4] >= 4'h4} ? 1'b1 : 1'b0;
            
            assign wrdata_out_tmp[(p*(DX_NUM*8) + n*8) +: 8] = (wrdata_dbi_tmp[(p*(DX_NUM*1) + n*1)] == 1'b1) ?  wrdata_in[(p*(DX_NUM*8) + n*8) +: 8]
                                                                                                              : ~wrdata_in[(p*(DX_NUM*8) + n*8) +: 8];
        end
    end
endgenerate

  assign wrdata_dbi = (WDBI == 1) ? wrdata_dbi_tmp : wrdata_mask;
  assign wrdata_out = (WDBI == 1) ? wrdata_out_tmp : wrdata_in  ;

endmodule
