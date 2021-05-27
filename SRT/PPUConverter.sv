`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// PPU image data conversion

`default_nettype none

module PPUConverter(
	input wire clock,
	input wire reset,
	output wire active,
	
	// Triggers
	input wire start_tick,
	output wire done_tick,
	
	// Source data RAM access
	output wire [14:0] inReadAddress,
	input wire [15:0] inReadData,
	input wire inReadOK,
	
	// Output to the SNES framebuffer RAM
	output wire [14:0] outWriteAddress,
	output wire outWriteEN,
	output reg [7:0] outWriteData,
	
	// Debug
	output wire [63:0] debug
);

reg [7:0] paletteIndex;

// Palette map ROM
PaletteMapROM PaletteMapROM_inst(
	.address(inReadData),
	.clock(clock),
	.q(paletteIndex)
);


reg [14:0] currentReadPixel; // Linear pixel index we are reading
reg [14:0] currentWritePixel; // Linear pixel index (*not* address) we are writing

reg [4:0] currentTileX; // Which tile are we on in the current row? (0-24)
reg [2:0] y; // Which Y are we on within the tile? (0-7)
reg [8:0] rowStartTileIndex; // Row index at the start of this row (0-500)
reg [8:0] currentTileIndex; // Current overall tile index (0-500)

// We work in 8 pixel strips as that's the natural swizzle unit for the bitplanes
// Index 0 is the right-most (last in RAM) pixel in this scheme, 7 the left-most (first in RAM)
reg [7:0] srcPixels[7:0]; // Source data, 8bpp linear
reg [7:0] destPixels[7:0]; // Destination data, 8bpp SNES bitplane format

// We always shift out from index 7 (the left-most pixel)
assign outWriteData = destPixels[7];

always @(*) begin
	// We have to swizzle the write address to account for the PPU data layout
	
	// For arbitrary-sized buffer, with C as the tile index

	// X0 => Bit 0
	// X1 => Bit 4
	// X2 => Bit 5
	// C0 => Bit 6
	// C1 => Bit 7
	// C2 => Bit 8
	// C3 => Bit 9
	// Y0 => Bit 1
	// Y1 => Bit 2
	// Y2 => Bit 3
	// C4 => Bit 10
	// C5 => Bit 11
	// C6 => Bit 12
	// C7 => Bit 13
	// C8 => Bit 14
	
	// ...or:
	
	// Bit 0 = X0
	// Bit 1 = Y0
	// Bit 2 = Y1
	// Bit 3 = Y2
	// Bit 4 = X1
	// Bit 5 = X2
	// Bit 6 = C0
	// Bit 7 = C1
	// Bit 8 = C2
	// Bit 9 = C3
	// Bit 10 = C4
	// Bit 11 = C5
	// Bit 12 = C6
	// Bit 13 = C7
	// Bit 14 = C8
	
	// We can get X from the bottom 3 bits of currentWritePixel

	outWriteAddress <= { currentTileIndex[8],   // C8
								currentTileIndex[7],   // C7
								currentTileIndex[6],   // C6
								currentTileIndex[5],   // C5
								currentTileIndex[4],   // C4
								currentTileIndex[3],   // C3
								currentTileIndex[2],   // C2
								currentTileIndex[1],   // C1
								currentTileIndex[0],   // C0
								currentWritePixel[2],  // X2
								currentWritePixel[1],  // X1
								y[2],                  // Y2
								y[1],                  // Y1
								y[0],                  // Y0
								currentWritePixel[0] };// X0
end

always @(*) begin
	inReadAddress <= currentReadPixel;
end

always @(*) debug = { 16'(currentPhase), debugConversionCount, 16'(currentReadPixel), 16'(currentWritePixel) };

typedef enum
{
	CP_Start = 0,
	CP_ReadPixelWait,
	CP_ReadPixelWait2,
	CP_ReadPixelWait3,
	CP_ReadPixelWait4,
	CP_ReadPixel,
	CP_ReadPixel2,
	CP_Convert,
	CP_WritePixel,
	CP_WriteWait0,
	CP_WriteWait1
} ConversionPhase;

ConversionPhase currentPhase;
ConversionPhase nextPhase;

always @(posedge clock or posedge reset) begin

	if (reset) begin
		done_tick <= 0;
		currentReadPixel <= 0;
		currentWritePixel <= 0;
		outWriteEN <= 0;
		nextPhase <= CP_Start;
		active <= 0;
		//debug <= 64'hC0DEC0DEC0DEC0DE;
		currentTileX <= 0;
		y <= 0;
		rowStartTileIndex <= 0;
		currentTileIndex <= 0;
	end else begin
		done_tick <= 0;
		outWriteEN <= 0;
		active <= 1;
	
		case (currentPhase)
			CP_Start: begin
				currentReadPixel <= 0;
				currentWritePixel <= 0;
				outWriteEN <= 0;
				currentTileX <= 0;
				y <= 0;
				rowStartTileIndex <= 0;
				currentTileIndex <= 0;
				
				// Wait for start trigger
				if (start_tick) begin
					nextPhase <= currentPhase.next;
				end else begin
					active <= 0;
					nextPhase <= currentPhase;
				end
			end
			CP_ReadPixelWait: begin
				// Wait for OK signal to indicate we can read from the framebuffer RAM
				if (inReadOK) begin
					nextPhase <= currentPhase.next;
				end
			end
			CP_ReadPixelWait2: begin
				nextPhase <= currentPhase.next;
			end
			CP_ReadPixelWait3: begin
				nextPhase <= currentPhase.next;
			end
			CP_ReadPixelWait4: begin
				nextPhase <= currentPhase.next;
			end			
			CP_ReadPixel: begin
				// Shift pixel into src data
				srcPixels[7] <= srcPixels[6];
				srcPixels[6] <= srcPixels[5];
				srcPixels[5] <= srcPixels[4];
				srcPixels[4] <= srcPixels[3];
				srcPixels[3] <= srcPixels[2];
				srcPixels[2] <= srcPixels[1];
				srcPixels[1] <= srcPixels[0];
				// Convert to 8bpp as we shift in
				srcPixels[0] <= paletteIndex;
								
				nextPhase <= currentPhase.next;
			end	
			CP_ReadPixel2: begin // Fixme: This is redundant
				// Move to next pixel
				currentReadPixel <= currentReadPixel + 15'd1;
				
				if (currentReadPixel[2:0] == 7) begin
					nextPhase <= currentPhase.next;
				end else begin
					// More pixels to process
					nextPhase <= CP_ReadPixelWait;
				end
			end
			CP_Convert: begin
				// Turn into bitplane format (this is essentially a transpose of the source data)
				destPixels[7] <= { srcPixels[7][0], srcPixels[6][0], srcPixels[5][0], srcPixels[4][0], srcPixels[3][0], srcPixels[2][0], srcPixels[1][0], srcPixels[0][0] };
				destPixels[6] <= { srcPixels[7][1], srcPixels[6][1], srcPixels[5][1], srcPixels[4][1], srcPixels[3][1], srcPixels[2][1], srcPixels[1][1], srcPixels[0][1] };
				destPixels[5] <= { srcPixels[7][2], srcPixels[6][2], srcPixels[5][2], srcPixels[4][2], srcPixels[3][2], srcPixels[2][2], srcPixels[1][2], srcPixels[0][2] };
				destPixels[4] <= { srcPixels[7][3], srcPixels[6][3], srcPixels[5][3], srcPixels[4][3], srcPixels[3][3], srcPixels[2][3], srcPixels[1][3], srcPixels[0][3] };
				destPixels[3] <= { srcPixels[7][4], srcPixels[6][4], srcPixels[5][4], srcPixels[4][4], srcPixels[3][4], srcPixels[2][4], srcPixels[1][4], srcPixels[0][4] };
				destPixels[2] <= { srcPixels[7][5], srcPixels[6][5], srcPixels[5][5], srcPixels[4][5], srcPixels[3][5], srcPixels[2][5], srcPixels[1][5], srcPixels[0][5] };
				destPixels[1] <= { srcPixels[7][6], srcPixels[6][6], srcPixels[5][6], srcPixels[4][6], srcPixels[3][6], srcPixels[2][6], srcPixels[1][6], srcPixels[0][6] };
				destPixels[0] <= { srcPixels[7][7], srcPixels[6][7], srcPixels[5][7], srcPixels[4][7], srcPixels[3][7], srcPixels[2][7], srcPixels[1][7], srcPixels[0][7] };										
				
				nextPhase <= currentPhase.next;
			end
			CP_WritePixel: begin			
				outWriteEN <= 1;
				nextPhase <= currentPhase.next;
			end
			CP_WriteWait0: begin
				nextPhase <= currentPhase.next;
			end
			CP_WriteWait1: begin
				// Shift the output data
				
				destPixels[7] <= destPixels[6];
				destPixels[6] <= destPixels[5];
				destPixels[5] <= destPixels[4];
				destPixels[4] <= destPixels[3];
				destPixels[3] <= destPixels[2];
				destPixels[2] <= destPixels[1];
				destPixels[1] <= destPixels[0];
				
				// Move to next pixel
				currentWritePixel <= currentWritePixel + 15'd1;
				
				if (currentWritePixel[2:0] == 7) begin
					// End of one 8 pixel chunk
					
					if (currentTileX == (25 - 1)) begin
						// End of one line of pixels
						
						currentTileX <= 0;
					
						if (y == 7) begin
							// Bottom of one complete row of tiles

							if (currentTileIndex == ((25 * 20) - 1)) begin
								// Finished the whole image, so go back to start and wait to run again
								nextPhase <= CP_Start;
								done_tick <= 1;
							end else begin
								// More rows of tiles to do
								y <= 0;
								rowStartTileIndex <= currentTileIndex + 1;
								currentTileIndex <= currentTileIndex + 1;
								nextPhase <= CP_ReadPixelWait;		
							end
						end else begin
							// Move to the next pixel line in this row of tiles
							y <= y + 1;
							currentTileIndex <= rowStartTileIndex;
							nextPhase <= CP_ReadPixelWait;		
						end
					end else begin
						// Still in the middle of the line
						currentTileX <= currentTileX + 1;
						currentTileIndex <= currentTileIndex + 1;
						nextPhase <= CP_ReadPixelWait;
					end				
				end else begin
					// More pixels to process in this batch
					nextPhase <= CP_WritePixel;
				end
			end
			default: begin
				nextPhase <= CP_Start;	
			end
		endcase
	end
end

always @(negedge clock or posedge reset) begin
	if (reset) begin
		currentPhase <= CP_Start;
	end else begin
		currentPhase <= nextPhase;
	end
end

// Count how many conversions we have completed

reg [15:0] debugConversionCount;
reg [15:0] nextDebugConversionCount;
always @(*) nextDebugConversionCount <= debugConversionCount + 16'd1;

always @(posedge clock or posedge reset) begin
	if (reset) begin
		debugConversionCount <= 0;
	end else begin
		if (done_tick) begin
			debugConversionCount <= nextDebugConversionCount;
		end
	end
end

endmodule