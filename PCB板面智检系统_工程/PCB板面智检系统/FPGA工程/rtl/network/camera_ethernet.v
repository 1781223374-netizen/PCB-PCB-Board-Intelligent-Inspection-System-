`timescale 1ns/1ps
module camera_ethernet #(parameter WIDTH=1920,HEIGHT=1080,BOOT_CYCLES=12500000,BOOT_DEBOUNCE=250000)(
 input wire ddr_clk,stream_rst_n,
 input wire [1:0] boot_select_n,output wire [1:0] device_id,output wire profile_done,
 output wire servo_pwm,
 input wire focus_lock,
 input wire lift_apply,input wire [15:0] lift_target,
 output wire lift_control_ready,output wire [15:0] lift_applied,
 output wire lift_enabled,
 output wire [12:0] net_cmd,output wire net_cmd_valid,input wire net_cmd_ready,
 input wire [129:0] net_response,input wire net_response_valid,output wire net_response_ready,
 input wire I_sys_clk, output wire O_phy_rst,
 input wire pll_locked,clk_125,clk_125_90,clk_25,
 input wire [3:0] I_a_rgmii_rxd, input wire I_a_rgmii_rx_ctl,I_a_rgmii_rxc,
 output wire [3:0] O_a_rgmii_txd, output wire O_a_rgmii_tx_ctl,O_a_rgmii_txc);
 wire profile_ready;wire phy_rst;
 scam_boot_profile #(.BOOT_CYCLES(BOOT_CYCLES),.DEBOUNCE_CYCLES(BOOT_DEBOUNCE)) u_profile(clk_25,pll_locked,boot_select_n,device_id,profile_done,profile_ready);
 (* async_reg="true" *) reg [1:0] identity_meta,identity_sync;
 (* async_reg="true" *) reg [3:0] profile_release;
 always @(posedge clk_125 or negedge pll_locked)
  if(!pll_locked)begin identity_meta<=0;identity_sync<=0;profile_release<=0;end
  else begin identity_meta<=device_id;identity_sync<=identity_meta;profile_release<={profile_release[2:0],profile_ready};end
 wire [31:0] local_ip=32'hc0a88901+{30'd0,identity_sync};
 wire [47:0] local_mac=48'h0223456789aa+{46'd0,identity_sync};
 wire [15:0] destination_port=16'd16000+{14'd0,identity_sync};
 assign O_phy_rst=phy_rst && profile_ready;
 wire reset=~phy_rst || !profile_release[3];
 uiphyrst #(.CLK_FREQ(25000000)) uiphyrst_inst(.I_CLK(clk_25),
 .I_rstn(pll_locked && profile_ready),.I_phyrst(pll_locked && profile_ready),.O_phyrst(phy_rst));
 wire W_udp_busy,W_udp_req,W_udp_valid,R_udp_valid;
 wire [7:0] W_udp_data,R_udp_data,gmii_tdata,gmii_rdata;
 wire [15:0] W_udp_len,R_udp_len,R_udp_src_port;
 wire gmii_rclk,gmii_rvalid,gmii_tvalid,ip_rx_error,mac_rx_error;
 wire [12:0] cmd;wire cmd_valid,cmd_ready;
 wire [129:0] resp;wire resp_valid,resp_ready;
 // Stream FIFOs and sender share the framebuffer reset, not the PHY reset.
 // A link stall can pin one bank but cannot stop HDMI or consume its cache.
 wire [12:0] cmd_fifo_data;wire cmd_fifo_valid,cmd_fifo_ready;
 ddr_async_fifo #(.WIDTH(13),.AW(3)) net_commands(clk_125,ddr_clk,stream_rst_n,
   cmd_valid,cmd,cmd_ready,cmd_fifo_valid,cmd_fifo_data,cmd_fifo_ready);
 ddr_elastic_buffer #(.WIDTH(13)) net_commands_stage(ddr_clk,stream_rst_n,
   cmd_fifo_data,cmd_fifo_valid,cmd_fifo_ready,net_cmd,net_cmd_valid,net_cmd_ready);
 ddr_async_fifo #(.WIDTH(130),.AW(8)) net_responses(ddr_clk,clk_125,stream_rst_n,
   net_response_valid,net_response,net_response_ready,resp_valid,resp,resp_ready);
 wire [7:0] requested_fps;
 wire image_req,image_valid,image_busy;
 wire [7:0] image_data;wire [15:0] image_len;
 wire [255:0] servo_reply;wire servo_reply_valid,servo_reply_take;
 wire control_rst_n=pll_locked && profile_release[3];
 assign lift_control_ready=control_rst_n;
 (* async_reg="true" *) reg [1:0] focus_lock_sync;
 always @(posedge clk_125 or negedge control_rst_n)
  if(!control_rst_n)focus_lock_sync<=0;else focus_lock_sync<={focus_lock_sync[0],focus_lock};
 servo_control u_servo(.clk(clk_125),.rst_n(control_rst_n),.device_id(identity_sync),
  .rx_valid(R_udp_valid),.rx_data(R_udp_data),.rx_len(R_udp_len),.pwm(servo_pwm),
  .reply(servo_reply),.reply_valid(servo_reply_valid),.reply_take(servo_reply_take),
  .local_lock(focus_lock_sync[1]),.local_apply(lift_apply),.local_target(lift_target),.applied_us(lift_applied),.target_us(),.pwm_enabled(lift_enabled),.local_control());
 scam_servo_arbiter u_tx_arbiter(.clk(clk_125),.rst_n(control_rst_n),.link_ready(phy_rst && profile_release[3]),
  .image_req(image_req),.image_valid(image_valid),.image_data(image_data),.image_len(image_len),.image_busy(image_busy),
  .status_packet(servo_reply),.status_valid(servo_reply_valid),.status_take(servo_reply_take),
  .udp_busy(W_udp_busy),.udp_req(W_udp_req),.udp_valid(W_udp_valid),.udp_data(W_udp_data),.udp_len(W_udp_len));
 scam_rate_control u_rate(.clk(clk_125),.rst_n(stream_rst_n),.rx_valid(R_udp_valid),
   .rx_data(R_udp_data),.rx_len(R_udp_len),.requested_fps(requested_fps));
 scam_camera_sender #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_sender(.clk(clk_125),.rst_n(stream_rst_n),.link_ready(phy_rst && profile_release[3]),.udp_busy(image_busy),
 .requested_fps(requested_fps),
 .cmd(cmd),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.response(resp),.response_valid(resp_valid),.response_ready(resp_ready),
 .udp_req(image_req),.udp_valid(image_valid),.udp_data(image_data),.udp_len(image_len));
uiudp_stack #
(	
.CRC_GEN_EN         	(1'b1),				//使能MAC层CRC校验
.INTER_FRAME_GAP    	(4'd12)				//插入帧间隔，2帧之间最少需要IFGmini=96bit/speed,比如1000M 96ns 100M 960ns 10M 9600ns，对于1000M 125M发送时钟，为12
)
udp_stack_inst
(
.I_uclk					(clk_125		), 
.I_reset				(reset			), 

.I_mac_local_addr  		(local_mac),//本地MAC地址	
.I_udp_local_port     	(16'd6002		), //本地端口号
.I_ip_local_addr   		(local_ip), //本地ip地址

.I_udp_dest_port		(destination_port), //目的端口
.I_ip_dest_addr	   		(32'hc0a88901	), //目的IP地址

.O_W_udp_busy			(W_udp_busy		), //udp写忙
.I_W_udp_req		   	(W_udp_req		), //udp写数据请求
.I_W_udp_valid 	   		(W_udp_valid	), //udp写数据有效
.I_W_udp_data			(W_udp_data		), //udp写数据
.I_W_udp_len	      	(W_udp_len		), //udp写数据长度

.O_R_udp_valid	      	(R_udp_valid	), //udp读数据有效
.O_R_udp_data			(R_udp_data		), //udp读数据
.O_R_udp_len 			(R_udp_len		), //udp读数据长度
.O_R_udp_src_port		(R_udp_src_port	), //udp读数据的远端主机端口号

.I_gmii_rclk           	(gmii_rclk		), //mac层接收GMII时钟
.I_gmii_rvalid	      	(gmii_rvalid	), //mac层接收GMII数据有效
.I_gmii_rdata			(gmii_rdata		), //mac层接收GMII数据

.I_gmii_tclk         	(clk_125		), //mac层发送GMII时钟
.O_gmii_tvalid	    	(gmii_tvalid	), //mac层发送GMII数据有效
.O_gmii_tdata			(gmii_tdata		), //mac层发送GMII数据有
.O_ip_rerror			(ip_rx_error	), //接收数据IP层数据校验错误
.O_mac_rerror			(mac_rx_error	)  //接收数据MAC层数据校验错误
);


rgmii_interface rgmii_interface_inst(

.speed_10_100	(1'b0				),   // 指示当前运行速度为10/100 或者1000
.gmii_tx_clk_d	(clk_125			),   //RGMII发送时序调整，当PHY 接收来自FPGA的TX信号，没有使用内部2ns延迟情况需要在fpga端设置2ns延迟 
.gmii_tx_reset_d(reset				),  
.gmii_tx_reset	(reset				),
.gmii_tx_clk	(clk_125			),     
.gmii_txd		(gmii_tdata			),
.gmii_tx_en		(gmii_tvalid		),
.gmii_tx_er		(					),

.gmii_rx_reset	(reset				),
.gmii_rx_clk	(gmii_rclk			),    //output： 125mhz（1gbps） 25mhz(100mbps)    2.5mhz(10mbps)
.gmii_rxd		(gmii_rdata			),
.gmii_rx_dv		(gmii_rvalid		),
.gmii_rx_er		(					),

// 以下端口是RGMII物理接口：这些端口将位于FPGA的引脚上
.rgmii_txd		(O_a_rgmii_txd		),
.rgmii_tx_ctl	(O_a_rgmii_tx_ctl	),
.rgmii_txc		(O_a_rgmii_txc		),

.rgmii_rxd		(I_a_rgmii_rxd		),
.rgmii_rx_ctl	(I_a_rgmii_rx_ctl	),
.rgmii_rxc		(I_a_rgmii_rxc		),
.gmii_crs		(					),
.gmii_col		(					),
// 以下信号为RGMII状态信号
.link_status	(					),
.clock_speed	(					),
.duplex_status	(					)
);




endmodule
