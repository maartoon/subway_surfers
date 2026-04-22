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
logic [11:0] fence_addr;
logic [10:0] clover_addr, moon_addr, sheep_j1_addr, sheep1_addr, sheep2_addr;
logic [2:0] fence_idx, sheep_j1_idx, sheep1_idx, sheep2_idx; // palette index
logic [1:0] clover_idx, moon_idx;

logic [3:0] fence_r, fence_g, fence_b;
logic [3:0] clover_r, clover_g, clover_b;
logic [3:0] moon_r, moon_g, moon_b;
logic [3:0] sheep1_r, sheep1_g, sheep1_b;
logic [3:0] sheep2_r, sheep2_g, sheep2_b;
logic [3:0] sheepj1_r, sheepj1_g, sheepj1_b;

logic moon_inrange, fence_inrange, clover_inrange, sheep1_inrange, sheep2_inrange, sheepj1_inrange;
logic moon_inrange_d, fence_inrange_d, clover_inrange_d, sheep1_inrange_d, sheep2_inrange_d, sheepj1_inrange_d;
logic moon_valid, fence_valid, clover_valid, sheep1_valid, sheep2_valid, sheepj1_valid;

logic [9:0] local_x_moon, local_y_moon;
logic [9:0] local_x_fence, local_y_fence;
logic [9:0] local_x_clover, local_y_clover;
logic [9:0] local_x_sheep1, local_y_sheep1;
logic [9:0] local_x_sheep2, local_y_sheep2;
logic [9:0] local_x_sheepj1, local_y_sheepj1;

localparam int MOON_X = 560, MOON_Y = 20, MOON_W = 40, MOON_H = 40;
localparam int FENCE_X = 80, FENCE_Y = 360, FENCE_W = 50, FENCE_H = 50;
localparam int CLOVER_X = 220, CLOVER_Y = 340, CLOVER_W = 40, CLOVER_H = 50;
localparam int SHEEP1_X = 300, SHEEP1_Y = 330, SHEEP1_W = 40, SHEEP1_H = 50;
localparam int SHEEP2_X = 390, SHEEP2_Y = 330, SHEEP2_W = 40, SHEEP2_H = 50;
localparam int SHEEPJ1_X = 480, SHEEPJ1_Y = 300, SHEEPJ1_W = 40, SHEEPJ1_H = 50;

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

// @todo delays drawX, drawY, hsync, vsync by one cycle due to BRAM read latency
logic [11:0] char_index;
assign char_index = (drawY[9:4] * 80) + drawX[9:3];
assign color_addr = char_index[11:1]; 

// Create 1 cycle delay using registers 
logic [9:0] delayed_drawX, delayed_drawY;
logic delayed_hsync, delayed_vsync, delayed_vde;

always_ff @(posedge clk_25MHz) begin
    delayed_drawX <= drawX;
    delayed_drawY <= drawY;
    delayed_hsync <= hsync;
    delayed_vsync <= vsync;
    delayed_vde <= vde;
    moon_inrange_d <= moon_inrange;
    fence_inrange_d <= fence_inrange;
    clover_inrange_d <= clover_inrange;
    sheep1_inrange_d <= sheep1_inrange;
    sheep2_inrange_d <= sheep2_inrange;
    sheepj1_inrange_d <= sheepj1_inrange;
end

always_comb begin
    moon_inrange = (drawX >= MOON_X) && (drawX < (MOON_X + MOON_W)) && (drawY >= MOON_Y) && (drawY < (MOON_Y + MOON_H));
    fence_inrange = (drawX >= FENCE_X) && (drawX < (FENCE_X + FENCE_W)) && (drawY >= FENCE_Y) && (drawY < (FENCE_Y + FENCE_H));
    clover_inrange = (drawX >= CLOVER_X) && (drawX < (CLOVER_X + CLOVER_W)) && (drawY >= CLOVER_Y) && (drawY < (CLOVER_Y + CLOVER_H));
    sheep1_inrange = (drawX >= SHEEP1_X) && (drawX < (SHEEP1_X + SHEEP1_W)) && (drawY >= SHEEP1_Y) && (drawY < (SHEEP1_Y + SHEEP1_H));
    sheep2_inrange = (drawX >= SHEEP2_X) && (drawX < (SHEEP2_X + SHEEP2_W)) && (drawY >= SHEEP2_Y) && (drawY < (SHEEP2_Y + SHEEP2_H));
    sheepj1_inrange = (drawX >= SHEEPJ1_X) && (drawX < (SHEEPJ1_X + SHEEPJ1_W)) && (drawY >= SHEEPJ1_Y) && (drawY < (SHEEPJ1_Y + SHEEPJ1_H));

    local_x_moon = drawX - MOON_X;
    local_y_moon = drawY - MOON_Y;
    local_x_fence = drawX - FENCE_X;
    local_y_fence = drawY - FENCE_Y;
    local_x_clover = drawX - CLOVER_X;
    local_y_clover = drawY - CLOVER_Y;
    local_x_sheep1 = drawX - SHEEP1_X;
    local_y_sheep1 = drawY - SHEEP1_Y;
    local_x_sheep2 = drawX - SHEEP2_X;
    local_y_sheep2 = drawY - SHEEP2_Y;
    local_x_sheepj1 = drawX - SHEEPJ1_X;
    local_y_sheepj1 = drawY - SHEEPJ1_Y;

    moon_addr = (moon_inrange) ? ((local_y_moon * MOON_W) + local_x_moon) : 11'd0;
    fence_addr = (fence_inrange) ? ((local_y_fence * FENCE_W) + local_x_fence) : 12'd0;
    clover_addr = (clover_inrange) ? ((local_y_clover * CLOVER_W) + local_x_clover) : 11'd0;
    sheep1_addr = (sheep1_inrange) ? ((local_y_sheep1 * SHEEP1_W) + local_x_sheep1) : 11'd0;
    sheep2_addr = (sheep2_inrange) ? ((local_y_sheep2 * SHEEP2_W) + local_x_sheep2) : 11'd0;
    sheep_j1_addr = (sheepj1_inrange) ? ((local_y_sheepj1 * SHEEPJ1_W) + local_x_sheepj1) : 11'd0;
end

// Transparency key: #FF00B7 => 4'hF,4'h0,4'hB.
assign moon_valid = moon_inrange_d && !((moon_r == 4'hF) && (moon_g == 4'h0) && (moon_b == 4'hB));
assign fence_valid = fence_inrange_d && !((fence_r == 4'hF) && (fence_g == 4'h0) && (fence_b == 4'hB));
assign clover_valid = clover_inrange_d && !((clover_r == 4'hF) && (clover_g == 4'h0) && (clover_b == 4'hB));
assign sheep1_valid = sheep1_inrange_d && !((sheep1_r == 4'hF) && (sheep1_g == 4'h0) && (sheep1_b == 4'hB));
assign sheep2_valid = sheep2_inrange_d && !((sheep2_r == 4'hF) && (sheep2_g == 4'h0) && (sheep2_b == 4'hB));
assign sheepj1_valid = sheepj1_inrange_d && !((sheepj1_r == 4'hF) && (sheepj1_g == 4'h0) && (sheepj1_b == 4'hB));

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
    .hsync(delayed_hsync),
    .vsync(delayed_vsync),
    .vde(delayed_vde),
        
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
    .DrawX(delayed_drawX),
    .DrawY(delayed_drawY),
    .vde(delayed_vde),
    .frame_count(frame_count),
    .char_data(bram_color_out),
    .color_regs(color_regs), // from the AXI module
    .moon_valid(moon_valid),
    .moon_r(moon_r),
    .moon_g(moon_g),
    .moon_b(moon_b),
    .fence_valid(fence_valid),
    .fence_r(fence_r),
    .fence_g(fence_g),
    .fence_b(fence_b),
    .clover_valid(clover_valid),
    .clover_r(clover_r),
    .clover_g(clover_g),
    .clover_b(clover_b),
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
fence_rom fence_rom_inst (
    .clka(clk_25MHz), // pixel clock
    .addra(fence_addr),
    .douta(fence_idx)
);

clover_rom clover_rom_inst (
    .clka(clk_25MHz), // pixel clock
    .addra(clover_addr),
    .douta(clover_idx)
);

moon_rom moon_rom_inst (
    .clka(clk_25MHz), // pixel clock
    .addra(moon_addr),
    .douta(moon_idx)
);

sheep1_rom sheep1_rom_inst (
    .clka(clk_25MHz), // pixel clock
    .addra(sheep1_addr),
    .douta(sheep1_idx)
);

sheep2_rom sheep2_rom_inst (
    .clka(clk_25MHz), // pixel clock
    .addra(sheep2_addr),
    .douta(sheep2_idx)
);

sheep_j1_rom sheep_j1_rom_inst (
    .clka(clk_25MHz), // pixel clock
    .addra(sheep_j1_addr),
    .douta(sheep_j1_idx)
);

fence_palette fence_palette_inst (
    .index(fence_idx),
    .red(fence_r),
    .green(fence_g),
    .blue(fence_b)
);

clover_palette clover_palette_inst (
    .index(clover_idx),
    .red(clover_r),
    .green(clover_g),
    .blue(clover_b)
);

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
