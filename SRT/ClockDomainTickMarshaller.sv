`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// This marshals a tick signal between clock domains
// Assumes that ticks do not occur at a frequency greater than four(?) cycles of the slower of inClock and outClock 

module ClockDomainTickMarshaller(
	input wire inClock,
	input wire outClock,
	input wire reset,
	
	input wire inTick,
	output wire outTick	
);

// Input clock domain logic
reg srcTick; // Source tick that is passed to output domain
reg [1:0] srcResetFIFO; // FIFO for clock domain synchronisation
reg lastInTick; // Previous inTick value

always @(posedge inClock) begin
	if (reset) begin
		srcTick <= 'h0;
		srcResetFIFO <= 'h0;
		lastInTick <= 'h0;
	end else begin
		srcResetFIFO <= { srcResetFIFO[0], destReset };
		lastInTick <= inTick;
	
		if (srcResetFIFO[1]) begin // Reset has been requested
			srcTick <= 0;
		end else	if (inTick && !lastInTick) begin // Set srcTick on rising edge of inTick
			srcTick <= 1;
		end
	end
end

// Output clock domain logic
reg destReset; // Goes high when the output logic has handled the tick signal
reg [2:0] destTickFIFO; // FIFO for clock domain synchronisation, with a bonus bit to keep the previous tick state in

always @(posedge outClock) begin
	if (reset) begin
		outTick <= 0;
		destReset <= 0;
		destTickFIFO <= 'h0;
	end else begin
		destTickFIFO <= { destTickFIFO[1:0], srcTick };
		
		destReset <= destTickFIFO[1]; // Signal the reset line when we get a tick
	
		outTick <= (destTickFIFO[2:1] == 2'b01); // Output on rising edge of srcTick	
	end
end

endmodule