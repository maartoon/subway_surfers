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
    input logic [31:0] frame_count,

    input logic [31:0] char_data, // register containing 2 characters 
    input logic [31:0] color_regs [8],
    input logic moon_valid,
    input logic [3:0] moon_r, moon_g, moon_b,
    input logic fence_valid,
    input logic [3:0] fence_r, fence_g, fence_b,
    input logic clover_valid,
    input logic [3:0] clover_r, clover_g, clover_b,
    input logic sheep1_valid,
    input logic [3:0] sheep1_r, sheep1_g, sheep1_b,
    input logic sheep2_valid,
    input logic [3:0] sheep2_r, sheep2_g, sheep2_b,
    input logic sheepj1_valid,
    input logic [3:0] sheepj1_r, sheepj1_g, sheepj1_b,
    
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

    // Procedural environment for Step 1:
    // top half = starry sky, bottom half = scrolling grass/lane field.
    logic [3:0] env_r, env_g, env_b;
    logic [9:0] drawy_scrolled;
    logic sky_star_on;
    logic lane_mark_on;
    logic [9:0] x_dist_center;
    logic [9:0] x_dist_left;
    logic [9:0] x_dist_right;
    logic stripe_bit;

    assign drawy_scrolled = DrawY + {2'b00, frame_count[7:0]};
    assign sky_star_on = ((DrawX[7:0] ^ DrawY[7:0] ^ frame_count[8:1]) == 8'h5A)
                      || ((DrawX[7:0] + DrawY[7:0] + frame_count[9:2]) == 8'hD3);

    assign x_dist_center = (DrawX >= 10'd320) ? (DrawX - 10'd320) : (10'd320 - DrawX);
    assign x_dist_left   = (DrawX >= 10'd213) ? (DrawX - 10'd213) : (10'd213 - DrawX);
    assign x_dist_right  = (DrawX >= 10'd426) ? (DrawX - 10'd426) : (10'd426 - DrawX);

    always_comb begin
        // Thicker stripes near the bottom create stronger forward-motion cues.
        if (DrawY < 10'd300) begin
            stripe_bit = drawy_scrolled[2];
        end else if (DrawY < 10'd360) begin
            stripe_bit = drawy_scrolled[3];
        end else if (DrawY < 10'd420) begin
            stripe_bit = drawy_scrolled[4];
        end else begin
            stripe_bit = drawy_scrolled[5];
        end
    end

    always_comb begin
        // Default environment color
        if (DrawY < 10'd240) begin
            // Dark blue sky with sparse twinkling stars.
            env_r = 4'h0;
            env_g = 4'h1;
            env_b = 4'h4;
            if (sky_star_on) begin
                env_r = 4'hE;
                env_g = 4'hE;
                env_b = 4'hF;
            end
        end else begin
            // Grass field with scrolling bands for depth/motion.
            if (stripe_bit) begin
                env_r = 4'h1;
                env_g = 4'h6;
                env_b = 4'h1;
            end else begin
                env_r = 4'h0;
                env_g = 4'h4;
                env_b = 4'h0;
            end
        end

        // Lane guides to anchor the runner track.
        lane_mark_on = 1'b0;
        if (DrawY >= 10'd240) begin
            if ((x_dist_left <= 10'd1) || (x_dist_center <= 10'd1) || (x_dist_right <= 10'd1)) begin
                lane_mark_on = 1'b1;
            end
        end

        if (lane_mark_on) begin
            env_r = 4'h1;
            env_g = 4'hA;
            env_b = 4'h1;
        end
    end

    always_comb begin
        if (vde) begin // not in blanking interval
            // Base layer: environment.
            Red = env_r;
            Green = env_g;
            Blue = env_b;

            // Optional text glyphs over environment.
            if ((code_n != 7'h00) && is_foreground) begin
                Red = fg_r;
                Green = fg_g;
                Blue = fg_b;
            end

            // Foreground sprites from partner assets (priority from back to front).
            if (moon_valid) begin
                Red = moon_r;
                Green = moon_g;
                Blue = moon_b;
            end
            if (fence_valid) begin
                Red = fence_r;
                Green = fence_g;
                Blue = fence_b;
            end
            if (clover_valid) begin
                Red = clover_r;
                Green = clover_g;
                Blue = clover_b;
            end
            if (sheep1_valid) begin
                Red = sheep1_r;
                Green = sheep1_g;
                Blue = sheep1_b;
            end
            if (sheep2_valid) begin
                Red = sheep2_r;
                Green = sheep2_g;
                Blue = sheep2_b;
            end
            if (sheepj1_valid) begin
                Red = sheepj1_r;
                Green = sheepj1_g;
                Blue = sheepj1_b;
            end
        end else begin // blanking interval
            Red = 4'h0;
            Green = 4'h0;
            Blue  = 4'h0;
        end
    end
endmodule