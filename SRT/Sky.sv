`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// Sky colour functionality

`default_nettype none

package Sky;

import Maths::*;

// Calculate sky colour
// Returns R in [7:0], G in [15:8], B in [23:16]
function automatic [23:0] GetSkyColour;
	input signed [15:0] rayDirX;
	input signed [15:0] rayDirY;
	input signed [15:0] rayDirZ;
	input signed [15:0] lightDirX;
	input signed [15:0] lightDirY;
	input signed [15:0] lightDirZ;
	reg signed [15:0] sunDot;
	reg signed [15:0] sunFactor;
	reg signed [15:0] sunFactor2;
	reg [7:0] sunCol;
	reg signed [15:0] skyLerp;
	reg [8:0] skyColRUnclamped;
	reg [8:0] skyColGUnclamped;
	reg [8:0] skyColBUnclamped;
	reg [7:0] skyColR;
	reg [7:0] skyColG;
	reg [7:0] skyColB;
	begin
		sunDot = FixedMul16x16(rayDirX, lightDirX) + FixedMul16x16(rayDirY, lightDirY) + FixedMul16x16(rayDirZ, lightDirZ);
		if (sunDot[15]) begin // Zero sun contribution if in shadow	
			 sunDot = 0;
		end
				
		sunFactor = FixedMul(sunDot, sunDot);
      sunFactor2 = FixedMul(sunFactor, sunFactor);

      sunCol = (sunFactor2 >> (fixedShift - (8 - 1))); // -1 to dial down the sun intensity a bit

      skyLerp = rayDirY + 16'sh00004000; // +1.0f

		if (skyLerp < 0) begin
			 skyLerp = 0;
		end

		skyColRUnclamped = ((24'd128 * 24'(skyLerp)) >> fixedShift) + sunCol;
      skyColGUnclamped = ((24'd128 * 24'(skyLerp)) >> fixedShift) + sunCol;
      skyColBUnclamped = 9'd190 + sunCol;

		skyColR = skyColRUnclamped[8] ? 255 : skyColRUnclamped[7:0];
		skyColG = skyColGUnclamped[8] ? 255 : skyColGUnclamped[7:0];
		skyColB = skyColBUnclamped[8] ? 255 : skyColBUnclamped[7:0];
		
		GetSkyColour = { skyColB, skyColG, skyColR };
	end
endfunction

endpackage : Sky