//============================================================================
//  Arcade: Atari-Tetris for MiSTer
//
//						Written by MiSTer-X 2019
//============================================================================

`include "src/fourWay/controls_top.sv"

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output		  VGA_F1,

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1	  = 0;
assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : 8'd4;
assign HDMI_ARY = status[1] ? 8'd9  : 8'd3;

`include "build_id.v" 
localparam CONF_STR = {
	"A.ATetris;;",
	"F,rom;", // allow loading of alternate ROMs
	"-;",
	"H0O1,Aspect Ratio,Original,Wide;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"ODG,Diagonal,Default,Change Direction,Keep Direction,Vertical,Horizontal,Stop;",
	"OH,Self-Test,Off,On;",
	"-;",
	"O8C,Analog Video H-Pos,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31;",
	"OIK,Analog Video V-Pos,0,1,2,3,4,5,6,7;",
	"-;",
	"R0,Reset;",
	"J1,Rotate,Coin;",
	"V,v",`BUILD_DATE
};

wire [3:0] DG_MODE = status[16:13];

wire [4:0] HOFFS = status[12:8];
wire [2:0] VOFFS = status[20:18];

wire bSelfTest = status[17];


////////////////////   CLOCKS   ///////////////////

wire clk_hdmi;
wire clk_14M;
wire clk_sys = clk_hdmi;

pll pll
(
	.rst(0),
	.refclk(CLK_50M),
	.outclk_0(clk_14M),
	.outclk_1(clk_hdmi)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire			direct_video;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;
wire [15:0] joystk1, joystk2;

wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),

	.status(status),
	.status_menumask({15'h0,direct_video}),

	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	
	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.joystick_0(joystk1),
	.joystick_1(joystk2),
	.ps2_key(ps2_key)
);

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right
			'h029: btn_trig1       <= pressed; // space
			'h014: btn_trig2       <= pressed; // ctrl
			'h005: btn_one_player  <= pressed; // F1
			'h006: btn_two_players <= pressed; // F2

			// JPAC/IPAC/MAME Style Codes
			'h016: btn_start_1     <= pressed; // 1
			'h01E: btn_start_2     <= pressed; // 2
			'h02E: btn_coin_1      <= pressed; // 5
			'h036: btn_coin_2      <= pressed; // 6
			'h02D: btn_up_2        <= pressed; // R
			'h02B: btn_down_2      <= pressed; // F
			'h023: btn_left_2      <= pressed; // D
			'h034: btn_right_2     <= pressed; // G
			'h01C: btn_trig1_2     <= pressed; // A
			'h01B: btn_trig2_2     <= pressed; // S
		endcase
	end
end

reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_trig1 = 0;
reg btn_trig2 = 0;
reg btn_one_player  = 0;
reg btn_two_players = 0;

reg btn_start_1 = 0;
reg btn_start_2 = 0;
reg btn_coin_1  = 0;
reg btn_coin_2  = 0;
reg btn_up_2    = 0;
reg btn_down_2  = 0;
reg btn_left_2  = 0;
reg btn_right_2 = 0;
reg btn_trig1_2  = 0;
reg btn_trig2_2  = 0;


wire m_up2     = btn_up_2    | joystk2[3];
wire m_down2   = btn_down_2  | joystk2[2];
wire m_left2   = btn_left_2  | joystk2[1];
wire m_right2  = btn_right_2 | joystk2[0];
wire m_trig21  = btn_trig1_2 | joystk2[4];

wire m_start1  = btn_one_player  | joystk1[4] | btn_start_1;
wire m_start2  = btn_two_players | joystk2[4] | btn_start_2;

wire m_up1     = btn_up      | joystk1[3];
wire m_down1   = btn_down    | joystk1[2];
wire m_left1   = btn_left    | joystk1[1];
wire m_right1  = btn_right   | joystk1[0];
wire m_trig11  = btn_trig1   | joystk1[4];

wire m_coin1   = btn_one_player | btn_coin_1 | joystk1[5];
wire m_coin2   = btn_two_players| btn_coin_2 | joystk2[5];


///////////////////////////////////////////////////

wire hblank, vblank;
wire ce_vid;
wire hs, vs;
wire [2:0] r,g; wire [1:0] b;

reg ce_pix;
always @(posedge clk_hdmi) begin
	reg old_clk;
	old_clk <= ce_vid;
	ce_pix  <= old_clk & ~ce_vid;
end

arcade_fx #(336,8) arcade_video
(
	.*,

	.clk_video(clk_hdmi),

	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(~hs),
	.VSync(~vs),

	.fx(status[5:3])
);

wire			PCLK;
wire  [8:0] HPOS,VPOS;
wire  [7:0] POUT;
HVGEN hvgen
(
	.HPOS(HPOS),.VPOS(VPOS),.PCLK(PCLK),.iRGB(POUT),
	.oRGB({r,g,b}),.HBLK(hblank),.VBLK(vblank),.HSYN(hs),.VSYN(vs),
	.HOFFS(HOFFS),.VOFFS(VOFFS)
);
assign ce_vid = PCLK;


wire [15:0] AOUT;
assign AUDIO_L = AOUT;
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;// unsigned PCM


///////////////////////////////////////////////////

wire	iRST = RESET | status[0] | buttons[1] | ioctl_download;


`define SELFT	bSelfTest

`define COIN1	m_coin1
`define COIN2	m_coin2

`define P1UP	m_up1
`define P1DW	m_down1
`define P1LF	m_left1
`define P1RG	m_right1
`define P1RO	m_trig11

`define P2UP	m_up2
`define P2DW	m_down2
`define P2LF	m_left2
`define P2RG	m_right2
`define P2RO	m_trig21


wire dum1,oP1DW,oP1LF,oP1RG;
wire dum2,oP2DW,oP2LF,oP2RG;

enhanced4wayjoy player1
(
    clk_sys,
    {
        `P1UP,
        `P1DW,
		  `P1LF,
        `P1RG
    },
    {dum1, oP1DW, oP1LF, oP1RG},
    DG_MODE
);

enhanced4wayjoy player2
(
    clk_sys,
    {
        `P2UP,
        `P2DW,
		  `P2LF,
        `P2RG
    },
    {dum2, oP2DW, oP2LF, oP2RG},
    DG_MODE
);

wire [10:0] INP = ~{`SELFT,`COIN2,`COIN1,oP2LF,oP2RG,oP2DW,`P2RO,oP1LF,oP1RG,oP1DW,`P1RO};

FPGA_ATETRIS GameCore
(
	.MCLK(clk_14M),.RESET(iRST),
	.INP(INP),
	.HPOS(HPOS),.VPOS(VPOS),.PCLK(PCLK),.POUT(POUT),
	.AOUT(AOUT),

	.ROMCL(clk_sys),.ROMAD(ioctl_addr),.ROMDT(ioctl_dout),.ROMEN(ioctl_wr)
);

endmodule


module HVGEN
(
	output  [8:0]		HPOS,
	output  [8:0]		VPOS,
	input 				PCLK,
	input	  [7:0]		iRGB,

	output reg [7:0]	oRGB,
	output reg			HBLK = 1,
	output reg			VBLK = 1,
	output reg			HSYN = 1,
	output reg			VSYN = 1,
	
	input   [8:0]		HOFFS,
	input   [8:0]		VOFFS
);

reg [8:0] hcnt = 0;
reg [8:0] vcnt = 0;

assign HPOS = hcnt-1;
assign VPOS = vcnt;

wire [8:0] HS_B = 360+(HOFFS*2);
wire [8:0] HS_E =  24+(HS_B);
wire [8:0] HS_N = 511-(456-HS_E);

wire [8:0] VS_B = 240+(VOFFS*2);
wire [8:0] VS_E =   3+(VS_B);

always @(posedge PCLK) begin
	case (hcnt)
		  0: begin HBLK <= 0; hcnt <= hcnt+1; end
		337: begin HBLK <= 1; hcnt <= hcnt+1; end
		511: begin hcnt <= 0;
			case (vcnt)
				239: begin VBLK <= 1; vcnt <= vcnt+1; end
				261: begin VBLK <= 0; vcnt <= 0;      end
				default: vcnt <= vcnt+1;
			endcase
		end
		default: hcnt <= hcnt+1;
	endcase

	if (hcnt==HS_B) begin HSYN <= 0; end
	if (hcnt==HS_E) begin HSYN <= 1; hcnt <= HS_N; end

	if (vcnt==VS_B) begin VSYN <= 0; end
	if (vcnt==VS_E) begin VSYN <= 1; end
	
	oRGB <= (HBLK|VBLK) ? 8'h0 : iRGB;
end

endmodule

