
///////////////////////////////////////////////////////////////////////////////////////////////////
// module : ph1p_ddrphy_cal_wrapper
///////////////////////////////////////////////////////////////////////////////////////////////////
`ifndef PH1P_MIS_SIM
`define MC0_DDRPHY_CAL_WRLVL
`define MC0_DDRPHY_CAL_GATE
//`define MC0_DDRPHY_CAL_RDEYE
//`define MC0_DDRPHY_CAL_WREYE
`endif

`timescale 1ps/1ps
module  ph1p_ddrphy_cal_wrapper #(
    parameter DX_NUM     = 2
)(
    input                       clk          ,
    input                       rst_n        ,

    input      [DX_NUM *9-1:0]  ui           ,

    input                       start        ,
    output reg                  done         ,
    output                      err          ,

    output     [DX_NUM* 9-1:0]  dcp_code     ,
    output     [DX_NUM* 4-1:0]  dcp_type     ,
    output     [DX_NUM   -1:0]  dcp_vld      ,
    output     [DX_NUM   -1:0]  dcp_inc      ,
    input      [DX_NUM   -1:0]  dcp_rdy      ,

    input      [DX_NUM* 9-1:0]  dly_cur_wdq  ,
    input      [DX_NUM* 9-1:0]  dly_cur_wdqs ,
    input      [DX_NUM* 9-1:0]  dly_cur_gate ,
    input      [DX_NUM* 9-1:0]  dly_cur_rdqs ,

    input      [DX_NUM* 4-1:0]  cur_wsl      ,
    input      [DX_NUM* 4-1:0]  cur_rsl      ,
    output     [DX_NUM* 4-1:0]  cal_wsl      ,
    output     [DX_NUM* 4-1:0]  cal_rsl      ,

    output                      cmd_vld      ,
    output     [         31:0]  cmd_code     ,

    input                       wdata_en     ,
    output     [DX_NUM*64-1:0]  wdata        ,
    output     [DX_NUM* 8-1:0]  wmask        ,
    input      [DX_NUM   -1:0]  rdata_vld    ,
    input      [DX_NUM*64-1:0]  rdata        ,

    output                      fifo_rst_n   ,
    output                      dqs_pupd_en  ,

    // from ddrphy
    output                      wrlvl_en     ,
    input      [DX_NUM   -1:0]  wrlvl_din    ,
    input      [DX_NUM* 2-1:0]  gate_status  ,

    input      [         12:0]  init_mr1     ,

    // APB
    input                       apb_pclk     ,
    input                       apb_prst_n   ,
    input                       apb_psel     ,
    input                       apb_penable  ,
    input                       apb_pwrite   ,
    input      [         15:0]  apb_paddr    ,
    input      [         31:0]  apb_pwdata   ,
    output reg                  apb_pready   ,
    output reg [         31:0]  apb_prdata   ,

    // Debug
    output     [          7:0]  dbg_cal_step ,
    output     [          7:0]  dbg_cal_done ,
    output     [          7:0]  dbg_cal_err
);

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
wire  wrlvl_start;
wire  wrlvl_done ;
wire  wrlvl_err  ;

wire  gate_start ;
wire  gate_done  ;
wire  gate_err   ;

wire  wla_start  ;
wire  wla_done   ;
wire  wla_err    ;

wire  rdeye_start;
wire  rdeye_done ;
wire  rdeye_err  ;

wire  wreye_start;
wire  wreye_done ;
wire  wreye_err  ;

wire         wrlvl_cmd_vld;
wire  [31:0] wrlvl_cmd_code;

wire         gate_cmd_vld;
wire  [31:0] gate_cmd_code;

wire         wla_cmd_vld;
wire  [31:0] wla_cmd_code;

wire         rdeye_cmd_vld;
wire  [31:0] rdeye_cmd_code;

wire         wreye_cmd_vld;
wire  [31:0] wreye_cmd_code;

wire  [DX_NUM*9-1:0]  wrlvl_dcp_code;
wire  [DX_NUM*4-1:0]  wrlvl_dcp_type;
wire  [DX_NUM  -1:0]  wrlvl_dcp_vld ;
wire  [DX_NUM  -1:0]  wrlvl_dcp_inc ;
wire  [DX_NUM  -1:0]  wrlvl_dcp_rdy ;

wire  [DX_NUM*9-1:0]  gate_dcp_code;
wire  [DX_NUM*4-1:0]  gate_dcp_type;
wire  [DX_NUM  -1:0]  gate_dcp_vld ;
wire  [DX_NUM  -1:0]  gate_dcp_inc ;
wire  [DX_NUM  -1:0]  gate_dcp_rdy ;

wire  [DX_NUM*9-1:0]  wla_dcp_code;
wire  [DX_NUM*4-1:0]  wla_dcp_type;
wire  [DX_NUM  -1:0]  wla_dcp_vld ;
wire  [DX_NUM  -1:0]  wla_dcp_inc ;
wire  [DX_NUM  -1:0]  wla_dcp_rdy ;

wire  [DX_NUM*9-1:0]  rdeye_dcp_code;
wire  [DX_NUM*4-1:0]  rdeye_dcp_type;
wire  [DX_NUM  -1:0]  rdeye_dcp_vld ;
wire  [DX_NUM  -1:0]  rdeye_dcp_inc ;
wire  [DX_NUM  -1:0]  rdeye_dcp_rdy ;

wire  [DX_NUM*9-1:0]  wreye_dcp_code;
wire  [DX_NUM*4-1:0]  wreye_dcp_type;
wire  [DX_NUM  -1:0]  wreye_dcp_vld ;
wire  [DX_NUM  -1:0]  wreye_dcp_inc ;
wire  [DX_NUM  -1:0]  wreye_dcp_rdy ;

wire  [DX_NUM*4-1:0]  wrlvl_wsl_o ;
wire  [DX_NUM*4-1:0]  wla_wsl_o   ;
wire  [DX_NUM*4-1:0]  gate_rsl    ;

wire                  wla_wdata_en ;
wire [DX_NUM*64-1:0]  wla_wdata    ;
wire [DX_NUM* 8-1:0]  wla_wmask    ;
wire [DX_NUM   -1:0]  wla_rdata_vld;
wire [DX_NUM*64-1:0]  wla_rdata    ;

wire                  wreye_wdata_en ;
wire [DX_NUM*64-1:0]  wreye_wdata    ;
wire [DX_NUM* 8-1:0]  wreye_wmask    ;
wire                  wreye_rdata_vld;
wire [DX_NUM*64-1:0]  wreye_rdata    ;

wire                  rdeye_rdata_vld ;
wire [DX_NUM*64-1:0]  rdeye_rdata     ;

wire                  gate_fifo_rst_n ;
wire                  rdeye_fifo_rst_n;

wire  [4:0] cal_done = {wreye_done, wla_done, rdeye_done, gate_done, wrlvl_done};

wire  [DX_NUM*64-1:0]  dbg_rdata_x0;
wire  [DX_NUM*64-1:0]  dbg_rdata_x1;
wire  [DX_NUM*64-1:0]  dbg_rdata_x2;
wire  [DX_NUM*64-1:0]  dbg_rdata_x3;
wire  [DX_NUM*64-1:0]  dbg_rdata_word;

wire  [DX_NUM*9 -1:0]  dbg_lbd_rdqsd;
wire  [DX_NUM*9 -1:0]  dbg_hbd_rdqsd;

wire  [DX_NUM*9 -1:0]  dbg_lbd_wdqd;
wire  [DX_NUM*9 -1:0]  dbg_hbd_wdqd;

///////////////////////////////////////////////////////////////////////////////////////////////////
//  DCP MUX
///////////////////////////////////////////////////////////////////////////////////////////////////
assign dcp_code = (cal_done == 5'b00000) ? wrlvl_dcp_code : (cal_done == 5'b00001) ? gate_dcp_code : (cal_done == 5'b00011) ? rdeye_dcp_code : (cal_done == 5'b00111) ? wla_dcp_code : (cal_done == 5'b01111) ? wreye_dcp_code : {(DX_NUM*9){1'b0}};
assign dcp_type = (cal_done == 5'b00000) ? wrlvl_dcp_type : (cal_done == 5'b00001) ? gate_dcp_type : (cal_done == 5'b00011) ? rdeye_dcp_type : (cal_done == 5'b00111) ? wla_dcp_type : (cal_done == 5'b01111) ? wreye_dcp_type : {(DX_NUM*4){1'b0}};
assign dcp_vld  = (cal_done == 5'b00000) ? wrlvl_dcp_vld  : (cal_done == 5'b00001) ? gate_dcp_vld  : (cal_done == 5'b00011) ? rdeye_dcp_vld  : (cal_done == 5'b00111) ? wla_dcp_vld  : (cal_done == 5'b01111) ? wreye_dcp_vld  : {(DX_NUM*1){1'b0}};
assign dcp_inc  = (cal_done == 5'b00000) ? wrlvl_dcp_inc  : (cal_done == 5'b00001) ? gate_dcp_inc  : (cal_done == 5'b00011) ? rdeye_dcp_inc  : (cal_done == 5'b00111) ? wla_dcp_inc  : (cal_done == 5'b01111) ? wreye_dcp_inc  : {(DX_NUM*1){1'b0}};

assign cal_wsl  = (cal_done == 5'b00000) ? wrlvl_wsl_o    : (cal_done == 5'b00111) ? wla_wsl_o     : {(DX_NUM*4){1'b0}};
assign cal_rsl  = gate_rsl;

assign wrlvl_dcp_rdy = dcp_rdy ;
assign  gate_dcp_rdy = dcp_rdy ;
assign rdeye_dcp_rdy = dcp_rdy ;
assign   wla_dcp_rdy = dcp_rdy ;
assign wreye_dcp_rdy = dcp_rdy ;

///////////////////////////////////////////////////////////////////////////////////////////////////
//  DHI MUX
///////////////////////////////////////////////////////////////////////////////////////////////////
assign cmd_vld  = (cal_done == 5'b00000) ? wrlvl_cmd_vld  : (cal_done == 5'b00001) ? gate_cmd_vld  : (cal_done == 5'b00011) ? rdeye_cmd_vld  : (cal_done == 5'b00111) ? wla_cmd_vld  : (cal_done == 5'b01111) ? wreye_cmd_vld  : 1'b0;
assign cmd_code = (cal_done == 5'b00000) ? wrlvl_cmd_code : (cal_done == 5'b00001) ? gate_cmd_code : (cal_done == 5'b00011) ? rdeye_cmd_code : (cal_done == 5'b00111) ? wla_cmd_code : (cal_done == 5'b01111) ? wreye_cmd_code : 32'h0;

assign wdata    = (cal_done == 5'b00111) ? wla_wdata : (cal_done == 5'b01111) ? wreye_wdata : {(DX_NUM*64){1'b0}};
assign wmask    = (cal_done == 5'b00111) ? wla_wmask : (cal_done == 5'b01111) ? wreye_wmask : {(DX_NUM* 8){1'b0}};

assign wla_wdata_en    = wla_start && (wla_done == 1'b0) ? wdata_en  : 1'b0;
assign wla_rdata_vld   = wla_start && (wla_done == 1'b0) ? rdata_vld : {(DX_NUM   ){1'b0}};
assign wla_rdata       = wla_start && (wla_done == 1'b0) ? rdata     : {(DX_NUM*64){1'b0}};

assign wreye_wdata_en  = wreye_start && (wreye_done == 1'b0) ? wdata_en  : 1'b0;
assign wreye_rdata_vld = wreye_start && (wreye_done == 1'b0) ? rdata_vld : {(DX_NUM   ){1'b0}};
assign wreye_rdata     = wreye_start && (wreye_done == 1'b0) ? rdata     : {(DX_NUM*64){1'b0}};

assign rdeye_rdata_vld = rdeye_start && (rdeye_done == 1'b0) ? rdata_vld : {(DX_NUM   ){1'b0}};
assign rdeye_rdata     = rdeye_start && (rdeye_done == 1'b0) ? rdata     : {(DX_NUM*64){1'b0}};

assign fifo_rst_n  = gate_fifo_rst_n & rdeye_fifo_rst_n;

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Write Leveling
///////////////////////////////////////////////////////////////////////////////////////////////////
`ifdef MC0_DDRPHY_CAL_WRLVL
ph1p_ddrphy_cal_wrlvl_wrapper #(
    .DX_NUM    ( DX_NUM )
) u_ddrphy_cal_wrlvl (
    .clk       ( clk            ),
    .rst_n     ( rst_n          ),
    .ui        ( ui             ),
    .start     ( wrlvl_start    ),
    .done      ( wrlvl_done     ),
    .err       ( wrlvl_err      ),

    .dcp_code  ( wrlvl_dcp_code ),
    .dcp_type  ( wrlvl_dcp_type ),
    .dcp_vld   ( wrlvl_dcp_vld  ),
    .dcp_inc   ( wrlvl_dcp_inc  ),
    .dcp_rdy   ( wrlvl_dcp_rdy  ),
    .dly_cur   ( dly_cur_wdqs   ),

    .cur_wsl   ( cur_wsl        ),
    .wsl_o     ( wrlvl_wsl_o    ),

    .cmd_vld   ( wrlvl_cmd_vld  ),
    .cmd_code  ( wrlvl_cmd_code ),

    .wrlvl_en  ( wrlvl_en       ),
    .wrlvl_din ( wrlvl_din      ),
    .mr1_set   ( init_mr1       )
);

assign wrlvl_start = start;
`else
assign wrlvl_en    = 1'b0;
assign wrlvl_done  = start;
assign wrlvl_err   = 1'b0;
assign wrlvl_wsl_o = {DX_NUM{4'h2}};

assign wrlvl_dcp_inc  = {DX_NUM{1'b0}};
assign wrlvl_dcp_vld  = {DX_NUM{1'b0}};
assign wrlvl_dcp_type = {DX_NUM{4'h0}};
assign wrlvl_dcp_code = {DX_NUM{9'h0}};

assign wrlvl_cmd_vld  = 1'b0;
assign wrlvl_cmd_code = 32'h0;

`endif

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Gate Leveling
///////////////////////////////////////////////////////////////////////////////////////////////////
`ifdef MC0_DDRPHY_CAL_GATE
ph1p_ddrphy_cal_gate_wrapper #(
    .DX_NUM      ( DX_NUM )
) u_ddrphy_cal_gate (
    .clk         ( clk             ),
    .rst_n       ( rst_n           ),
    .ui          ( ui              ),
    .start       ( gate_start      ),
    .done        ( gate_done       ),
    .err         ( gate_err        ),

    .dcp_code    ( gate_dcp_code   ),
    .dcp_type    ( gate_dcp_type   ),
    .dcp_vld     ( gate_dcp_vld    ),
    .dcp_inc     ( gate_dcp_inc    ),
    .dcp_rdy     ( gate_dcp_rdy    ),
    .dly_cur     ( dly_cur_gate    ),

    .cur_rsl     ( cur_rsl         ),
    .rsl_o       ( gate_rsl        ),

    .cmd_vld     ( gate_cmd_vld    ),
    .cmd_code    ( gate_cmd_code   ),

//  .fifo_rst_n  ( gate_fifo_rst_n ),
    .dqs_pupd_en ( dqs_pupd_en     ),
    .gate_status ( gate_status     )
);

assign gate_start = wrlvl_done;
`else
assign gate_done  = wrlvl_done;
assign gate_err   = 1'b0;

assign gate_dcp_inc  = {DX_NUM{1'b0}};
assign gate_dcp_vld  = {DX_NUM{1'b0}};
assign gate_dcp_type = {DX_NUM{4'h0}};
assign gate_dcp_code = {DX_NUM{9'h0}};

assign gate_cmd_vld  = 1'b0;
assign gate_cmd_code = 32'h0;

assign gate_rsl      = {DX_NUM{4'h3}};
assign dqs_pupd_en   = 1'b0;

`endif

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Reset After RDQS Gate Leveling
///////////////////////////////////////////////////////////////////////////////////////////////////
reg [3:0] gate_done_cnt;
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        gate_done_cnt <= 4'h0;
    else if (gate_done)
        gate_done_cnt <= (gate_done_cnt == 4'hf) ? 4'hf : gate_done_cnt + 1'b1;
end

assign gate_fifo_rst_n = gate_done ? (gate_done_cnt == 4'hf) : 1'b1;

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Read Eye
///////////////////////////////////////////////////////////////////////////////////////////////////

`ifdef MC0_DDRPHY_CAL_RDEYE
assign rdeye_start = gate_fifo_rst_n && gate_done && (gate_err == 1'b0);

ph1p_ddrphy_cal_rdeye_wrapper #(
    .DX_NUM      ( DX_NUM )
) u_ddrphy_cal_rdeye (
    .clk           ( clk              ),
    .rst_n         ( rst_n            ),
    .ui            ( ui               ),
    .start         ( rdeye_start      ),
    .done          ( rdeye_done       ),
    .err           ( rdeye_err        ),

    .dcp_code      ( rdeye_dcp_code   ),
    .dcp_type      ( rdeye_dcp_type   ),
    .dcp_vld       ( rdeye_dcp_vld    ),
    .dcp_inc       ( rdeye_dcp_inc    ),
    .dcp_rdy       ( rdeye_dcp_rdy    ),
    .dly_cur_gate  ( dly_cur_gate     ),
    .dly_cur_rdqs  ( dly_cur_rdqs     ),

    .cmd_vld       ( rdeye_cmd_vld    ),
    .cmd_code      ( rdeye_cmd_code   ),

    .fifo_rst_n    ( rdeye_fifo_rst_n ),

    .rdata_vld     ( rdeye_rdata_vld  ),
    .rdata         ( rdeye_rdata      ),

    .dbg_lbd_rdqsd ( dbg_lbd_rdqsd    ),
    .dbg_hbd_rdqsd ( dbg_hbd_rdqsd    )
);
`else
assign rdeye_done = gate_done && (gate_err == 1'b0);
assign rdeye_err  = 1'b0;

assign rdeye_dcp_code = {DX_NUM{9'b0}};
assign rdeye_dcp_type = {DX_NUM{4'b0}};
assign rdeye_dcp_vld  = {DX_NUM{1'b0}};
assign rdeye_dcp_inc  = {DX_NUM{1'b0}};

assign rdeye_cmd_vld  = 1'b0 ;
assign rdeye_cmd_code = 32'b0;

assign rdeye_fifo_rst_n = 1'b1;

assign dbg_lbd_rdqsd = {DX_NUM{9'b0}};
assign dbg_hbd_rdqsd = {DX_NUM{9'b0}};
`endif
///////////////////////////////////////////////////////////////////////////////////////////////////
//  Write Latency Adjust
///////////////////////////////////////////////////////////////////////////////////////////////////
`ifdef MC0_DDRPHY_CAL_WRLVL
assign wla_start = rdeye_done && (rdeye_err == 1'b0);

ph1p_ddrphy_cal_wla_wrapper #(
    .DX_NUM      ( DX_NUM )
) u_ddrphy_cal_wla (
    .clk          ( clk           ),
    .rst_n        ( rst_n         ),

    .start        ( wla_start     ),
    .done         ( wla_done      ),
    .err          ( wla_err       ),

    .dcp_code     ( wla_dcp_code  ),
    .dcp_type     ( wla_dcp_type  ),
    .dcp_vld      ( wla_dcp_vld   ),
    .dcp_inc      ( wla_dcp_inc   ),
    .dcp_rdy      ( wla_dcp_rdy   ),
    .dly_cur      ( dly_cur_wdqs  ),

    .cur_wsl      ( cur_wsl       ),
    .wsl_o        ( wla_wsl_o     ),

    .cmd_vld      ( wla_cmd_vld   ),
    .cmd_code     ( wla_cmd_code  ),

    .wdata_en     ( wla_wdata_en  ),
    .wdata        ( wla_wdata     ),
    .wmask        ( wla_wmask     ),
    .rdata_vld    ( wla_rdata_vld ),
    .rdata        ( wla_rdata     ),

    .dbg_rdata_x0 ( dbg_rdata_x0  ),
    .dbg_rdata_x1 ( dbg_rdata_x1  ),
    .dbg_rdata_x2 ( dbg_rdata_x2  ),
    .dbg_rdata_x3 ( dbg_rdata_x3  )
);
`else
assign wla_done  = rdeye_done && (rdeye_err == 1'b0);
assign wla_err   = 1'b0;

assign wla_wsl_o    = {DX_NUM{4'h2}};

assign wla_dcp_inc  = {DX_NUM{1'b0}};
assign wla_dcp_vld  = {DX_NUM{1'b0}};
assign wla_dcp_type = {DX_NUM{4'h0}};
assign wla_dcp_code = {DX_NUM{9'h0}};

assign wla_cmd_vld  = 1'b0;
assign wla_cmd_code = 32'h0;

assign wla_wdata    = {DX_NUM{64'h0}};
assign wla_wmask    = {DX_NUM{ 8'h0}};

`endif


///////////////////////////////////////////////////////////////////////////////////////////////////
//  Write Eye
///////////////////////////////////////////////////////////////////////////////////////////////////
`ifdef MC0_DDRPHY_CAL_WREYE
assign wreye_start = wla_done && (wla_err == 1'b0);

ph1p_ddrphy_cal_wreye_wrapper #(
    .DX_NUM      ( DX_NUM )
) u_ddrphy_cal_wreye (
    .clk           ( clk             ),
    .rst_n         ( rst_n           ),

    .ui            ( ui              ),

    .start         ( wreye_start     ),
    .done          ( wreye_done      ),
    .err           ( wreye_err       ),

    .dcp_code      ( wreye_dcp_code  ),
    .dcp_type      ( wreye_dcp_type  ),
    .dcp_vld       ( wreye_dcp_vld   ),
    .dcp_inc       ( wreye_dcp_inc   ),
    .dcp_rdy       ( wreye_dcp_rdy   ),
    .dly_cur_wdq   ( dly_cur_wdq     ),

    .cmd_vld       ( wreye_cmd_vld   ),
    .cmd_code      ( wreye_cmd_code  ),

    .wdata_en      ( wreye_wdata_en  ),
    .wdata         ( wreye_wdata     ),
    .wmask         ( wreye_wmask     ),
    .rdata_vld     ( wreye_rdata_vld ),
    .rdata         ( wreye_rdata     ),

    .dbg_lbd_wdqd  ( dbg_lbd_wdqd    ),
    .dbg_hbd_wdqd  ( dbg_hbd_wdqd    )
);
`else
assign wreye_done = wla_done && (wla_err == 1'b0);
assign wreye_err  = 1'b0;

assign wreye_dcp_code = {DX_NUM{9'b0}};
assign wreye_dcp_type = {DX_NUM{4'b0}};
assign wreye_dcp_vld  = {DX_NUM{1'b0}};
assign wreye_dcp_inc  = {DX_NUM{1'b0}};

assign wreye_cmd_vld  = 1'b0 ;
assign wreye_cmd_code = 32'b0;

assign wreye_wdata    = {DX_NUM{64'b0}};
assign wreye_wmask    = {DX_NUM{ 8'b0}};

assign dbg_lbd_wdqd   = {DX_NUM{9'b0}};
assign dbg_hbd_wdqd   = {DX_NUM{9'b0}};
`endif

///////////////////////////////////////////////////////////////////////////////////////////////////
//  MISC
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        done <= 1'b0;
    else
        done <= wreye_done && (wreye_err == 1'b0);
end

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Debug
///////////////////////////////////////////////////////////////////////////////////////////////////
// reg00: RO : ID
// reg04: RO : SR (err[7:0], done[7:0], step[7:0])
// reg08: RW : CR (bsel[3:0], nsel[3:0])
// reg0c: RW : RSVD0
// reg10: RO : WLA rdata_w0
// reg14: RO : WLA rdata_w1
// reg18: RO : RDEYE LBD/HBD
// reg1C: RO : WREYE LBD/HBD

reg  [31:0] reg00; // ro
reg  [31:0] reg04; // ro
reg  [31:0] reg08; // rw
reg  [31:0] reg0c; // rw
reg  [31:0] reg10; // ro
reg  [31:0] reg14; // ro
reg  [31:0] reg18; // ro
reg  [31:0] reg1c; // ro

wire [ 3:0] bsel = reg08[7:4];
wire [ 3:0] nsel = reg08[3:0];
wire [31:0] dbg_wla_rdata;

wire [ 8:0] rdly_bit_shift;

// apb timing control
wire apb_wr_en = apb_psel & apb_penable & (apb_pwrite == 1'b1) & apb_pready;
wire apb_rd_en = apb_psel & apb_penable & (apb_pwrite == 1'b0);

always @ (posedge apb_pclk or negedge apb_prst_n)
begin
    if (apb_prst_n == 1'b0)
        apb_pready <= 1'b0;
    else if (apb_psel & (apb_penable == 1'b0))
        apb_pready <= 1'b0;
    else if (apb_psel & apb_penable & (apb_pwrite == 1'b1))
        apb_pready <= 1'b1;
    else if (apb_psel & apb_penable & (apb_pwrite == 1'b0))
        apb_pready <= apb_rd_en;
    else
        apb_pready <= 1'b1;
end

// apb write
always @ (posedge apb_pclk or negedge apb_prst_n)
begin
    if (apb_prst_n == 1'b0) begin
        reg08 <= 32'h0;
    end else if (apb_wr_en) begin
        case (apb_paddr[7:0])
            8'h08  : reg08 <= apb_pwdata;
            default: begin
            end
        endcase
    end
end

// apb read
always @ (posedge apb_pclk or negedge apb_prst_n)
begin
    if (apb_prst_n == 1'b0) begin
        apb_prdata <= 32'h0;
    end else if (apb_rd_en) begin
        case (apb_paddr[7:0])
            8'h00  : apb_prdata <= reg00;
            8'h04  : apb_prdata <= reg04;
            8'h08  : apb_prdata <= reg08;
            8'h0c  : apb_prdata <= reg0c;
            8'h10  : apb_prdata <= reg10;
            8'h14  : apb_prdata <= reg14;
            8'h18  : apb_prdata <= reg18;
            8'h1c  : apb_prdata <= reg1c;
            default: apb_prdata <= 32'hdeadbeef;
        endcase
    end
end

always @ (posedge apb_pclk)
begin
    reg00 <= 32'h20251202;
    reg04 <= {8'h0, dbg_cal_err[7:0], dbg_cal_done[7:0], dbg_cal_step[7:0]};
    reg10 <= dbg_rdata_word[bsel*64+ 0+:32];
    reg14 <= dbg_rdata_word[bsel*64+32+:32];
    reg18 <= {7'h0, dbg_hbd_rdqsd[rdly_bit_shift +: 9], 7'h0, dbg_lbd_rdqsd[rdly_bit_shift +: 9]};
    reg1c <= {7'h0, dbg_hbd_wdqd [rdly_bit_shift +: 9], 7'h0, dbg_lbd_wdqd [rdly_bit_shift +: 9]};
end

assign dbg_cal_step[7:0] = {3'b0, wreye_start, wla_start, rdeye_start, gate_start, wrlvl_start};
assign dbg_cal_done[7:0] = {3'b0, wreye_done,  wla_done,  rdeye_done,  gate_done,  wrlvl_done };
assign dbg_cal_err [7:0] = {3'b0, wreye_err,   wla_err,   rdeye_err,   gate_err,   wrlvl_err  };

assign dbg_rdata_word = (nsel == 4'h0) ? dbg_rdata_x0 :
                        (nsel == 4'h1) ? dbg_rdata_x1 :
                        (nsel == 4'h2) ? dbg_rdata_x2 :
                        (nsel == 4'h3) ? dbg_rdata_x3 : {DX_NUM{64'h0}};

assign rdly_bit_shift = (bsel == 8'h0) ? 9*0 :
                        (bsel == 8'h1) ? 9*1 :
                        (bsel == 8'h2) ? 9*2 :
                        (bsel == 8'h3) ? 9*3 :
                        (bsel == 8'h4) ? 9*4 :
                        (bsel == 8'h5) ? 9*5 :
                        (bsel == 8'h6) ? 9*6 :
                        (bsel == 8'h7) ? 9*7 :
                        (bsel == 8'h8) ? 9*8 : 9'h0;

////////////////////////////////////////////////////////////////
// SIMULATION ONLY
////////////////////////////////////////////////////////////////
//synthesis translate_off
`ifdef PH1P_MIS_SIM
initial begin
    wait(wrlvl_start);
    $display("[DDRPPC_INFO] : Write Leveling Start!");
    wait(wrlvl_done);
    $display("[DDRPPC_INFO] : Write Leveling Done!");
end

initial begin
    wait(gate_start);
    $display("[DDRPPC_INFO] : RDQS Gate Leveling Start!");
    wait(gate_done);
    $display("[DDRPPC_INFO] : RDQS Gate Leveling Done!");
end

initial begin
    wait(rdeye_start);
    $display("[DDRPPC_INFO] : Read Eye Centering Start!");
    wait(rdeye_done);
    $display("[DDRPPC_INFO] : Read Eye Centering Done!");
end

initial begin
    wait(wla_start);
    $display("[DDRPPC_INFO] : Write Latency Adjustment Start!");
    wait(wla_done);
    $display("[DDRPPC_INFO] : Write Latency Adjustment Done!");
end

initial begin
    wait(wreye_start);
    $display("[DDRPPC_INFO] : Write Eye Centering Start!");
    wait(wreye_done);
    $display("[DDRPPC_INFO] : Write Eye Centering Done!");
end
`endif
//synthesis translate_on

endmodule
