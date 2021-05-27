`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// This implements a bunch of functions for fixed-point maths

`default_nettype none

package Maths;

localparam [31:0] fixedShift = 14; // Left shift factor for fixed point (i.e. how many fractional bits do we have)
localparam signed [31:0] onePointFive = 32'sh00006000; // 1.5f in fixed point

// Convert 8.7 value

function automatic signed [31:0] ConvertFrom8dot7;
	input signed [14:0] x;
	begin
		ConvertFrom8dot7 = 32'($signed({ x, 7'h0 })); // Note: Padding by fixedShift-7 here
	end
endfunction

// Convert 4.7 value

function automatic signed [31:0] ConvertFrom4dot7;
	input signed [10:0] x;
	begin
		ConvertFrom4dot7 = 32'($signed({ x, 7'h0 })); // Note: Padding by fixedShift-7 here
	end
endfunction

// Convert 2.10 value

function automatic signed [15:0] ConvertFrom2dot10;
	input signed [11:0] x;
	begin
		ConvertFrom2dot10 = 16'($signed({ x, 4'h0 })); // Note: Padding by fixedShift-10 here
	end
endfunction

// Convert 8.12 value

function automatic signed [31:0] ConvertFrom8dot12;
	input signed [19:0] x;
	begin
		ConvertFrom8dot12 = 32'($signed({ x, 2'h0 })); // Note: Padding by fixedShift-12 here
	end
endfunction

// Convert 8.1 value

function automatic signed [31:0] ConvertFrom8dot1;
	input signed [8:0] x;
	begin
		ConvertFrom8dot1 = 32'($signed({ x, 13'h0 })); // Note: Padding by fixedShift-1 here
	end
endfunction

// Fixed-point mul (48-bit internal precision)

function automatic signed [31:0] FixedMul48;
	input signed [31:0] x;
	input signed [31:0] y;
	begin
		// Sign-extend out to 48 bits and then truncate again afterwards
		FixedMul48 = 32'($signed({{16{x[31]}}, x} * {{16{y[31]}}, y}) >>> fixedShift);
	end
endfunction

// Fixed-point mul (40-bit internal precision)

function automatic signed [31:0] FixedMul;
	input signed [31:0] x;
	input signed [31:0] y;
	begin
		// Sign-extend out to 40 bits and then truncate again afterwards
		FixedMul = 32'($signed({{8{x[31]}}, x} * {{8{y[31]}}, y}) >>> fixedShift);
	end
endfunction

// Fixed-point mul (16bit X 16 bit with 32-bit output)

function automatic signed [31:0] FixedMul16x16;
	input signed [15:0] x;
	input signed [15:0] y;
	begin
		// Sign-extend out to 32 bits
		FixedMul16x16 = $signed({{16{x[15]}}, x} * {{16{y[15]}}, y}) >>> fixedShift;
	end
endfunction

// Fast fixed-point recprical square root
// Takes ~4 cycles

function automatic signed [31:0] FixedRcpSqrt;
	input signed [31:0] sqrtIn; // Input
	reg signed [31:0] sqrtFirstGuess; // First guess (table-based)
	reg signed [31:0] sqrtIntermediate; // Result of first Newton iteration
	begin	
		// First-guess lookup based on number of leading zeroes
		
		if (sqrtIn[30]) sqrtFirstGuess = 32'sh00000034;
		else if (sqrtIn[29]) sqrtFirstGuess = 32'sh00000049;
		else if (sqrtIn[28]) sqrtFirstGuess = 32'sh00000068;
		else if (sqrtIn[27]) sqrtFirstGuess = 32'sh00000093;
		else if (sqrtIn[26]) sqrtFirstGuess = 32'sh000000d1;
		else if (sqrtIn[25]) sqrtFirstGuess = 32'sh00000127;
		else if (sqrtIn[24]) sqrtFirstGuess = 32'sh000001a2;
		else if (sqrtIn[23]) sqrtFirstGuess = 32'sh0000024f;
		else if (sqrtIn[22]) sqrtFirstGuess = 32'sh00000344;
		else if (sqrtIn[21]) sqrtFirstGuess = 32'sh0000049e;
		else if (sqrtIn[20]) sqrtFirstGuess = 32'sh00000688;
		else if (sqrtIn[19]) sqrtFirstGuess = 32'sh0000093c;
		else if (sqrtIn[18]) sqrtFirstGuess = 32'sh00000d10;
		else if (sqrtIn[17]) sqrtFirstGuess = 32'sh00001279;
		else if (sqrtIn[16]) sqrtFirstGuess = 32'sh00001a20;
		else if (sqrtIn[15]) sqrtFirstGuess = 32'sh000024f3;
		else if (sqrtIn[14]) sqrtFirstGuess = 32'sh00003441;
		else if (sqrtIn[13]) sqrtFirstGuess = 32'sh000049e6;
		else if (sqrtIn[12]) sqrtFirstGuess = 32'sh00006882;
		else if (sqrtIn[11]) sqrtFirstGuess = 32'sh000093cd;
		else if (sqrtIn[10]) sqrtFirstGuess = 32'sh0000d105;
		else if (sqrtIn[9]) sqrtFirstGuess = 32'sh0001279a;
		else if (sqrtIn[8]) sqrtFirstGuess = 32'sh0001a20b;
		else if (sqrtIn[7]) sqrtFirstGuess = 32'sh00024f34;
		else if (sqrtIn[6]) sqrtFirstGuess = 32'sh00034417;
		else if (sqrtIn[5]) sqrtFirstGuess = 32'sh00049e69;
		else if (sqrtIn[4]) sqrtFirstGuess = 32'sh0006882f;
		else if (sqrtIn[3]) sqrtFirstGuess = 32'sh00093cd3;
		else if (sqrtIn[2]) sqrtFirstGuess = 32'sh000d105e;
		else if (sqrtIn[1]) sqrtFirstGuess = 32'sh001279a7;
		else sqrtFirstGuess = 32'sh00200000;

		// Newton's method - x(n+1) =(x(n) * (1.5 - (val * 0.5f * x(n)^2))
		
		// First iteration	
		sqrtIntermediate = FixedMul(sqrtFirstGuess, onePointFive - FixedMul(sqrtIn >>> 1, FixedMul(sqrtFirstGuess, sqrtFirstGuess)));
		
		// Second iteration
		FixedRcpSqrt = FixedMul(sqrtIntermediate, onePointFive - FixedMul(sqrtIn >>> 1, FixedMul(sqrtIntermediate, sqrtIntermediate)));
	end
endfunction

// Fast fixed-point square root
// Takes ~4 cycles

function automatic signed [31:0] FixedSqrt;
	input signed [31:0] sqrtIn; // Input
	reg signed [31:0] sqrtFirstGuess; // First guess (table-based)
	reg signed [31:0] sqrtIntermediate; // Result of first Newton iteration
	reg signed [31:0] sqrtRcpResult; // Result of second Newton iteration
	begin	
		// First-guess lookup based on number of leading zeroes
		
		if (sqrtIn[30]) sqrtFirstGuess = 32'sh00000034;
		else if (sqrtIn[29]) sqrtFirstGuess = 32'sh00000049;
		else if (sqrtIn[28]) sqrtFirstGuess = 32'sh00000068;
		else if (sqrtIn[27]) sqrtFirstGuess = 32'sh00000093;
		else if (sqrtIn[26]) sqrtFirstGuess = 32'sh000000d1;
		else if (sqrtIn[25]) sqrtFirstGuess = 32'sh00000127;
		else if (sqrtIn[24]) sqrtFirstGuess = 32'sh000001a2;
		else if (sqrtIn[23]) sqrtFirstGuess = 32'sh0000024f;
		else if (sqrtIn[22]) sqrtFirstGuess = 32'sh00000344;
		else if (sqrtIn[21]) sqrtFirstGuess = 32'sh0000049e;
		else if (sqrtIn[20]) sqrtFirstGuess = 32'sh00000688;
		else if (sqrtIn[19]) sqrtFirstGuess = 32'sh0000093c;
		else if (sqrtIn[18]) sqrtFirstGuess = 32'sh00000d10;
		else if (sqrtIn[17]) sqrtFirstGuess = 32'sh00001279;
		else if (sqrtIn[16]) sqrtFirstGuess = 32'sh00001a20;
		else if (sqrtIn[15]) sqrtFirstGuess = 32'sh000024f3;
		else if (sqrtIn[14]) sqrtFirstGuess = 32'sh00003441;
		else if (sqrtIn[13]) sqrtFirstGuess = 32'sh000049e6;
		else if (sqrtIn[12]) sqrtFirstGuess = 32'sh00006882;
		else if (sqrtIn[11]) sqrtFirstGuess = 32'sh000093cd;
		else if (sqrtIn[10]) sqrtFirstGuess = 32'sh0000d105;
		else if (sqrtIn[9]) sqrtFirstGuess = 32'sh0001279a;
		else if (sqrtIn[8]) sqrtFirstGuess = 32'sh0001a20b;
		else if (sqrtIn[7]) sqrtFirstGuess = 32'sh00024f34;
		else if (sqrtIn[6]) sqrtFirstGuess = 32'sh00034417;
		else if (sqrtIn[5]) sqrtFirstGuess = 32'sh00049e69;
		else if (sqrtIn[4]) sqrtFirstGuess = 32'sh0006882f;
		else if (sqrtIn[3]) sqrtFirstGuess = 32'sh00093cd3;
		else if (sqrtIn[2]) sqrtFirstGuess = 32'sh000d105e;
		else if (sqrtIn[1]) sqrtFirstGuess = 32'sh001279a7;
		else sqrtFirstGuess = 32'sh00200000;

		// Newton's method - x(n+1) =(x(n) * (1.5 - (val * 0.5f * x(n)^2))
		
		// First iteration	
		sqrtIntermediate = FixedMul(sqrtFirstGuess, onePointFive - FixedMul(sqrtIn >>> 1, FixedMul(sqrtFirstGuess, sqrtFirstGuess)));
		
		// Second iteration
		sqrtRcpResult = FixedMul(sqrtIntermediate, onePointFive - FixedMul(sqrtIn >>> 1, FixedMul(sqrtIntermediate, sqrtIntermediate)));
		
		// Convert 1/sqrt(x) to sqrt(x)
		FixedSqrt = FixedMul(sqrtRcpResult, sqrtIn);
	end
endfunction

// Fast fixed-point recpriocal (abusing fast square root maths)
// Takes ~4 cycles

function automatic signed [31:0] FixedRcp;
	input signed [31:0] rcpIn; // Input
	reg signed [31:0] absRcpIn;
	reg signed [31:0] sqrtFirstGuess; // First guess (table-based)
	reg signed [31:0] sqrtIntermediate; // Result of first Newton iteration
	reg signed [31:0] sqrtRcpResult; // Result of second Newton iteration
	reg signed [31:0] absResult;
	begin	
		if (rcpIn == 32'h0) begin
			FixedRcp = 32'h7FFFFFFF; // Return largest possible number for 0
		end else begin
		
			// Strip sign
			absRcpIn = rcpIn[31] ? (-rcpIn) : rcpIn;
		
			// First-guess lookup based on number of leading zeroes
			
			if (absRcpIn[30]) sqrtFirstGuess = 32'sh00000034;
			else if (absRcpIn[29]) sqrtFirstGuess = 32'sh00000049;
			else if (absRcpIn[28]) sqrtFirstGuess = 32'sh00000068;
			else if (absRcpIn[27]) sqrtFirstGuess = 32'sh00000093;
			else if (absRcpIn[26]) sqrtFirstGuess = 32'sh000000d1;
			else if (absRcpIn[25]) sqrtFirstGuess = 32'sh00000127;
			else if (absRcpIn[24]) sqrtFirstGuess = 32'sh000001a2;
			else if (absRcpIn[23]) sqrtFirstGuess = 32'sh0000024f;
			else if (absRcpIn[22]) sqrtFirstGuess = 32'sh00000344;
			else if (absRcpIn[21]) sqrtFirstGuess = 32'sh0000049e;
			else if (absRcpIn[20]) sqrtFirstGuess = 32'sh00000688;
			else if (absRcpIn[19]) sqrtFirstGuess = 32'sh0000093c;
			else if (absRcpIn[18]) sqrtFirstGuess = 32'sh00000d10;
			else if (absRcpIn[17]) sqrtFirstGuess = 32'sh00001279;
			else if (absRcpIn[16]) sqrtFirstGuess = 32'sh00001a20;
			else if (absRcpIn[15]) sqrtFirstGuess = 32'sh000024f3;
			else if (absRcpIn[14]) sqrtFirstGuess = 32'sh00003441;
			else if (absRcpIn[13]) sqrtFirstGuess = 32'sh000049e6;
			else if (absRcpIn[12]) sqrtFirstGuess = 32'sh00006882;
			else if (absRcpIn[11]) sqrtFirstGuess = 32'sh000093cd;
			else if (absRcpIn[10]) sqrtFirstGuess = 32'sh0000d105;
			else if (absRcpIn[9]) sqrtFirstGuess = 32'sh0001279a;
			else if (absRcpIn[8]) sqrtFirstGuess = 32'sh0001a20b;
			else if (absRcpIn[7]) sqrtFirstGuess = 32'sh00024f34;
			else if (absRcpIn[6]) sqrtFirstGuess = 32'sh00034417;
			else if (absRcpIn[5]) sqrtFirstGuess = 32'sh00049e69;
			else if (absRcpIn[4]) sqrtFirstGuess = 32'sh0006882f;
			else if (absRcpIn[3]) sqrtFirstGuess = 32'sh00093cd3;
			else if (absRcpIn[2]) sqrtFirstGuess = 32'sh000d105e;
			else if (absRcpIn[1]) sqrtFirstGuess = 32'sh001279a7;
			else sqrtFirstGuess = 32'sh00200000;
			
			// Newton's method - x(n+1) =(x(n) * (1.5 - (val * 0.5f * x(n)^2))

			// First iteration	
			sqrtIntermediate = FixedMul(sqrtFirstGuess, onePointFive - FixedMul(absRcpIn >> 1, FixedMul(sqrtFirstGuess, sqrtFirstGuess)));
			
			// Second iteration
			sqrtRcpResult = FixedMul(sqrtIntermediate, onePointFive - FixedMul(absRcpIn >> 1, FixedMul(sqrtIntermediate, sqrtIntermediate)));
			
			// Convert 1/sqrt(x) to 1/x
			absResult = FixedMul(sqrtRcpResult, sqrtRcpResult);
			
			// Reapply sign
			FixedRcp = rcpIn[31] ? (-absResult) : absResult;
		end
	end
endfunction

// Truncate a signed 32-bit value to a 16-bit one, because Verilog

function automatic signed [15:0] TruncateSigned32To16;
	input signed [31:0] in;
	begin
		TruncateSigned32To16 = in[15:0];
	end
endfunction

// Fixed-point normalise
// Requires two cycles
task FixedNormalise;
	input signed [31:0] inX;
	input signed [31:0] inY;
	input signed [31:0] inZ;
	output signed [31:0] outX;
	output signed [31:0] outY;
	output signed [31:0] outZ;
	reg signed [31:0] lenSq;
	reg signed [31:0] rcpLen;
	begin	
		lenSq = FixedMul(inX, inX) + FixedMul(inY, inY) + FixedMul(inZ, inZ);
		rcpLen = FixedRcpSqrt(lenSq);
		outX = FixedMul(inX, rcpLen);
      outY = FixedMul(inY, rcpLen);
      outZ = FixedMul(inZ, rcpLen);		
	end
endtask

// Fixed-point normalise with 16 bit inputs/outputs
// Requires two cycles
task FixedNormalise16Bit;
	input signed [15:0] inX;
	input signed [15:0] inY;
	input signed [15:0] inZ;
	output signed [15:0] outX;
	output signed [15:0] outY;
	output signed [15:0] outZ;
	reg signed [15:0] lenSq;
	reg signed [15:0] rcpLen;
	begin	
		lenSq = 16'(FixedMul16x16(inX, inX)) + 16'(FixedMul(inY, inY)) + 16'(FixedMul(inZ, inZ));
		rcpLen = 16'(FixedRcpSqrt(lenSq));
		outX = 16'(FixedMul16x16(inX, rcpLen));
      outY = 16'(FixedMul16x16(inY, rcpLen));
      outZ = 16'(FixedMul16x16(inZ, rcpLen));
	end
endtask

// Colour multiplication (8 bit X 8 bit)
function automatic [7:0] ColourMul;
	input [7:0] x;
	input [7:0] y;
	begin
		// Extend out to 16 bits and then truncate again afterwards
		ColourMul = 8'(({ 8'h0, x } * { 8'h0, y }) >> 8);
	end
endfunction

// Colour addition (8 bit + 8 bit with saturation)
function automatic [7:0] ColourAdd;
	input [7:0] x;
	input [7:0] y;
	reg [8:0] intermediate;
	begin
		intermediate = { 1'h0, x } + { 1'h0, y };
		if (intermediate[8]) begin
			ColourAdd = 8'hFF; // Saturate
		end else begin
			ColourAdd = intermediate[7:0];
		end
	end
endfunction

endpackage : Maths