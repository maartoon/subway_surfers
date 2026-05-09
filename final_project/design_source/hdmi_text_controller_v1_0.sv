//Provided HDMI_Text_controller_v1_0 for HDMI AXI4 IP 
//Fall 2024 Distribution

//Modified 3/10/24 by Zuofu
//Updated 11/18/24 by Zuofu


`timescale 1 ns / 1 ps

module hdmi_text_controller_v1_0 #
(
    // Parameters of Axi Slave Bus Interface S00_AXI
    // Modify parameters as necessary for access of full VRAM range

    parameter integer C_AXI_DATA_WIDTH	= 32,
    parameter integer C_AXI_ADDR_WIDTH	= 16
)
(
    // Users to add ports here

    output logic hdmi_clk_n,
    output logic hdmi_clk_p,
    output logic [2:0] hdmi_tx_n,
    output logic [2:0] hdmi_tx_p,
    output logic audio_pwm,

    //HDMI
    // output logic hdmi_tmds_clk_n,
    // output logic hdmi_tmds_clk_p,
    // output logic [2:0]hdmi_tmds_data_n,
    // output logic [2:0]hdmi_tmds_data_p,    
    
    // User ports ends
    // Do not modify the ports beyond this line


    // Ports of Axi Slave Bus Interface AXI
    input logic  axi_aclk,
    input logic  axi_aresetn,
    input logic [C_AXI_ADDR_WIDTH-1 : 0] axi_awaddr,
    input logic [2 : 0] axi_awprot,
    input logic  axi_awvalid,
    output logic  axi_awready,
    input logic [C_AXI_DATA_WIDTH-1 : 0] axi_wdata,
    input logic [(C_AXI_DATA_WIDTH/8)-1 : 0] axi_wstrb,
    input logic  axi_wvalid,
    output logic  axi_wready,
    output logic [1 : 0] axi_bresp,
    output logic  axi_bvalid,
    input logic  axi_bready,
    input logic [C_AXI_ADDR_WIDTH-1 : 0] axi_araddr,
    input logic [2 : 0] axi_arprot,
    input logic  axi_arvalid,
    output logic  axi_arready,
    output logic [C_AXI_DATA_WIDTH-1 : 0] axi_rdata,
    output logic [1 : 0] axi_rresp,
    output logic  axi_rvalid,
    input logic  axi_rready
);

//additional logic variables as necessary to support VGA, and HDMI modules.

logic clk_25MHz, clk_125MHz, clk, clk_100MHz;
logic locked;
logic [9:0] drawX, drawY, ballxsig, ballysig, ballsizesig;

logic hsync, vsync, vde;
logic [3:0] red, green, blue;
logic reset_ah;
logic [31:0] frame_count;
logic sheep_use_frame2;
logic [31:0] game_regs [47];
logic [10:0] jump_sample_addr;
logic [15:0] jump_sample_data;
logic jump_sample_rom_en;
logic [15:0] jump_audio_sample;
logic jump_audio_active;
logic [10:0] crash_sample_addr;
logic [15:0] crash_sample_data;
logic crash_sample_rom_en;
logic [15:0] crash_audio_sample;
logic crash_audio_active;
logic [1:0] player_state_d;
logic [3:0] game_state_d;
logic [16:0] audio_pdm_accum;


// BRAM signals
logic [10:0] bram_addr;
logic [31:0] bram_in;
logic [31:0] bram_out;
logic [3:0] bram_we;

// color mapping
logic [31:0] color_regs [8];
logic [10:0] color_addr;
logic [31:0] bram_color_out;

// Sprites
// address size calculated from COE memory depth and width
logic [10:0] fence_addr, fence2_addr, fence3_addr, fence4_addr;
logic [10:0] clover_addr, clover2_addr, clover3_addr, moon_addr, sheep_j1_addr, sheep1_addr, sheep2_addr;
logic [2:0] fence_idx, fence2_idx, fence3_idx, fence4_idx, sheep_j1_idx, sheep1_idx, sheep2_idx; // palette index
logic [1:0] clover_idx, clover2_idx, clover3_idx, moon_idx;

logic [3:0] fence_r, fence_g, fence_b;
logic [3:0] fence2_r, fence2_g, fence2_b;
logic [3:0] fence3_r, fence3_g, fence3_b;
logic [3:0] fence4_r, fence4_g, fence4_b;
logic [3:0] clover_r, clover_g, clover_b;
logic [3:0] clover2_r, clover2_g, clover2_b;
logic [3:0] clover3_r, clover3_g, clover3_b;
logic [3:0] moon_r, moon_g, moon_b;
logic [3:0] sheep1_r, sheep1_g, sheep1_b;
logic [3:0] sheep2_r, sheep2_g, sheep2_b;
logic [3:0] sheepj1_r, sheepj1_g, sheepj1_b;

logic moon_inrange, fence_inrange, fence2_inrange, fence3_inrange, fence4_inrange, clover_inrange, clover2_inrange, clover3_inrange, sheep1_inrange, sheep2_inrange, sheepj1_inrange;
logic moon_inrange_d, fence_inrange_d, fence2_inrange_d, fence3_inrange_d, fence4_inrange_d, clover_inrange_d, clover2_inrange_d, clover3_inrange_d, sheep1_inrange_d, sheep2_inrange_d, sheepj1_inrange_d;
logic moon_valid, fence_valid, fence2_valid, fence3_valid, fence4_valid, clover_valid, clover2_valid, clover3_valid, sheep1_valid, sheep2_valid, sheepj1_valid;

logic [9:0] local_x_moon, local_y_moon;
logic [9:0] local_x_fence, local_y_fence;
logic [9:0] local_x_fence2, local_y_fence2;
logic [9:0] local_x_fence3, local_y_fence3;
logic [9:0] local_x_fence4, local_y_fence4;
logic [9:0] local_x_clover, local_y_clover;
logic [9:0] local_x_clover2, local_y_clover2;
logic [9:0] local_x_clover3, local_y_clover3;
logic [9:0] local_x_sheep1, local_y_sheep1;
logic [9:0] local_x_sheep2, local_y_sheep2;
logic [9:0] local_x_sheepj1, local_y_sheepj1;



// Keep moon static; obstacle and player positions are controlled by software via AXI game registers.
localparam [9:0] MOON_X = 10'd560, MOON_Y = 10'd20, MOON_W = 10'd40, MOON_H = 10'd40;
localparam [9:0] FENCE_W = 10'd50, FENCE_H = 10'd40;
localparam [9:0] CLOVER_W = 10'd40, CLOVER_H = 10'd50;
localparam [9:0] SHEEP_W = 10'd40, SHEEP_H = 10'd50;
localparam logic [1:0] PLAYER_RUN  = 2'd0;
localparam logic [1:0] PLAYER_JUMP = 2'd1;
localparam logic [3:0] GAME_STATE_GAMEOVER = 4'd2;

wire [9:0] player_x = game_regs[1][9:0]; // PLAYER_X
wire [9:0] player_y = game_regs[2][9:0]; // PLAYER_Y
wire [1:0] player_state = game_regs[3][1:0]; // PLAYER_STATE
wire [9:0] fence_x = game_regs[4][9:0]; // FENCE_X
wire [9:0] fence_y = game_regs[5][9:0]; // FENCE_Y
wire       fence_active = game_regs[6][0]; // FENCE_VIS
wire [9:0] clover_x = game_regs[7][9:0]; // CLOVER_X
wire [9:0] clover_y = game_regs[8][9:0]; // CLOVER_Y
wire       clover_active = game_regs[9][0]; // CLOVER_VIS
wire [3:0] game_state = game_regs[0][3:0]; // GAME_CTRL
wire       player_visible = (game_state == 4'd1);
wire jump_audio_trigger = (player_state == PLAYER_JUMP) && (player_state_d != PLAYER_JUMP);
wire crash_audio_trigger = (game_state == GAME_STATE_GAMEOVER) && (game_state_d != GAME_STATE_GAMEOVER);
wire [15:0] selected_audio_sample = crash_audio_active ? crash_audio_sample : 
                                    jump_audio_active ? jump_audio_sample : 16'h0000;
wire [15:0] selected_audio_unsigned = selected_audio_sample ^ 16'h8000;

wire [9:0] fence_w_s = game_regs[11][9:0]; // FENCE_W_S
wire [9:0] fence_h_s = game_regs[12][9:0]; // FENCE_H_S
wire [15:0] fence_scale_inv = game_regs[13][15:0]; // FENCE_SCALE_INV

wire [9:0] clover_w_s = game_regs[14][9:0]; // CLOVER_W_S
wire [9:0] clover_h_s = game_regs[15][9:0]; // CLOVER_H_S
wire [15:0] clover_scale_inv = game_regs[16][15:0]; // CLOVER_SCALE_INV

wire [9:0] fence2_x = game_regs[17][9:0];
wire [9:0] fence2_y = game_regs[18][9:0];
wire       fence2_active = game_regs[19][0];
wire [9:0] fence2_w_s = game_regs[20][9:0];
wire [9:0] fence2_h_s = game_regs[21][9:0];
wire [15:0] fence2_scale_inv = game_regs[22][15:0];

wire [9:0] fence3_x = game_regs[23][9:0];
wire [9:0] fence3_y = game_regs[24][9:0];
wire       fence3_active = game_regs[25][0];
wire [9:0] fence3_w_s = game_regs[26][9:0];
wire [9:0] fence3_h_s = game_regs[27][9:0];
wire [15:0] fence3_scale_inv = game_regs[28][15:0];

wire [9:0] fence4_x = game_regs[29][9:0];
wire [9:0] fence4_y = game_regs[30][9:0];
wire       fence4_active = game_regs[31][0];
wire [9:0] fence4_w_s = game_regs[32][9:0];
wire [9:0] fence4_h_s = game_regs[33][9:0];
wire [15:0] fence4_scale_inv = game_regs[34][15:0];

wire [9:0] clover2_x = game_regs[35][9:0];
wire [9:0] clover2_y = game_regs[36][9:0];
wire       clover2_active = game_regs[37][0];
wire [9:0] clover2_w_s = game_regs[38][9:0];
wire [9:0] clover2_h_s = game_regs[39][9:0];
wire [15:0] clover2_scale_inv = game_regs[40][15:0];

wire [9:0] clover3_x = game_regs[41][9:0];
wire [9:0] clover3_y = game_regs[42][9:0];
wire       clover3_active = game_regs[43][0];
wire [9:0] clover3_w_s = game_regs[44][9:0];
wire [9:0] clover3_h_s = game_regs[45][9:0];
wire [15:0] clover3_scale_inv = game_regs[46][15:0];

always_ff @(posedge axi_aclk) begin
    if (reset_ah) begin
        player_state_d <= PLAYER_RUN;
        game_state_d <= 4'd0;
        audio_pdm_accum <= 17'd0;
    end else begin
        player_state_d <= player_state;
        game_state_d <= game_state;

        // Always accumulate to maintain 50% duty cycle when idle (silence)
        // This prevents the amplifier from saturating due to sudden DC jumps
        audio_pdm_accum <= {1'b0, audio_pdm_accum[15:0]} + {1'b0, selected_audio_unsigned};
    end
end

assign audio_pwm = audio_pdm_accum[16];

jump_audio_player jump_audio_player_inst (
    .clk(axi_aclk),
    .reset(reset_ah),
    .trigger(jump_audio_trigger),
    .sample_addr(jump_sample_addr),
    .sample_data(jump_sample_data),
    .sample_rom_en(jump_sample_rom_en),
    .audio_sample(jump_audio_sample),
    .active(jump_audio_active)
);

jump_sound_rom jump_sound_rom_inst (
    .clka(axi_aclk),
    .ena(jump_sample_rom_en),
    .addra(jump_sample_addr),
    .douta(jump_sample_data)
);

jump_audio_player crash_audio_player_inst (
    .clk(axi_aclk),
    .reset(reset_ah),
    .trigger(crash_audio_trigger),
    .sample_addr(crash_sample_addr),
    .sample_data(crash_sample_data),
    .sample_rom_en(crash_sample_rom_en),
    .audio_sample(crash_audio_sample),
    .active(crash_audio_active)
);

crash_sound_rom crash_sound_rom_inst (
    .clka(axi_aclk),
    .ena(crash_sample_rom_en),
    .addra(crash_sample_addr),
    .douta(crash_sample_data)
);

// Instantiation of Axi Bus Interface AXI
hdmi_text_controller_v1_0_AXI # ( 
    .C_S_AXI_DATA_WIDTH(C_AXI_DATA_WIDTH),
    .C_S_AXI_ADDR_WIDTH(C_AXI_ADDR_WIDTH)
) hdmi_text_controller_v1_0_AXI_inst (
    .vsync(vsync),
    .DrawX(drawX),
    .DrawY(drawY),
    .frame_count(frame_count),
    .bram_addr(bram_addr),
    .bram_in(bram_in),
    .bram_out(bram_out),
    .bram_we(bram_we),
    .color_regs(color_regs),
    .game_regs(game_regs),


    .S_AXI_ACLK(axi_aclk),
    .S_AXI_ARESETN(axi_aresetn),
    .S_AXI_AWADDR(axi_awaddr),
    .S_AXI_AWPROT(axi_awprot),
    .S_AXI_AWVALID(axi_awvalid),
    .S_AXI_AWREADY(axi_awready),
    .S_AXI_WDATA(axi_wdata),
    .S_AXI_WSTRB(axi_wstrb),
    .S_AXI_WVALID(axi_wvalid),
    .S_AXI_WREADY(axi_wready),
    .S_AXI_BRESP(axi_bresp),
    .S_AXI_BVALID(axi_bvalid),
    .S_AXI_BREADY(axi_bready),
    .S_AXI_ARADDR(axi_araddr),
    .S_AXI_ARPROT(axi_arprot),
    .S_AXI_ARVALID(axi_arvalid),
    .S_AXI_ARREADY(axi_arready),
    .S_AXI_RDATA(axi_rdata),
    .S_AXI_RRESP(axi_rresp),    
    .S_AXI_RVALID(axi_rvalid),
    .S_AXI_RREADY(axi_rready)
);


//Instiante clocking wizard, VGA sync generator modules, and VGA-HDMI IP here. For a hint, refer to the provided
//top-level from the previous lab. You should get the IP to generate a valid HDMI signal (e.g. blue screen or gradient)
//prior to working on the text drawing.

assign reset_ah = ~axi_aresetn;

//clock wizard configured with a 1x and 5x clock for HDMI
clk_wiz_0 clk_wiz (
    .clk_out1(clk_25MHz),
    .clk_out2(clk_125MHz),
    .reset(reset_ah),
    .locked(locked),
    .clk_in1(axi_aclk)
);
    
//VGA Sync signal generator
vga_controller vga (
    .pixel_clk(clk_25MHz),
    .reset(reset_ah),
    .hs(hsync),
    .vs(vsync),
    .active_nblank(vde),
    .drawX(drawX),
    .drawY(drawY)
);    

// @todo delays drawX, drawY, hsync, vsync by two cycles due to pipelined math + BRAM read latency
logic [11:0] char_index;

// Create 1 cycle and 2 cycle delay using registers 
logic [9:0] delayed_drawX, delayed_drawY;
logic delayed_hsync, delayed_vsync, delayed_vde;

logic [9:0] delayed2_drawX, delayed2_drawY;
logic delayed2_hsync, delayed2_vsync, delayed2_vde;

logic moon_inrange_d2, fence_inrange_d2, fence2_inrange_d2, fence3_inrange_d2, fence4_inrange_d2, clover_inrange_d2, clover2_inrange_d2, clover3_inrange_d2;
logic sheep1_inrange_d2, sheep2_inrange_d2, sheepj1_inrange_d2;

logic [15:0] fence_y_unscaled_reg, fence_x_unscaled_reg;
logic [15:0] fence2_y_unscaled_reg, fence2_x_unscaled_reg;
logic [15:0] fence3_y_unscaled_reg, fence3_x_unscaled_reg;
logic [15:0] fence4_y_unscaled_reg, fence4_x_unscaled_reg;
logic [15:0] clover_y_unscaled_reg, clover_x_unscaled_reg;
logic [15:0] clover2_y_unscaled_reg, clover2_x_unscaled_reg;
logic [15:0] clover3_y_unscaled_reg, clover3_x_unscaled_reg;

logic [9:0] local_x_moon_reg, local_y_moon_reg;
logic [9:0] local_x_sheep1_reg, local_y_sheep1_reg;
logic [9:0] local_x_sheep2_reg, local_y_sheep2_reg;
logic [9:0] local_x_sheepj1_reg, local_y_sheepj1_reg;

    assign moon_inrange = (drawX >= MOON_X) && (drawX < (MOON_X + MOON_W)) && (drawY >= MOON_Y) && (drawY < (MOON_Y + MOON_H));
    assign fence_inrange = fence_active && (drawX >= fence_x) && (drawX < (fence_x + fence_w_s)) && (drawY >= fence_y) && (drawY < (fence_y + fence_h_s));
    assign fence2_inrange = fence2_active && (drawX >= fence2_x) && (drawX < (fence2_x + fence2_w_s)) && (drawY >= fence2_y) && (drawY < (fence2_y + fence2_h_s));
    assign fence3_inrange = fence3_active && (drawX >= fence3_x) && (drawX < (fence3_x + fence3_w_s)) && (drawY >= fence3_y) && (drawY < (fence3_y + fence3_h_s));
    assign fence4_inrange = fence4_active && (drawX >= fence4_x) && (drawX < (fence4_x + fence4_w_s)) && (drawY >= fence4_y) && (drawY < (fence4_y + fence4_h_s));
    assign clover_inrange = clover_active && (drawX >= clover_x) && (drawX < (clover_x + clover_w_s)) && (drawY >= clover_y) && (drawY < (clover_y + clover_h_s));
    assign clover2_inrange = clover2_active && (drawX >= clover2_x) && (drawX < (clover2_x + clover2_w_s)) && (drawY >= clover2_y) && (drawY < (clover2_y + clover2_h_s));
    assign clover3_inrange = clover3_active && (drawX >= clover3_x) && (drawX < (clover3_x + clover3_w_s)) && (drawY >= clover3_y) && (drawY < (clover3_y + clover3_h_s));
    assign sheep1_inrange = player_visible && (drawX >= player_x) && (drawX < (player_x + SHEEP_W)) && (drawY >= player_y) && (drawY < (player_y + SHEEP_H));
    assign sheep2_inrange = player_visible && (drawX >= player_x) && (drawX < (player_x + SHEEP_W)) && (drawY >= player_y) && (drawY < (player_y + SHEEP_H));
    assign sheepj1_inrange = player_visible && (drawX >= player_x) && (drawX < (player_x + SHEEP_W)) && (drawY >= player_y) && (drawY < (player_y + SHEEP_H));

    assign local_x_moon = drawX - MOON_X;
    assign local_y_moon = drawY - MOON_Y;
    assign local_x_fence = drawX - fence_x;
    assign local_y_fence = drawY - fence_y;
    assign local_x_fence2 = drawX - fence2_x;
    assign local_y_fence2 = drawY - fence2_y;
    assign local_x_fence3 = drawX - fence3_x;
    assign local_y_fence3 = drawY - fence3_y;
    assign local_x_fence4 = drawX - fence4_x;
    assign local_y_fence4 = drawY - fence4_y;
    assign local_x_clover = drawX - clover_x;
    assign local_y_clover = drawY - clover_y;
    assign local_x_clover2 = drawX - clover2_x;
    assign local_y_clover2 = drawY - clover2_y;
    assign local_x_clover3 = drawX - clover3_x;
    assign local_y_clover3 = drawY - clover3_y;
    assign local_x_sheep1 = drawX - player_x;
    assign local_y_sheep1 = drawY - player_y;
    assign local_x_sheep2 = drawX - player_x;
    assign local_y_sheep2 = drawY - player_y;
    assign local_x_sheepj1 = drawX - player_x;
    assign local_y_sheepj1 = drawY - player_y;

(* use_dsp = "no" *) wire [11:0] char_index_mult = (delayed_drawY[9:4] * 80) + delayed_drawX[9:3];
assign char_index = char_index_mult;
assign color_addr = char_index[11:1];

    (* use_dsp = "no" *) wire [31:0] fence_y_mult = local_y_fence * fence_scale_inv;
    (* use_dsp = "no" *) wire [31:0] fence_x_mult = local_x_fence * fence_scale_inv;

    (* use_dsp = "no" *) wire [31:0] fence2_y_mult = local_y_fence2 * fence2_scale_inv;
    (* use_dsp = "no" *) wire [31:0] fence2_x_mult = local_x_fence2 * fence2_scale_inv;

    (* use_dsp = "no" *) wire [31:0] fence3_y_mult = local_y_fence3 * fence3_scale_inv;
    (* use_dsp = "no" *) wire [31:0] fence3_x_mult = local_x_fence3 * fence3_scale_inv;

    (* use_dsp = "no" *) wire [31:0] fence4_y_mult = local_y_fence4 * fence4_scale_inv;
    (* use_dsp = "no" *) wire [31:0] fence4_x_mult = local_x_fence4 * fence4_scale_inv;

    (* use_dsp = "no" *) wire [31:0] clover_y_mult = local_y_clover * clover_scale_inv;
    (* use_dsp = "no" *) wire [31:0] clover_x_mult = local_x_clover * clover_scale_inv;
    (* use_dsp = "no" *) wire [31:0] clover2_y_mult = local_y_clover2 * clover2_scale_inv;
    (* use_dsp = "no" *) wire [31:0] clover2_x_mult = local_x_clover2 * clover2_scale_inv;
    (* use_dsp = "no" *) wire [31:0] clover3_y_mult = local_y_clover3 * clover3_scale_inv;
    (* use_dsp = "no" *) wire [31:0] clover3_x_mult = local_x_clover3 * clover3_scale_inv;

always_ff @(posedge clk_25MHz) begin
    // Stage 1
    delayed_drawX <= drawX;
    delayed_drawY <= drawY;
    delayed_hsync <= hsync;
    delayed_vsync <= vsync;
    delayed_vde <= vde;
    moon_inrange_d <= moon_inrange;
    fence_inrange_d <= fence_inrange;
    fence2_inrange_d <= fence2_inrange;
    fence3_inrange_d <= fence3_inrange;
    fence4_inrange_d <= fence4_inrange;
    clover_inrange_d <= clover_inrange;
    clover2_inrange_d <= clover2_inrange;
    clover3_inrange_d <= clover3_inrange;
    sheep1_inrange_d <= sheep1_inrange;
    sheep2_inrange_d <= sheep2_inrange;
    sheepj1_inrange_d <= sheepj1_inrange;
    
    fence_y_unscaled_reg <= fence_y_mult[23:8];
    fence_x_unscaled_reg <= fence_x_mult[23:8];
    fence2_y_unscaled_reg <= fence2_y_mult[23:8];
    fence2_x_unscaled_reg <= fence2_x_mult[23:8];
    fence3_y_unscaled_reg <= fence3_y_mult[23:8];
    fence3_x_unscaled_reg <= fence3_x_mult[23:8];
    fence4_y_unscaled_reg <= fence4_y_mult[23:8];
    fence4_x_unscaled_reg <= fence4_x_mult[23:8];
    clover_y_unscaled_reg <= clover_y_mult[23:8];
    clover_x_unscaled_reg <= clover_x_mult[23:8];
    clover2_y_unscaled_reg <= clover2_y_mult[23:8];
    clover2_x_unscaled_reg <= clover2_x_mult[23:8];
    clover3_y_unscaled_reg <= clover3_y_mult[23:8];
    clover3_x_unscaled_reg <= clover3_x_mult[23:8];
    
    local_x_moon_reg <= local_x_moon;
    local_y_moon_reg <= local_y_moon;
    local_x_sheep1_reg <= local_x_sheep1;
    local_y_sheep1_reg <= local_y_sheep1;
    local_x_sheep2_reg <= local_x_sheep2;
    local_y_sheep2_reg <= local_y_sheep2;
    local_x_sheepj1_reg <= local_x_sheepj1;
    local_y_sheepj1_reg <= local_y_sheepj1;

    // Stage 2
    delayed2_drawX <= delayed_drawX;
    delayed2_drawY <= delayed_drawY;
    delayed2_hsync <= delayed_hsync;
    delayed2_vsync <= delayed_vsync;
    delayed2_vde <= delayed_vde;
    
    moon_inrange_d2 <= moon_inrange_d;
    fence_inrange_d2 <= fence_inrange_d;
    fence2_inrange_d2 <= fence2_inrange_d;
    fence3_inrange_d2 <= fence3_inrange_d;
    fence4_inrange_d2 <= fence4_inrange_d;
    clover_inrange_d2 <= clover_inrange_d;
    clover2_inrange_d2 <= clover2_inrange_d;
    clover3_inrange_d2 <= clover3_inrange_d;
    sheep1_inrange_d2 <= sheep1_inrange_d;
    sheep2_inrange_d2 <= sheep2_inrange_d;
    sheepj1_inrange_d2 <= sheepj1_inrange_d;
end

    (* use_dsp = "no" *) wire [31:0] moon_addr_mult = (local_y_moon_reg * MOON_W) + local_x_moon_reg;
    assign moon_addr = (moon_inrange_d) ? moon_addr_mult[10:0] : 11'd0;

    (* use_dsp = "no" *) wire [31:0] fence_addr_mult = fence_y_unscaled_reg * FENCE_W;
    assign fence_addr = (fence_inrange_d) ? (fence_addr_mult[10:0] + fence_x_unscaled_reg[10:0]) : 11'd0;
    
    (* use_dsp = "no" *) wire [31:0] fence2_addr_mult = fence2_y_unscaled_reg * FENCE_W;
    assign fence2_addr = (fence2_inrange_d) ? (fence2_addr_mult[10:0] + fence2_x_unscaled_reg[10:0]) : 11'd0;

    (* use_dsp = "no" *) wire [31:0] fence3_addr_mult = fence3_y_unscaled_reg * FENCE_W;
    assign fence3_addr = (fence3_inrange_d) ? (fence3_addr_mult[10:0] + fence3_x_unscaled_reg[10:0]) : 11'd0;

    (* use_dsp = "no" *) wire [31:0] fence4_addr_mult = fence4_y_unscaled_reg * FENCE_W;
    assign fence4_addr = (fence4_inrange_d) ? (fence4_addr_mult[10:0] + fence4_x_unscaled_reg[10:0]) : 11'd0;
    
    (* use_dsp = "no" *) wire [31:0] clover_addr_mult = clover_y_unscaled_reg * CLOVER_W;
    assign clover_addr = (clover_inrange_d) ? (clover_addr_mult[10:0] + clover_x_unscaled_reg[10:0]) : 11'd0;

    (* use_dsp = "no" *) wire [31:0] clover2_addr_mult = clover2_y_unscaled_reg * CLOVER_W;
    assign clover2_addr = (clover2_inrange_d) ? (clover2_addr_mult[10:0] + clover2_x_unscaled_reg[10:0]) : 11'd0;

    (* use_dsp = "no" *) wire [31:0] clover3_addr_mult = clover3_y_unscaled_reg * CLOVER_W;
    assign clover3_addr = (clover3_inrange_d) ? (clover3_addr_mult[10:0] + clover3_x_unscaled_reg[10:0]) : 11'd0;

    
    (* use_dsp = "no" *) wire [31:0] sheep1_addr_mult = local_y_sheep1_reg * SHEEP_W;
    assign sheep1_addr = (sheep1_inrange_d) ? (sheep1_addr_mult[10:0] + local_x_sheep1_reg) : 11'd0;
    
    (* use_dsp = "no" *) wire [31:0] sheep2_addr_mult = local_y_sheep2_reg * SHEEP_W;
    assign sheep2_addr = (sheep2_inrange_d) ? (sheep2_addr_mult[10:0] + local_x_sheep2_reg) : 11'd0;
    
    (* use_dsp = "no" *) wire [31:0] sheepj1_addr_mult = local_y_sheepj1_reg * SHEEP_W;
    assign sheep_j1_addr = (sheepj1_inrange_d) ? (sheepj1_addr_mult[10:0] + local_x_sheepj1_reg) : 11'd0;

// Transparency key: index 0 is reserved for the background in all palettes.
// frame_count increments at v-sync; bit[3] toggles every 8 frames => 7.5 swaps/sec at 60 Hz.
assign sheep_use_frame2 = frame_count[3];

`define NOT_PINK(r, g, b) !(r >= 4'h8 && g <= 4'h4 && b >= 4'h6)

assign moon_valid = moon_inrange_d2 && (moon_idx != 0) && `NOT_PINK(moon_r, moon_g, moon_b);
assign fence_valid = fence_inrange_d2 && (fence_idx != 0) && `NOT_PINK(fence_r, fence_g, fence_b);
assign fence2_valid = fence2_inrange_d2 && (fence2_idx != 0) && `NOT_PINK(fence2_r, fence2_g, fence2_b);
assign fence3_valid = fence3_inrange_d2 && (fence3_idx != 0) && `NOT_PINK(fence3_r, fence3_g, fence3_b);
assign fence4_valid = fence4_inrange_d2 && (fence4_idx != 0) && `NOT_PINK(fence4_r, fence4_g, fence4_b);
assign clover_valid = clover_inrange_d2 && (clover_idx != 0) && `NOT_PINK(clover_r, clover_g, clover_b);
assign clover2_valid = clover2_inrange_d2 && (clover2_idx != 0) && `NOT_PINK(clover2_r, clover2_g, clover2_b);
assign clover3_valid = clover3_inrange_d2 && (clover3_idx != 0) && `NOT_PINK(clover3_r, clover3_g, clover3_b);
assign sheep1_valid = sheep1_inrange_d2 && ~sheep_use_frame2 && (player_state != PLAYER_JUMP) && (sheep1_idx != 1) && `NOT_PINK(sheep1_r, sheep1_g, sheep1_b);
assign sheep2_valid = sheep2_inrange_d2 && sheep_use_frame2 && (player_state != PLAYER_JUMP) && (sheep2_idx != 3) && `NOT_PINK(sheep2_r, sheep2_g, sheep2_b);
assign sheepj1_valid = sheepj1_inrange_d2 && (player_state == PLAYER_JUMP) && (sheep_j1_idx != 0) && `NOT_PINK(sheepj1_r, sheepj1_g, sheepj1_b); 

//Real Digital VGA to HDMI converter
hdmi_tx_0 vga_to_hdmi (
    //Clocking and Reset
    .pix_clk(clk_25MHz),
    .pix_clkx5(clk_125MHz),
    .pix_clk_locked(locked),
    .rst(reset_ah),
    //Color and Sync Signals
    .red(red),
    .green(green),
    .blue(blue),
    .hsync(delayed2_hsync),
    .vsync(delayed2_vsync),
    .vde(delayed2_vde),
        
    //aux Data (unused)
    .aux0_din(4'b0),
    .aux1_din(4'b0),
    .aux2_din(4'b0),
    .ade(1'b0),
        
    //Differential outputs
    .TMDS_CLK_P(hdmi_clk_p),          
    .TMDS_CLK_N(hdmi_clk_n),          
    .TMDS_DATA_P(hdmi_tx_p),         
    .TMDS_DATA_N(hdmi_tx_n)
);

// Color mapper
color_mapper color_instance (
    .DrawX(delayed2_drawX),
    .DrawY(delayed2_drawY),
    .vde(delayed2_vde),
    .frame_count(frame_count),
    .char_data(bram_color_out),
    .color_regs(color_regs), // from the AXI module
    .game_state(game_state),
    .moon_valid(moon_valid),
    .moon_r(moon_r),
    .moon_g(moon_g),
    .moon_b(moon_b),
    .fence_valid(fence_valid),
    .fence_r(fence_r),
    .fence_g(fence_g),
    .fence_b(fence_b),
    .fence2_valid(fence2_valid),
    .fence2_r(fence2_r),
    .fence2_g(fence2_g),
    .fence2_b(fence2_b),
    .fence3_valid(fence3_valid),
    .fence3_r(fence3_r),
    .fence3_g(fence3_g),
    .fence3_b(fence3_b),
    .fence4_valid(fence4_valid),
    .fence4_r(fence4_r),
    .fence4_g(fence4_g),
    .fence4_b(fence4_b),
    .clover_valid(clover_valid),
    .clover_r(clover_r),
    .clover_g(clover_g),
    .clover_b(clover_b),
    .clover2_valid(clover2_valid),
    .clover2_r(clover2_r),
    .clover2_g(clover2_g),
    .clover2_b(clover2_b),
    .clover3_valid(clover3_valid),
    .clover3_r(clover3_r),
    .clover3_g(clover3_g),
    .clover3_b(clover3_b),
    .sheep1_valid(sheep1_valid),
    .sheep1_r(sheep1_r),
    .sheep1_g(sheep1_g),
    .sheep1_b(sheep1_b),
    .sheep2_valid(sheep2_valid),
    .sheep2_r(sheep2_r),
    .sheep2_g(sheep2_g),
    .sheep2_b(sheep2_b),
    .sheepj1_valid(sheepj1_valid),
    .sheepj1_r(sheepj1_r),
    .sheepj1_g(sheepj1_g),
    .sheepj1_b(sheepj1_b),
//    .color_addr(color_addr), // sends the requested index to the AXI module
    .Red(red),
    .Green(green),
    .Blue(blue)
);

// BRAM
blk_mem_gen_0 blk_mem_inst (
    // port a for AXI
    .addra(bram_addr), // [10:0] 11-bit address, could be axi_araddr or axi_awaddr 
    .clka(axi_aclk), 
    .dina(bram_in), // [31:0] 32-bit word input
    .douta(bram_out), // [31:0] 32-bit word output
    .ena(1'b1), // Enables Read, Write, and reset operations through port A. Optional in all configurations.
    .wea(bram_we), // write enable port A

    // port b for color mapper
    .addrb(color_addr), // [10:0] 11-bit address
    .clkb(clk_25MHz), 
    .dinb(32'h00000000), // disconnected, never write with port b
    .doutb(bram_color_out), // [31:0] 32-bit word output
    .enb(1'b1), // Enables Read, Write, and reset operations through port B. Optional in all configurations.
    .web(4'b0000) // write enable for port B
);

// Sprite BROM
// fence
fence_new_rom fence_rom_inst (
    .clka(clk_25MHz),
    .addra(fence_addr),
    .douta(fence_idx),
    .ena(1'b1)
);

fence_new_rom fence2_rom_inst (.clka(clk_25MHz), .addra(fence2_addr), .douta(fence2_idx), .ena(1'b1));
fence_new_rom fence3_rom_inst (.clka(clk_25MHz), .addra(fence3_addr), .douta(fence3_idx), .ena(1'b1));
fence_new_rom fence4_rom_inst (.clka(clk_25MHz), .addra(fence4_addr), .douta(fence4_idx), .ena(1'b1));

clover_rom clover_rom_inst (
    .clka(clk_25MHz),
    .addra(clover_addr),
    .douta(clover_idx),
    .ena(1'b1)
);

clover_rom clover2_rom_inst (.clka(clk_25MHz), .addra(clover2_addr), .douta(clover2_idx), .ena(1'b1));
clover_rom clover3_rom_inst (.clka(clk_25MHz), .addra(clover3_addr), .douta(clover3_idx), .ena(1'b1));

moon_rom moon_rom_inst (
    .clka(clk_25MHz), // pixel clock
    .addra(moon_addr),
    .douta(moon_idx),
    .ena(1'b1)
);

sheep1_rom sheep1_rom_inst (
    .clka(clk_25MHz), // pixel clock
    .addra(sheep1_addr),
    .douta(sheep1_idx),
    .ena(1'b1)
);

sheep2_rom sheep2_rom_inst (
    .clka(clk_25MHz), // pixel clock
    .addra(sheep2_addr),
    .douta(sheep2_idx),
    .ena(1'b1)
);

sheep_j1_rom sheep_j1_rom_inst (
    .clka(clk_25MHz), // pixel clock
    .addra(sheep_j1_addr),
    .douta(sheep_j1_idx),
    .ena(1'b1)
);

fence_new_palette fence_palette_inst (
    .index(fence_idx),
    .red(fence_r),
    .green(fence_g),
    .blue(fence_b)
);

fence_new_palette fence2_palette_inst (.index(fence2_idx), .red(fence2_r), .green(fence2_g), .blue(fence2_b));
fence_new_palette fence3_palette_inst (.index(fence3_idx), .red(fence3_r), .green(fence3_g), .blue(fence3_b));
fence_new_palette fence4_palette_inst (.index(fence4_idx), .red(fence4_r), .green(fence4_g), .blue(fence4_b));

clover_palette clover_palette_inst (
    .index(clover_idx),
    .red(clover_r),
    .green(clover_g),
    .blue(clover_b)
);

clover_palette clover2_palette_inst (.index(clover2_idx), .red(clover2_r), .green(clover2_g), .blue(clover2_b));
clover_palette clover3_palette_inst (.index(clover3_idx), .red(clover3_r), .green(clover3_g), .blue(clover3_b));

moon_palette moon_palette_inst (
    .index(moon_idx),
    .red(moon_r),
    .green(moon_g),
    .blue(moon_b)
);

sheep1_palette sheep1_palette_inst (
    .index(sheep1_idx),
    .red(sheep1_r),
    .green(sheep1_g),
    .blue(sheep1_b)
);

sheep2_palette sheep2_palette_inst (
    .index(sheep2_idx),
    .red(sheep2_r),
    .green(sheep2_g),
    .blue(sheep2_b)
);

sheep_j1_palette sheep_j1_palette_inst (
    .index(sheep_j1_idx),
    .red(sheepj1_r),
    .green(sheepj1_g),
    .blue(sheepj1_b)
);

// User logic ends

endmodule
