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
logic [2:0] fence_idx, sheep_j1_idx, sheep1_idx, sheep2_idx; // palette index

logic [10:0] clover_addr, moon_addr, sheep_j1_addr, sheep1_addr, sheep2_addr;
logic [1:0] clover_idx, moon_idx;

// Instantiation of Axi Bus Interface AXI
hdmi_text_controller_v1_0_AXI # ( 
    .C_S_AXI_DATA_WIDTH(C_AXI_DATA_WIDTH),
    .C_S_AXI_ADDR_WIDTH(C_AXI_ADDR_WIDTH)
) hdmi_text_controller_v1_0_AXI_inst (
    .vsync(vsync),
    .DrawX(drawX),
    .DrawY(drawY),
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
end

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
    .char_data(bram_color_out),
    .color_regs(color_regs), // from the AXI module
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
blk_fence fence_rom (
    .addra(fence_addr),
    .clk(clk_25MHz), // pixel clock
    .douta(fence_idx)
);

blk_clover clover_rom (
    .addra(clover_addr),
    .clk(clk_25MHz), // pixel clock
    .douta(clover_idx)
);

blk_moon moon_rom (
    .addra(moon_addr),
    .clk(clk_25MHz), // pixel clock
    .douta(moon_idx)
);

blk_sheep1 sheep1_rom (
    .addra(sheep1_addr),
    .clk(clk_25MHz), // pixel clock
    .douta(sheep1_idx)
);

blk_sheep2 sheep2_rom (
    .addra(sheep2_addr),
    .clk(clk_25MHz), // pixel clock
    .douta(sheep2_idx)
);

blk_sheep_j1 sheep_j1_rom (
    .addra(sheep_j1_addr),
    .clk(clk_25MHz), // pixel clock
    .douta(sheep_j1_idx)
);

// User logic ends

endmodule
