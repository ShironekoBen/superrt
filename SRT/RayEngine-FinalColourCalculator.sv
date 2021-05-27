// SuperRT by Ben Carter (c) 2021
// Calculates the final blended pixel colour

reg [7:0] finalColourCalculator_R;
reg [7:0] finalColourCalculator_G;
reg [7:0] finalColourCalculator_B;

reg [7:0] fcc_PrimaryHitReflectiveness;
reg [7:0] fcc_InvPrimaryHitReflectiveness;

always @(*) begin
	if (regPrimaryHit) begin
		fcc_PrimaryHitReflectiveness = regPrimaryHitReflectiveness;
		fcc_InvPrimaryHitReflectiveness = 8'hFF - regPrimaryHitReflectiveness;
	end else begin
		// If there was no hit, then reflectiveness is effectively 0
		fcc_PrimaryHitReflectiveness = 8'h00;
		fcc_InvPrimaryHitReflectiveness = 8'hFF;
	end	
end

// Dither pattern ROM

reg [3:0] fcc_ditherPattern;

DitherPatternROM fcc_DitherPatternROM_inst(
	.x(pixelX[0]),
	.y(pixelY[1:0]),
	.pixel(fcc_ditherPattern)
);

always @(*) begin
	finalColourCalculator_R = ColourAdd(ColourAdd(ColourMul(primaryRayColourR, fcc_InvPrimaryHitReflectiveness), ColourMul(secondaryRayColourR, fcc_PrimaryHitReflectiveness)), fcc_ditherPattern);
	finalColourCalculator_G = ColourAdd(ColourAdd(ColourMul(primaryRayColourG, fcc_InvPrimaryHitReflectiveness), ColourMul(secondaryRayColourG, fcc_PrimaryHitReflectiveness)), fcc_ditherPattern);
	finalColourCalculator_B = ColourAdd(ColourAdd(ColourMul(primaryRayColourB, fcc_InvPrimaryHitReflectiveness), ColourMul(secondaryRayColourB, fcc_PrimaryHitReflectiveness)), fcc_ditherPattern);
`ifdef ENABLE_TINT_PIXEL
	finalColourCalculator_R = ColourAdd((finalColourCalculator_R >> 2), (pixelTintR >> 1));
	finalColourCalculator_G = ColourAdd((finalColourCalculator_G >> 2), (pixelTintG >> 1));
	finalColourCalculator_B = ColourAdd((finalColourCalculator_B >> 2), (pixelTintB >> 1));
`endif
end
