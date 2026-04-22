module sheep_j1_rom (
	input logic clock,
	input logic [10:0] address,
	output logic [2:0] q
);

logic [2:0] memory [0:1999] /* synthesis ram_init_file = "./sheep_j1/sheep_j1.COE" */;

always_ff @ (posedge clock) begin
	q <= memory[address];
end

endmodule
