`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// Debounce an input from our (debug) joypad and turn it into a single pressed/released tick

module JoypadInputHandler(
	input wire clock,
	input wire reset,
	
	input wire inPressed,
	output wire outPressed, // 1 all the time the button is pressed
	output wire outPressed_tick // 1 for one cycle when the button goes down
);

// Debounce

reg [31:0] testTimer; // Time intervals between joypad samples
reg [15:0] joypadHistory;

always @(posedge clock) begin
	if (reset) begin
		joypadHistory <= 4'h0;
		outPressed <= 0;
		testTimer <= 'd0;
	end else begin
		if (testTimer > 0) begin
			testTimer <= testTimer - 1;
		end else begin	
			testTimer <= 'd500000; // About 1/100 of a second at 50Mhz, which means our debounce buffer covers about 0.16s
			joypadHistory[15:1] <= joypadHistory[14:0];
			joypadHistory[0] <= ~inPressed; // Invert because input is active low
		end
		if (joypadHistory == 16'hFFFF) begin
			outPressed <= 1;
		end else if (joypadHistory == 4'h0) begin
			outPressed <= 0;
		end
	end
end

// Press detection

reg oldPressed;

always @(posedge clock) begin
	if (reset) begin
		oldPressed <= 0;
		outPressed_tick <= 0;
	end else begin
		if (outPressed && (~oldPressed)) begin
			outPressed_tick <= 1;
		end else begin
			outPressed_tick <= 0;
		end
		oldPressed <= outPressed;
	end
end

endmodule