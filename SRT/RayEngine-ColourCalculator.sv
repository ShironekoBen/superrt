// SuperRT by Ben Carter (c) 2021
// Calculates the colour for the current ray

import Sky::*;

reg [7:0] colourCalculator_RayR;
reg [7:0] colourCalculator_RayG;
reg [7:0] colourCalculator_RayB;

localparam signed [15:0] maxIllumination = 16'sh3FFF; // Very slightly less than 1.0f, because 1.0f exactly becomes 256 and overflows our 8-bit maths

// Current base illumination level
reg signed [15:0] cc_BaseIllumination;
reg signed [15:0] cc_BaseIlluminationClamped;

always @(*) begin
	cc_BaseIllumination = 16'(FixedMul16x16(currentPhaseIsPrimary ? regPrimaryHitNormalX : regSecondaryHitNormalX, lightDirX)) + 
							    16'(FixedMul16x16(currentPhaseIsPrimary ? regPrimaryHitNormalY : regSecondaryHitNormalY, lightDirY)) +
							    16'(FixedMul16x16(currentPhaseIsPrimary ? regPrimaryHitNormalZ : regSecondaryHitNormalZ, lightDirZ));
								 
	cc_BaseIlluminationClamped = (cc_BaseIllumination > maxIllumination) ? maxIllumination : cc_BaseIllumination;
end
													 
// Illumination modulated by shadowing/etc, in 0-255 range												 
reg [7:0] cc_Illumination;

always @(*) begin
	if (cc_BaseIlluminationClamped < 0) begin
		// Anti-light
		cc_Illumination = 8'(((-cc_BaseIlluminationClamped) >> 2) >> (fixedShift - 8));
	end else if (currentPhaseIsPrimary ? regPrimaryShadowHit : regSecondaryShadowHit) begin
		// Shadowed
		cc_Illumination = 8'((cc_BaseIlluminationClamped >> 3) >> (fixedShift - 8));
	end else begin
		cc_Illumination = 8'(cc_BaseIlluminationClamped >> (fixedShift - 8));
	end
end

// Specular contribution

reg signed [15:0] cc_NormalDotRay;

always @(*) begin
	cc_NormalDotRay = (FixedMul16x16(primaryRayDirX, regPrimaryHitNormalX) + FixedMul16x16(primaryRayDirY, regPrimaryHitNormalY) + FixedMul16x16(primaryRayDirZ, regPrimaryHitNormalZ));
end

reg signed [15:0] cc_SpecDirX;
reg signed [15:0] cc_SpecDirY;
reg signed [15:0] cc_SpecDirZ;

always @(*) begin
	cc_SpecDirX = primaryRayDirX - 16'(FixedMul16x16(regPrimaryHitNormalX, cc_NormalDotRay) <<< 1);
	cc_SpecDirY = primaryRayDirY - 16'(FixedMul16x16(regPrimaryHitNormalY, cc_NormalDotRay) <<< 1);
	cc_SpecDirZ = primaryRayDirZ - 16'(FixedMul16x16(regPrimaryHitNormalZ, cc_NormalDotRay) <<< 1);
end

reg signed [15:0] cc_SpecDot;

always @(*) begin
	cc_SpecDot = 16'(FixedMul16x16(cc_SpecDirX, lightDirX)) + 16'(FixedMul16x16(cc_SpecDirY, lightDirY)) + 16'(FixedMul16x16(cc_SpecDirZ, lightDirZ));
end

reg signed [15:0] cc_SpecDotClamped;

always @(*) begin
	cc_SpecDotClamped = (cc_SpecDot < 0) ? 16'h0 : ((cc_SpecDot > maxIllumination) ? maxIllumination : cc_SpecDot);
end

// Power terms

reg signed [15:0] cc_SpecIlluminationA;

always @(*) begin
	cc_SpecIlluminationA = FixedMul16x16(cc_SpecDotClamped, cc_SpecDotClamped);
end

reg signed [15:0] cc_SpecIlluminationB;

always @(*) begin
	cc_SpecIlluminationB = FixedMul16x16(cc_SpecIlluminationA, cc_SpecIlluminationA);
end

reg signed [15:0] cc_SpecIlluminationC;

always @(*) begin
	cc_SpecIlluminationC = 16'(FixedMul16x16(cc_SpecIlluminationB, cc_SpecIlluminationB));
end

// Final specular term as an 8-bit value
reg [7:0] cc_SpecIllumination;

always @(*) begin
if (cc_BaseIlluminationClamped < 0) begin
		// Facing away from light
		cc_SpecIllumination = 8'h00;
	end else if (currentPhaseIsPrimary ? regPrimaryShadowHit : regSecondaryShadowHit) begin
		// Shadowed
		cc_SpecIllumination = 8'h00;
	end else begin
		cc_SpecIllumination = 8'(cc_SpecIlluminationC >> (fixedShift - 8));
	end
end

// Extract albedo colour components

reg [7:0] cc_AlbedoR;
reg [7:0] cc_AlbedoG;
reg [7:0] cc_AlbedoB;

always @(*) begin
	if (currentPhaseIsPrimary) begin
		cc_AlbedoR = regPrimaryHitAlbedo[4:0] << 3;
		cc_AlbedoG = regPrimaryHitAlbedo[9:5] << 3;
		cc_AlbedoB = regPrimaryHitAlbedo[15:10] << 3;
	end else begin
		cc_AlbedoR = regSecondaryHitAlbedo[4:0] << 3;
		cc_AlbedoG = regSecondaryHitAlbedo[9:5] << 3;
		cc_AlbedoB = regSecondaryHitAlbedo[15:10] << 3;
	end
end

// Sky colour

reg signed [23:0] cc_skyColour;

always @(*) begin
	cc_skyColour = GetSkyColour(rayDirX, rayDirY, rayDirZ, lightDirX, lightDirY, lightDirZ);
end

// Colour calculation

always @(*) begin	
	if (currentPhaseIsPrimary ? regPrimaryHit : regSecondaryHit) begin
		colourCalculator_RayR = ColourAdd(ColourMul(cc_AlbedoR, cc_Illumination), cc_SpecIllumination);
      colourCalculator_RayG = ColourAdd(ColourMul(cc_AlbedoG, cc_Illumination), cc_SpecIllumination);
      colourCalculator_RayB = ColourAdd(ColourMul(cc_AlbedoB, cc_Illumination), cc_SpecIllumination);
	end else begin
		// No hit, so sky colour
		colourCalculator_RayR = cc_skyColour[7:0];
		colourCalculator_RayG = cc_skyColour[15:8];
		colourCalculator_RayB = cc_skyColour[23:16];		
	end
end