`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// Dither pattern lookup ROM

module DitherPatternROM (
	input [0:0] x,
	input [1:0] y,
	
	output [3:0] pixel
);

// 4x2 matrix
always @(*) begin
	case({y, x})
		4'h0: pixel = 0;
		4'h1: pixel = 4;
		4'h2: pixel = 2;
		4'h3: pixel = 6;
		4'h4: pixel = 3;
		4'h5: pixel = 7;
		4'h6: pixel = 1;
		4'h7: pixel = 5;
	endcase
end

// 4x4 matrix

/*
module DitherPatternROM (
	input [1:0] x,
	input [1:0] y,
	
	output [3:0] pixel
);

always @(*) begin
	case({y, x})
		4'h0: pixel = 0;
		4'h1: pixel = 12;
		4'h2: pixel = 13;
		4'h3: pixel = 15;
		4'h4: pixel = 8;
		4'h5: pixel = 4;
		4'h6: pixel = 11;
		4'h7: pixel = 7;
		4'h8: pixel = 2;
		4'h9: pixel = 14;
		4'hA: pixel = 1;
		4'hB: pixel = 13;
		4'hC: pixel = 10;
		4'hD: pixel = 6;
		4'hE: pixel = 9;
		4'hF: pixel = 5;
	endcase
end
*/

endmodule
