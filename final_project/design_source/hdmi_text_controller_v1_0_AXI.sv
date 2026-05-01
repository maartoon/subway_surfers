`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ECE-Illinois
// Engineer: Zuofu Cheng
// 
// Create Date: 06/08/2023 12:21:05 PM
// Design Name: 
// Module Name: hdmi_text_controller_v1_0_AXI
// Project Name: ECE 385 - hdmi_text_controller
// Target Devices: 
// Tool Versions: 
// Description: 
// This is a modified version of the Vivado template for an AXI4-Lite peripheral,
// rewritten into SystemVerilog for use with ECE 385.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.02 - File modified to be more consistent with generated template
// Revision 11/18 - Made comments less confusing
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps

module hdmi_text_controller_v1_0_AXI #
(

    // Parameters of Axi Slave Bus Interface S_AXI
    // Modify parameters as necessary for access of full VRAM range

    // Width of S_AXI data bus
    parameter integer C_S_AXI_DATA_WIDTH	= 32,
    // Width of S_AXI address bus
    parameter integer C_S_AXI_ADDR_WIDTH	= 16 // changed from 16 to 14 since axi maximum addr is x2000s
)
(
    // Users to add ports here

    // Control register signals
    input logic vsync,
    input logic [C_S_AXI_DATA_WIDTH-1:0] DrawX,
    input logic [C_S_AXI_DATA_WIDTH-1:0] DrawY,
    output logic [C_S_AXI_DATA_WIDTH-1:0] frame_count,

    // Register data output signals
    input logic [C_S_AXI_DATA_WIDTH-1:0] bram_out, // data coming out of bram
    output logic [10:0] bram_addr, // address to read from or write to
    output logic [C_S_AXI_DATA_WIDTH-1:0] bram_in, // data going into bram 
    output logic [3:0] bram_we, // write enable for bram

    output logic [C_S_AXI_DATA_WIDTH-1:0] color_regs [8], // specific color register to output

    // User ports ends

    // Global Clock Signal
    input logic  S_AXI_ACLK,

    // Global Reset Signal. This Signal is Active LOW
    input logic  S_AXI_ARESETN,

    // Write address (issued by master, acceped by Slave)
    input logic [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,

    // Write channel Protection type. This signal indicates the
        // privilege and security level of the transaction, and whether
        // the transaction is a data access or an instruction access.
    input logic [2 : 0] S_AXI_AWPROT,

    // Write address valid. This signal indicates that the master signaling
        // valid write address and control information.
    input logic  S_AXI_AWVALID,

    // Write address ready. This signal indicates that the slave is ready
        // to accept an address and associated control signals.
    output logic  S_AXI_AWREADY,

    // Write data (issued by master, acceped by Slave) 
    input logic [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
    
    // Write strobes. This signal indicates which byte lanes hold
        // valid data. There is one write strobe bit for each eight
        // bits of the write data bus.    
    input logic [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,

    // Write valid. This signal indicates that valid write
        // data and strobes are available.
    input logic  S_AXI_WVALID,

    // Write ready. This signal indicates that the slave
        // can accept the write data.
    output logic  S_AXI_WREADY,

    // Write response. This signal indicates the status
        // of the write transaction.
    output logic [1 : 0] S_AXI_BRESP,

    // Write response valid. This signal indicates that the channel
        // is signaling a valid write response.
    output logic  S_AXI_BVALID,

    // Response ready. This signal indicates that the master
        // can accept a write response.
    input logic  S_AXI_BREADY,

    // Read address (issued by master, acceped by Slave)
    input logic [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,

    // Protection type. This signal indicates the privilege
        // and security level of the transaction, and whether the
        // transaction is a data access or an instruction access.
    input logic [2 : 0] S_AXI_ARPROT,

    // Read address valid. This signal indicates that the channel
        // is signaling valid read address and control information.
    input logic  S_AXI_ARVALID,

    // Read address ready. This signal indicates that the slave is
        // ready to accept an address and associated control signals.
    output logic  S_AXI_ARREADY,

    // Read data (issued by slave)
    output logic [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,

    // Read response. This signal indicates the status of the
        // read transfer.
    output logic [1 : 0] S_AXI_RRESP,

    // Read valid. This signal indicates that the channel is
        // signaling the required read data.
    output logic  S_AXI_RVALID,

    // Read ready. This signal indicates that the master can
        // accept the read data and response information.
    input logic  S_AXI_RREADY
);

// AXI4LITE signals
logic  [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
logic  axi_awready;
logic  axi_wready;
logic  [1 : 0] 	axi_bresp;
logic  axi_bvalid;
logic  [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
logic  axi_arready;
logic  [C_S_AXI_DATA_WIDTH-1 : 0] 	axi_rdata;
logic  [1 : 0] 	axi_rresp;
logic  	axi_rvalid;

// Example-specific design signals
// local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
// ADDR_LSB is used for addressing 32/64 bit registers/memories
// ADDR_LSB = 2 for 32 bits (n downto 2)
// ADDR_LSB = 3 for 64 bits (n downto 3)
localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
localparam integer OPT_MEM_ADDR_BITS = 11; // ADDR_WIDTH - ADDR_LSB - 1
//----------------------------------------------
//-- Signals for user logic register space example
//------------------------------------------------
//-- Number of Slave Registers 4
//logic [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0;
//logic [C_S_AXI_DATA_WIDTH-1:0]	slv_reg1;
//logic [C_S_AXI_DATA_WIDTH-1:0]	slv_reg2;
//logic [C_S_AXI_DATA_WIDTH-1:0]	slv_reg3;
//
//Note: the provided Verilog template had the registered declared as above, but in order to give 
//students a hint we have replaced the 4 individual registers with an unpacked array of packed logic. 
//Note that you as the student will still need to extend this to the full register set needed for the lab.

// packed array of 32 bits (actual data content)
logic	 slv_reg_rden;
logic	 slv_reg_wren;
logic [C_S_AXI_DATA_WIDTH-1:0]	 reg_data_out;
integer	 byte_index;
logic	 aw_en;

// I/O Connections assignments

assign S_AXI_AWREADY	= axi_awready;
assign S_AXI_WREADY	= axi_wready;
assign S_AXI_BRESP	= axi_bresp;
assign S_AXI_BVALID	= axi_bvalid;
assign S_AXI_ARREADY = axi_arready;
assign S_AXI_RDATA	= axi_rdata;
assign S_AXI_RRESP	= axi_rresp;
assign S_AXI_RVALID	= axi_rvalid;
// Implement axi_awready generation
// axi_awready is asserted for one S_AXI_ACLK clock cycle when both
// S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
// de-asserted when reset is low.

always_ff @( posedge S_AXI_ACLK )
begin
  if ( S_AXI_ARESETN == 1'b0 )
    begin
      axi_awready <= 1'b0;
      aw_en <= 1'b1;
    end 
  else
    begin    
      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
        begin
          // slave is ready to accept write address when 
          // there is a valid write address and write data
          // on the write address and data bus. This design 
          // expects no outstanding transactions. 
          axi_awready <= 1'b1;
          aw_en <= 1'b0;
        end
        else if (S_AXI_BREADY && axi_bvalid)
            begin
              aw_en <= 1'b1;
              axi_awready <= 1'b0;
            end
      else           
        begin
          axi_awready <= 1'b0;
        end
    end 
end       

// Implement axi_awaddr latching
// This process is used to latch the address when both 
// S_AXI_AWVALID and S_AXI_WVALID are valid. 

always_ff @( posedge S_AXI_ACLK )
begin
  if ( S_AXI_ARESETN == 1'b0 )
    begin
      axi_awaddr <= 0;
    end 
  else
    begin    
      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
        begin
          // Write Address latching 
          axi_awaddr <= S_AXI_AWADDR;
        end
    end 
end       

// Implement axi_wready generation
// axi_wready is asserted for one S_AXI_ACLK clock cycle when both
// S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is 
// de-asserted when reset is low. 

always_ff @( posedge S_AXI_ACLK )
begin
  if ( S_AXI_ARESETN == 1'b0 )
    begin
      axi_wready <= 1'b0;
    end 
  else
    begin    
      if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en )
        begin
          // slave is ready to accept write data when 
          // there is a valid write address and write data
          // on the write address and data bus. This design 
          // expects no outstanding transactions. 
          axi_wready <= 1'b1;
        end
      else
        begin
          axi_wready <= 1'b0;
        end
    end 
end       

// Implement memory mapped register select and write logic generation
// The write data is accepted and written to memory mapped registers when
// axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
// select byte enables of slave registers while writing.
// These registers are cleared when reset (active low) is applied.
// Slave register write enable is asserted when valid address and data are available
// and the slave is ready to accept the write address and write data.
assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

// always_ff @( posedge S_AXI_ACLK )
// begin
//   if ( S_AXI_ARESETN == 1'b0 )
//     begin
//         slv_regs[600] <= 0;
//     end
//   else begin
//     if (slv_reg_wren)
//       begin
//         for ( byte_index = 0; byte_index <= (C_S_AXI_DTA_WIDTH/8)-1; byte_index = byte_index+1 )
//           if ( S_AXI_WSTRB[byte_index] == 1 ) begin
//             // Respective byte enables are asserted as per write strobes, note the use of the index part select operator
//             // '+:', you will need to understand how this operator works.
//             slv_regs[axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]][(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
//           end  
//       end
//   end
// end    

// Implement write response logic generation
// The write response and response valid signals are asserted by the slave 
// when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.  
// This marks the acceptance of address and indicates the status of 
// write transaction.

always_ff @( posedge S_AXI_ACLK )
begin
  if ( S_AXI_ARESETN == 1'b0 )
    begin
      axi_bvalid  <= 0;
      axi_bresp   <= 2'b0;
    end 
  else
    begin    
      if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID)
        begin
          // indicates a valid write response is available
          axi_bvalid <= 1'b1;
          axi_bresp  <= 2'b0; // 'OKAY' response 
        end                   // work error responses in future
      else
        begin
          if (S_AXI_BREADY && axi_bvalid) 
            //check if bready is asserted while bvalid is high) 
            //(there is a possibility that bready is always asserted high)   
            begin
              axi_bvalid <= 1'b0; 
            end  
        end
    end
end   

// Implement axi_arready generation
// axi_arready is asserted for one S_AXI_ACLK clock cycle when
// S_AXI_ARVALID is asserted. axi_awready is 
// de-asserted when reset (active low) is asserted. 
// The read address is also latched when S_AXI_ARVALID is 
// asserted. axi_araddr is reset to zero on reset assertion.

always_ff @( posedge S_AXI_ACLK )
begin
  if ( S_AXI_ARESETN == 1'b0 )
    begin
      axi_arready <= 1'b0;
      axi_araddr  <= 32'b0;
    end 
  else
    begin    
      if (~axi_arready && S_AXI_ARVALID)
        begin
          // indicates that the slave has acceped the valid read address
          axi_arready <= 1'b1;
          // Read address latching
          axi_araddr  <= S_AXI_ARADDR;
        end
      else
        begin
          axi_arready <= 1'b0;
        end
    end 
end    


// @todo: register for delaying RVALID generation by one clock cycle (done)
logic read_delay;

always_ff @( posedge S_AXI_ACLK )
begin
  if ( S_AXI_ARESETN == 1'b0 )
    begin
      read_delay <= 0;
    end 
  else
    begin    
      // When ARREADY is asserted by slave, we load axi_arready into read_delay
      // If we condition on read_delay and of axi_arready for asserting RVALID,
      // we successfully account for read latency by delaying RVALID assertion by one clock cycle.
      // Thus, master will only read the correct data after RVALID assertion
      if (axi_arready && ~read_delay)
        begin
          read_delay <= axi_arready;
        end
      else 
        begin
          read_delay <= axi_arready;
        end 
    end
end    

// Implement axi_arvalid generation
// axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both 
// S_AXI_ARVALID and axi_arready are asserted. The slave registers 
// data are available on the axi_rdata bus at this instance. The 
// assertion of axi_rvalid marks the validity of read data on the 
// bus and axi_rresp indicates the status of read transaction.axi_rvalid 
// is deasserted on reset (active low). axi_rresp and axi_rdata are 
// cleared to zero on reset (active low).  

// @todo: Since there is a one clock cycle latency from fetching data from BRAM,
//        we need to delay RVALID generation by one clock cycle to make sure data
//        is actually fetched before we tell master it's ok to grab it from the channel
always_ff @( posedge S_AXI_ACLK )
begin
  if ( S_AXI_ARESETN == 1'b0 )
    begin
      axi_rvalid <= 0;
      axi_rresp  <= 0;
    end 
  else
    begin    
      if (~axi_rvalid && read_delay) // make sure read_delay is 1, accounts for read latency
        begin
          // Valid read data is available at the read data bus
          axi_rvalid <= 1'b1;
          axi_rresp  <= 2'b0; // 'OKAY' response
        end   
      else if (axi_rvalid && S_AXI_RREADY)
        begin
          // Read data is accepted by the master
          axi_rvalid <= 1'b0;
        end                
    end
end    


// Implement memory mapped register select and read logic generation
// Slave register read enable is asserted when valid address is available
// and the slave is ready to accept the read address.
assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;
always_comb
begin
    // if axi_araddr < 0x800, we read from bram
    if (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] < 12'h800) begin
      reg_data_out = bram_out;
    end else begin
      case(axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
        // if axi_araddr >= 0x800, we read from palette registers
        12'h800: reg_data_out = color_regs[0];
        12'h801: reg_data_out = color_regs[1];
        12'h802: reg_data_out = color_regs[2];
        12'h803: reg_data_out = color_regs[3];
        12'h804: reg_data_out = color_regs[4];
        12'h805: reg_data_out = color_regs[5];
        12'h806: reg_data_out = color_regs[6];
        12'h807: reg_data_out = color_regs[7];
        12'h808: reg_data_out = frame_counter;
        12'h809: reg_data_out = DrawX;
        12'h80A: reg_data_out = DrawY;
        default: reg_data_out = 32'b0;
      endcase
    end
end

// Output register or memory read data
always_ff @( posedge S_AXI_ACLK )
begin
  if ( S_AXI_ARESETN == 1'b0 )
    begin
      axi_rdata  <= 0;
    end 
  else
    begin    
      // When there is a valid read address (S_AXI_ARVALID) with 
      // acceptance of read address by the slave (axi_arready), 
      // output the read data
      if (read_delay) // read_delay to capture rdata one cycle later
        begin
          if (axi_araddr[13] == 1'b1) 
            begin
              axi_rdata <= reg_data_out;     // register read data
            end
          else 
            begin
              axi_rdata <= bram_out; // bram read data
            end
        end   
      
    end
end    

// Add user logic here

// Choose bram_addr as axi_awaddr or axi_araddr based on if we are writing or reading
always_comb begin
  if (slv_reg_rden) begin
    bram_addr = axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB];
  end else begin
    bram_addr = axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB];
  end
end

// Frame Counter logic
logic prev_vsync;
logic [C_S_AXI_DATA_WIDTH-1:0] frame_counter;
assign frame_count = frame_counter;

always_ff @( posedge S_AXI_ACLK ) begin
  // Reset frame counter and prev_vsync
  if (S_AXI_ARESETN == 1'b0) begin
    frame_counter <= 32'b0;
    prev_vsync <= 1'b0;
  end

  else begin
    // Update frame counter on falling edge of vsync
    if (prev_vsync == 1'b1 && vsync == 1'b0) begin
      frame_counter <= frame_counter + 1;
    end

    prev_vsync <= vsync;
  end
end

// write logic for color registers
always_ff @(posedge S_AXI_ACLK) begin
  if (S_AXI_ARESETN == 1'b0) begin
    for (int i = 0; i < 8; i++) color_regs[i] <= 32'b0;
  end 
  else begin
    // write into color registers if write is enabled and awaddr >= 0x800
    if (slv_reg_wren && axi_awaddr[13:5] == 9'b100000000) begin  
      for ( byte_index = 0; byte_index <= 3; byte_index = byte_index+1 ) begin
        if ( S_AXI_WSTRB[byte_index] == 1 ) begin
          color_regs[axi_awaddr[4:2]][(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
        end  
      end
    end
  end
end

// write logic for BRAM
// Pass AXI write data straight through to the BRAM
assign bram_in = S_AXI_WDATA;

always_comb begin
  // write into BRAM if write is enabled and awaddr < 0x800
  if (slv_reg_wren && (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS] == 1'b0) && axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] <= 12'h4AF) begin
    bram_we = S_AXI_WSTRB; 
  end else begin
    bram_we = 4'b0000;
  end
end

// User logic ends

endmodule

