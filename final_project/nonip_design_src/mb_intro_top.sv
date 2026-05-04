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

  mb_block mb_block_i
       (.clk_100MHz(clk_100MHz),
       
       .HDMI_0_tmds_clk_n(HDMI_0_tmds_clk_n),
       .HDMI_0_tmds_clk_p(HDMI_0_tmds_clk_p),
       .HDMI_0_tmds_data_n(HDMI_0_tmds_data_n),
       .HDMI_0_tmds_data_p(HDMI_0_tmds_data_p),
       
       .reset_rtl_0(~reset_rtl_0),      //Note the inversion of the reset button. Buttons are active low, but the MicroBlaze reset is active high
       .uart_rtl_0_rxd(uart_rtl_0_txd),  //Note the switcheroo between RTX and TXD. This is a common source of confusion in embedded development
       .uart_rtl_0_txd(uart_rtl_0_rxd)); //RXD = Received Data, and TXD = Transmitted Data, but whether data is transmitted or received depeneds on the
                                    //perspective. Here, the TXD port means transmitted by the FPGA (but received by the Urbana Board's UART chip)
endmodule
