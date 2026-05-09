`timescale 1 ns / 1 ps

module jump_audio_player_tb;

logic clk = 1'b0;
logic reset = 1'b1;
logic trigger = 1'b0;
logic [10:0] sample_addr;
logic [15:0] sample_data;
logic sample_rom_en;
logic [15:0] audio_sample;
logic active;

logic [15:0] memory [0:3];

always #5 clk = ~clk;

always_ff @(posedge clk) begin
    if (sample_rom_en) begin
        sample_data <= memory[sample_addr[1:0]];
    end
end

jump_audio_player #(
    .CLK_HZ(100),
    .SAMPLE_HZ(10),
    .SAMPLE_COUNT(4)
) dut (
    .clk(clk),
    .reset(reset),
    .trigger(trigger),
    .sample_addr(sample_addr),
    .sample_data(sample_data),
    .sample_rom_en(sample_rom_en),
    .audio_sample(audio_sample),
    .active(active)
);

initial begin
    memory[0] = 16'h8000;
    memory[1] = 16'hffff;
    memory[2] = 16'h0000;
    memory[3] = 16'h7fff;
    sample_data = 16'h0000;

    repeat (2) @(posedge clk);
    reset = 1'b0;
    repeat (2) @(posedge clk);

    trigger = 1'b1;
    @(posedge clk);
    trigger = 1'b0;

    wait (sample_addr == 11'd3);
    repeat (12) @(posedge clk);
    assert (active == 1'b0) else $error("audio did not stop after final sample");

    repeat (2) @(posedge clk);
    trigger = 1'b1;
    @(posedge clk);
    trigger = 1'b0;
    #1;
    assert (active == 1'b1) else $error("audio did not restart on a later trigger");

    $finish;
end

endmodule
