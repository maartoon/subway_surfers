`timescale 1 ns / 1 ps

module jump_sound_rom (
    input  logic        clka,
    input  logic        ena,
    input  logic [10:0] addra,
    output logic [15:0] douta
);

logic [15:0] memory [0:2047] /* synthesis ram_init_file = "./meh/meh.coe" */;

always_ff @(posedge clka) begin
    if (ena) begin
        douta <= memory[addra];
    end
end

endmodule
