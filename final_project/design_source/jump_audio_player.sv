`timescale 1 ns / 1 ps

module jump_audio_player #(
    parameter int unsigned CLK_HZ = 100_000_000,
    parameter int unsigned SAMPLE_HZ = 11_025,
    parameter int unsigned SAMPLE_COUNT = 2048
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        trigger,
    output logic [10:0] sample_addr,
    input  logic [15:0] sample_data,
    output logic        sample_rom_en,
    output logic [15:0] audio_sample,
    output logic        active
);

localparam int unsigned SAMPLE_DIV = CLK_HZ / SAMPLE_HZ;

logic playing;
logic [10:0] next_addr;
logic [15:0] sample_latched;
logic [31:0] sample_tick_count;

wire sample_tick = (sample_tick_count == (SAMPLE_DIV - 1));

assign sample_rom_en = playing || trigger;
assign sample_addr = next_addr;
assign audio_sample = sample_latched;
assign active = playing;

always_ff @(posedge clk) begin
    if (reset) begin
        playing <= 1'b0;
        next_addr <= 11'd0;
        sample_latched <= 16'h0000;
        sample_tick_count <= 32'd0;
    end else begin
        if (trigger && !playing) begin
            playing <= 1'b1;
            next_addr <= 11'd0;
            sample_latched <= 16'h0000;
            sample_tick_count <= 32'd0;
        end else if (playing) begin
            if (sample_tick) begin
                sample_tick_count <= 32'd0;
                sample_latched <= sample_data;

                if (next_addr == (SAMPLE_COUNT - 1)) begin
                    playing <= 1'b0;
                    next_addr <= 11'd0;
                end else begin
                    next_addr <= next_addr + 11'd1;
                end
            end else begin
                sample_tick_count <= sample_tick_count + 32'd1;
            end
        end else begin
            next_addr <= 11'd0;
            sample_latched <= 16'h0000;
            sample_tick_count <= 32'd0;
        end
    end
end

endmodule
