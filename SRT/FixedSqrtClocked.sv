`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// Clocked version of FixedSqrt, latency 4 cycles, throughput 1 cycle

`default_nettype none

import Maths::*;

localparam signed [31:0] sqrt_onePointFive = 32'sh00006000; // 1.5f in fixed point

module FixedSqrtClocked(
	input wire clock,
	input wire signed [31:0] sqrtIn, // Input
	output wire signed [31:0] result); // Result

// Cycle 1
always @(posedge clock) begin

	c2_sqrtIn <= sqrtIn;

	// First-guess lookup based on number of leading zeroes
/*
	// Alternative version (in theory behaves identically, arguably more idomatic Verilog?)
	unique casez(sqrtIn)
		32'sb?1??????????????????????????????: c2_sqrtFirstGuess <= 32'sh00000034;
		32'sb?01?????????????????????????????: c2_sqrtFirstGuess <= 32'sh00000049;
		32'sb?001????????????????????????????: c2_sqrtFirstGuess <= 32'sh00000068;
		32'sb?0001???????????????????????????: c2_sqrtFirstGuess <= 32'sh00000093;
		32'sb?00001??????????????????????????: c2_sqrtFirstGuess <= 32'sh000000d1;
		32'sb?000001?????????????????????????: c2_sqrtFirstGuess <= 32'sh00000127;
		32'sb?0000001????????????????????????: c2_sqrtFirstGuess <= 32'sh000001a2;
		32'sb?00000001???????????????????????: c2_sqrtFirstGuess <= 32'sh0000024f;
		32'sb?000000001??????????????????????: c2_sqrtFirstGuess <= 32'sh00000344;
		32'sb?0000000001?????????????????????: c2_sqrtFirstGuess <= 32'sh0000049e;
		32'sb?00000000001????????????????????: c2_sqrtFirstGuess <= 32'sh00000688;
		32'sb?000000000001???????????????????: c2_sqrtFirstGuess <= 32'sh0000093c;
		32'sb?0000000000001??????????????????: c2_sqrtFirstGuess <= 32'sh00000d10;
		32'sb?00000000000001?????????????????: c2_sqrtFirstGuess <= 32'sh00001279;
		32'sb?000000000000001????????????????: c2_sqrtFirstGuess <= 32'sh00001a20;
		32'sb?0000000000000001???????????????: c2_sqrtFirstGuess <= 32'sh000024f3;
		32'sb?00000000000000001??????????????: c2_sqrtFirstGuess <= 32'sh00003441;
		32'sb?000000000000000001?????????????: c2_sqrtFirstGuess <= 32'sh000049e6;
		32'sb?0000000000000000001????????????: c2_sqrtFirstGuess <= 32'sh00006882;
		32'sb?00000000000000000001???????????: c2_sqrtFirstGuess <= 32'sh000093cd;
		32'sb?000000000000000000001??????????: c2_sqrtFirstGuess <= 32'sh0000d105;
		32'sb?0000000000000000000001?????????: c2_sqrtFirstGuess <= 32'sh0001279a;
		32'sb?00000000000000000000001????????: c2_sqrtFirstGuess <= 32'sh0001a20b;
		32'sb?000000000000000000000001???????: c2_sqrtFirstGuess <= 32'sh00024f34;
		32'sb?0000000000000000000000001??????: c2_sqrtFirstGuess <= 32'sh00034417;
		32'sb?00000000000000000000000001?????: c2_sqrtFirstGuess <= 32'sh00049e69;
		32'sb?000000000000000000000000001????: c2_sqrtFirstGuess <= 32'sh0006882f;
		32'sb?0000000000000000000000000001???: c2_sqrtFirstGuess <= 32'sh00093cd3;
		32'sb?00000000000000000000000000001??: c2_sqrtFirstGuess <= 32'sh000d105e;
		32'sb?000000000000000000000000000001?: c2_sqrtFirstGuess <= 32'sh001279a7;
		default: c2_sqrtFirstGuess <= 32'sh00200000;
	endcase
*/
	if (sqrtIn[30]) c2_sqrtFirstGuess <= 32'sh00000034;
	else if (sqrtIn[29]) c2_sqrtFirstGuess <= 32'sh00000049;
	else if (sqrtIn[28]) c2_sqrtFirstGuess <= 32'sh00000068;
	else if (sqrtIn[27]) c2_sqrtFirstGuess <= 32'sh00000093;
	else if (sqrtIn[26]) c2_sqrtFirstGuess <= 32'sh000000d1;
	else if (sqrtIn[25]) c2_sqrtFirstGuess <= 32'sh00000127;
	else if (sqrtIn[24]) c2_sqrtFirstGuess <= 32'sh000001a2;
	else if (sqrtIn[23]) c2_sqrtFirstGuess <= 32'sh0000024f;
	else if (sqrtIn[22]) c2_sqrtFirstGuess <= 32'sh00000344;
	else if (sqrtIn[21]) c2_sqrtFirstGuess <= 32'sh0000049e;
	else if (sqrtIn[20]) c2_sqrtFirstGuess <= 32'sh00000688;
	else if (sqrtIn[19]) c2_sqrtFirstGuess <= 32'sh0000093c;
	else if (sqrtIn[18]) c2_sqrtFirstGuess <= 32'sh00000d10;
	else if (sqrtIn[17]) c2_sqrtFirstGuess <= 32'sh00001279;
	else if (sqrtIn[16]) c2_sqrtFirstGuess <= 32'sh00001a20;
	else if (sqrtIn[15]) c2_sqrtFirstGuess <= 32'sh000024f3;
	else if (sqrtIn[14]) c2_sqrtFirstGuess <= 32'sh00003441;
	else if (sqrtIn[13]) c2_sqrtFirstGuess <= 32'sh000049e6;
	else if (sqrtIn[12]) c2_sqrtFirstGuess <= 32'sh00006882;
	else if (sqrtIn[11]) c2_sqrtFirstGuess <= 32'sh000093cd;
	else if (sqrtIn[10]) c2_sqrtFirstGuess <= 32'sh0000d105;
	else if (sqrtIn[9]) c2_sqrtFirstGuess <= 32'sh0001279a;
	else if (sqrtIn[8]) c2_sqrtFirstGuess <= 32'sh0001a20b;
	else if (sqrtIn[7]) c2_sqrtFirstGuess <= 32'sh00024f34;
	else if (sqrtIn[6]) c2_sqrtFirstGuess <= 32'sh00034417;
	else if (sqrtIn[5]) c2_sqrtFirstGuess <= 32'sh00049e69;
	else if (sqrtIn[4]) c2_sqrtFirstGuess <= 32'sh0006882f;
	else if (sqrtIn[3]) c2_sqrtFirstGuess <= 32'sh00093cd3;
	else if (sqrtIn[2]) c2_sqrtFirstGuess <= 32'sh000d105e;
	else if (sqrtIn[1]) c2_sqrtFirstGuess <= 32'sh001279a7;
	else c2_sqrtFirstGuess <= 32'sh00200000;
end

reg signed [31:0] c2_sqrtIn;
reg signed [31:0] c2_sqrtFirstGuess; // First guess (table-based)

// Cycle 2
always @(posedge clock) begin
	// Newton's method - x(n+1) =(x(n) * (1.5 - (val * 0.5f * x(n)^2))

	// First iteration	
	c3_sqrtIntermediate <= FixedMul(c2_sqrtFirstGuess, sqrt_onePointFive - FixedMul(c2_sqrtIn >> 1, FixedMul(c2_sqrtFirstGuess, c2_sqrtFirstGuess)));

	c3_sqrtIn <= c2_sqrtIn;
end

reg signed [31:0] c3_sqrtIn;
reg signed [31:0] c3_sqrtIntermediate; // Result of first Newton iteration

// Cycle 3
always @(posedge clock) begin
	// Second iteration
	c4_sqrtRcpResult <= FixedMul(c3_sqrtIntermediate, sqrt_onePointFive - FixedMul(c3_sqrtIn >> 1, FixedMul(c3_sqrtIntermediate, c3_sqrtIntermediate)));

	c4_sqrtIn <= c3_sqrtIn;
end

reg signed [31:0] c4_sqrtIn;
reg signed [31:0] c4_sqrtRcpResult; // Result of second Newton iteration

// Cycle 4
always @(posedge clock) begin
	if (c4_sqrtIn == 'h0) begin
		result <= 32'h0;
	end else begin
		// Convert 1/sqrt(x) to sqrt(x)
		result <= FixedMul(c4_sqrtRcpResult, c4_sqrtIn);
	end	
end
	
endmodule