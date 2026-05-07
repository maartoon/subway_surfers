module fence_new_rom (
	input logic clock,
	input logic [10:0] address,
	output logic [2:0] q
);

logic [2:0] memory [0:1999] /* synthesis ram_init_file = "./fence_new/fence_new.COE" */;

always_ff @ (posedge clock) begin
	q <= memory[address];
end

endmodule
