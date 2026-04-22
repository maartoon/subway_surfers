module sheep1_rom (
	input logic clock,
	input logic [10:0] address,
	output logic [2:0] q
);

logic [2:0] memory [0:1999] /* synthesis ram_init_file = "./sheep1/sheep1.COE" */;

always_ff @ (posedge clock) begin
	q <= memory[address];
end

endmodule
