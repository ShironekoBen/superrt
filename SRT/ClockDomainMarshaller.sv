`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// This marshals a bus between clock domains, deliberately introducing enough latency so that
// timing matches ClockDomainTickMarshaller

module ClockDomainMarshaller#(
	BUS_WIDTH = 1
)(
	input wire inClock,
	input wire outClock,
	input wire reset,
	
	input wire [BUS_WIDTH-1:0] inData,
	output wire [BUS_WIDTH-1:0] outData
);

// Input clock domain logic
reg [BUS_WIDTH-1:0] srcData; // Source data that is passed to output domain

always @(posedge inClock) begin
	if (reset) begin
		srcData <= 'h0;
	end else begin
		srcData <= inData;
	end
end

// Output clock domain logic
reg [BUS_WIDTH-1:0] destDataFIFO[1:0]; // FIFO for clock domain synchronisation, with a bonus bit to keep the previous data in

always @(posedge outClock) begin
	if (reset) begin
		destDataFIFO[0] <= 'h0;
		destDataFIFO[1] <= 'h0;
	end else begin
		destDataFIFO[1] <= destDataFIFO[0];
		destDataFIFO[0] <= srcData;
		
		outData <= destDataFIFO[1];
	end
end

endmodule