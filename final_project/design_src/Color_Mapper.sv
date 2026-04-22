//-------------------------------------------------------------------------
//    Color_Mapper.sv                                                    --
//    Stephen Kempf                                                      --
//    3-1-06                                                             --
//                                                                       --
//    Modified by David Kesler  07-16-2008                               --
//    Translated by Joe Meng    07-07-2013                               --
//    Modified by Zuofu Cheng   08-19-2023                               --
//                                                                       --
//    Fall 2023 Distribution                                             --
//                                                                       --
//    For use with ECE 385 USB + HDMI                                    --
//    University of Illinois ECE Department                              --
//-------------------------------------------------------------------------


module  color_mapper ( 
    input logic [9:0] DrawX, DrawY,
    input logic vde,

    input logic [31:0] char_data, // register containing 2 characters 
    input logic [31:0] color_regs [8],
    
//    output logic [10:0] color_addr, // which register to read 
    output logic [3:0]  Red, Green, Blue);
	  

    // 1. Calculate coordinates (80 columns x 30 rows)
    logic [6:0] col; 
    logic [4:0] row; 
    assign col = DrawX[9:3]; // divide by 8
    assign row = DrawY[9:4]; // divide by 16

    // 2. Find index of character from (row, col) index
    logic [11:0] char_index; // 2400 characters
    assign char_index = (row << 6) + (row << 4) + col; // equiv. to (row * 80) + col

    // 3. Find out which word (register) char_index corresponds to
//    assign color_addr = (char_index < 2400) ? char_index[11:1] : 11'd0; // divide by 2 if index is in range

    // 4. Find which character char_index corresponds to in word
    logic [7:0] char;
    logic [3:0] fg_idx, bg_idx;
    always_comb begin
        if (char_index[0] == 1'b0) begin
            // character 0 (bits 15:0)
            char = char_data[15:8];  // CODE0 and IV0
            fg_idx = char_data[7:4]; // FGD_IDX0
            bg_idx = char_data[3:0]; // BKG_IDX0
        end else begin
            // character 1 (bits 31:16)
            char = char_data[31:24]; // CODE1 and IV1
            fg_idx = char_data[23:20]; // FGD_IDX1
            bg_idx = char_data[19:16]; // BKG_IDX1
        end
    end 

    // 5. Find actual pixel colors using font_rom.sv
    logic [6:0] code_n;
    logic iv;
    assign code_n = char[6:0];
    assign iv = char[7];

    // Look up pixel in font rom
    logic [10:0] font_addr;
    logic [7:0] font_data;
    logic font_bit;

    // address is CODEn + least significant 4 bits of DrawY
    assign font_addr = {code_n, DrawY[3:0]};

    font_rom font_rom_inst (
        .addr(font_addr),
        .data(font_data)
    );

    // Invert index since we draw from MSB to LSB but DrawX counts from 0-7
    assign font_bit = font_data[~DrawX[2:0]];

    // Extract foreground and background colors
    logic [3:0] fg_r, fg_g, fg_b;
    logic [3:0] bg_r, bg_g, bg_b;
    
    always_comb begin 
        // LSB of fg_idx and bg_idx determines if we pick upper color or lower color in 32-bit word
        if(fg_idx[0] == 1'b1) begin
            fg_r = color_regs[fg_idx[3:1]][27:24];
            fg_g = color_regs[fg_idx[3:1]][23:20];
            fg_b = color_regs[fg_idx[3:1]][19:16];
        end else begin
            fg_r = color_regs[fg_idx[3:1]][11:8];
            fg_g = color_regs[fg_idx[3:1]][7:4];
            fg_b = color_regs[fg_idx[3:1]][3:0];
        end

        if(bg_idx[0] == 1'b1) begin
            bg_r = color_regs[bg_idx[3:1]][27:24];
            bg_g = color_regs[bg_idx[3:1]][23:20];
            bg_b = color_regs[bg_idx[3:1]][19:16];
        end else begin
            bg_r = color_regs[bg_idx[3:1]][11:8];
            bg_g = color_regs[bg_idx[3:1]][7:4];
            bg_b = color_regs[bg_idx[3:1]][3:0];
        end
    end

    // Flip colors if IV bit is 1
    logic is_foreground;
    assign is_foreground = font_bit ^ iv;

    always_comb begin
        if (vde) begin // not in blanking interval
            if (is_foreground) begin
                Red = fg_r;
                Green = fg_g;
                Blue = fg_b;
            end 
            else begin
                Red = bg_r;
                Green = bg_g;
                Blue = bg_b;
            end
        end else begin // blanking interval
            Red = 4'h0;
            Green = 4'h0;
            Blue  = 4'h0;
        end
    end
endmodule