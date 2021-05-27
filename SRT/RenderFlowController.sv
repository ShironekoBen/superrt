`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// Handles the high level flow of the rendering process

module RenderFlowController(
	// Fundamentals
	input wire reset,
	input wire clock,
	
	// Main trigger
	input wire startRequest_tick,
	output wire done_tick,
	
	// Sub-triggers
	output wire frameStart_tick,
	output wire startRenderer_tick,
	input wire rendererDone_tick,
	output wire startPPUConverter_tick,
	input wire ppuConverterDone_tick,
	
	// Performance
	output wire [31:0] lastTotalCycleCount,
	output wire [31:0] lastRenderCycleCount,
	output wire [31:0] lastPPUConversionCycleCount,
	
	// Status
	output wire busy,
	
	// Debug
	output wire [63:0] debug
);

typedef enum
{
	P_Start = 0,
	P_FrameStart,
	P_Rendering,
	P_PPUConversion,
	P_Finishing
} Phase;

Phase currentPhase;

reg [31:0] frameCount;

// Performance counters

reg [31:0] currentTotalCycleCount;
reg [31:0] currentRenderCycleCount;
reg [31:0] currentPPUConversionCycleCount;

assign debug = { frameCount, 32'(currentPhase) };

always @(posedge clock or posedge reset) begin
	if (reset) begin
		frameCount <= 0;
		currentPhase <= P_Start;
		frameStart_tick <= 0;
		startRenderer_tick <= 0;
		startPPUConverter_tick <= 0;
		done_tick <= 0;
		currentTotalCycleCount <= 0;
		currentRenderCycleCount <= 0;
		currentPPUConversionCycleCount <= 0;
		lastTotalCycleCount <= 0;
		lastRenderCycleCount <= 0;
		lastPPUConversionCycleCount <= 0;
		busy <= 1;
	end else begin
		frameStart_tick <= 0;
		startRenderer_tick <= 0;
		startPPUConverter_tick <= 0;
		done_tick <= 0;
		currentTotalCycleCount <= currentTotalCycleCount + 1;
		busy <= 1;
	
		case (currentPhase)
			P_Start: begin
				// Wait for start trigger
				
				currentTotalCycleCount <= 0;
				currentRenderCycleCount <= 0;
				currentPPUConversionCycleCount <= 0;				
				
				if (startRequest_tick) begin
					// Notify everyone of the frame start
					frameStart_tick <= 1;
					currentPhase <= currentPhase.next;				
				end else begin
					busy <= 0; // This is the only state when we are not considered busy
				end
			end
			P_FrameStart: begin
				// Start renderer					
				startRenderer_tick <= 1;
				currentPhase <= currentPhase.next;
			end
			P_Rendering: begin
				currentRenderCycleCount <= currentRenderCycleCount + 1;
				if (rendererDone_tick) begin
					// Start PPU conversion
					startPPUConverter_tick <= 1;
					currentPhase <= currentPhase.next;
				end
			end
			P_PPUConversion: begin
				currentPPUConversionCycleCount <= currentPPUConversionCycleCount + 1;
				if (ppuConverterDone_tick) begin
					currentPhase <= currentPhase.next;
				end
			end
			P_Finishing: begin
			
				lastTotalCycleCount <= currentTotalCycleCount;
				lastRenderCycleCount <= currentRenderCycleCount;
				lastPPUConversionCycleCount <= currentPPUConversionCycleCount;
			
				frameCount <= frameCount + 1;
				done_tick <= 1;
				currentPhase <= P_Start;
			end		
			default: begin
				currentPhase <= P_Start;	
			end
		endcase
	end
end

endmodule