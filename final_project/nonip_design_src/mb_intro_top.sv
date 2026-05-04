`timescale 1ns / 1ps
//mb_intro_top
//
//Replacement block diagram wrapper file and top level for use with ECE 385
//MicroBlaze introduction tutorial. Note that this instances only the block
//design with no additional logic. You will have to modify this for future labs
//to instantate additional logic
//
//Distribution starting with Fall 2023 semester
//modified 7/25/2023 - Zuofu

module mb_intro_top(
    input logic clk_100MHz,
    input logic reset_rtl_0,

    //USB signals
    input logic [0:0] gpio_usb_int_tri_i,
    output logic [0:0] gpio_usb_rst_tri_o,
    input logic usb_spi_miso,
    output logic usb_spi_mosi,
    output logic usb_spi_sclk,
    output logic [0:0] usb_spi_ss,

    //UART
    input logic uart_rtl_0_rxd,
    output logic uart_rtl_0_txd,

    //HDMI
    output logic HDMI_0_tmds_clk_n,
    output logic HDMI_0_tmds_clk_p,
    output logic [2:0]HDMI_0_tmds_data_n,
    output logic [2:0]HDMI_0_tmds_data_p,

    //HEX displays
    output logic [7:0] hex_segA,
    output logic [3:0] hex_gridA,
    output logic [7:0] hex_segB,
    output logic [3:0] hex_gridB);

  logic [31:0] gpio_usb_keycode_0_tri_o;
  logic [31:0] gpio_usb_keycode_1_tri_o;

  // Keep HEX displays inactive for now.
  assign hex_segA = 8'hFF;
  assign hex_gridA = 4'hF;
  assign hex_segB = 8'hFF;
  assign hex_gridB = 4'hF;

  mb_block mb_block_i
       (.clk_100MHz(clk_100MHz),
       
       .HDMI_0_tmds_clk_n(HDMI_0_tmds_clk_n),
       .HDMI_0_tmds_clk_p(HDMI_0_tmds_clk_p),
       .HDMI_0_tmds_data_n(HDMI_0_tmds_data_n),
       .HDMI_0_tmds_data_p(HDMI_0_tmds_data_p),
       .gpio_usb_int_tri_i(gpio_usb_int_tri_i),
       .gpio_usb_keycode_0_tri_o(gpio_usb_keycode_0_tri_o),
       .gpio_usb_keycode_1_tri_o(gpio_usb_keycode_1_tri_o),
       .gpio_usb_rst_tri_o(gpio_usb_rst_tri_o),
       
       .reset_rtl_0(~reset_rtl_0),      // Keep reset polarity consistent with block design expectations
       .uart_rtl_0_rxd(uart_rtl_0_rxd), // UART RX from board USB-UART into MicroBlaze
       .uart_rtl_0_txd(uart_rtl_0_txd), // UART TX from MicroBlaze out to board USB-UART
       .usb_spi_miso(usb_spi_miso),
       .usb_spi_mosi(usb_spi_mosi),
       .usb_spi_sclk(usb_spi_sclk),
       .usb_spi_ss(usb_spi_ss));
endmodule
