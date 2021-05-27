// SuperRT by Ben Carter (c) 2021
// Calculates the secondary ray (shadow/reflection) direction

reg signed [31:0] secondaryRayDirectionCalculator_ShadowRayStartX;
reg signed [31:0] secondaryRayDirectionCalculator_ShadowRayStartY;
reg signed [31:0] secondaryRayDirectionCalculator_ShadowRayStartZ;
reg signed [15:0] secondaryRayDirectionCalculator_ShadowRayDirX;
reg signed [15:0] secondaryRayDirectionCalculator_ShadowRayDirY;
reg signed [15:0] secondaryRayDirectionCalculator_ShadowRayDirZ;

reg signed [31:0] secondaryRayDirectionCalculator_ReflectionRayStartX;
reg signed [31:0] secondaryRayDirectionCalculator_ReflectionRayStartY;
reg signed [31:0] secondaryRayDirectionCalculator_ReflectionRayStartZ;
reg signed [15:0] secondaryRayDirectionCalculator_ReflectionRayDirX;
reg signed [15:0] secondaryRayDirectionCalculator_ReflectionRayDirY;
reg signed [15:0] secondaryRayDirectionCalculator_ReflectionRayDirZ;

reg signed [15:0] SRDC_NormalDotRay;

always @(*) begin

	// Shadow ray

	secondaryRayDirectionCalculator_ShadowRayStartX = (currentPhaseIsPrimary ? regPrimaryHitX : regSecondaryHitX) + (lightDirX >>> secondaryRayBiasShift);
	secondaryRayDirectionCalculator_ShadowRayStartY = (currentPhaseIsPrimary ? regPrimaryHitY : regSecondaryHitY) + (lightDirY >>> secondaryRayBiasShift);
	secondaryRayDirectionCalculator_ShadowRayStartZ = (currentPhaseIsPrimary ? regPrimaryHitZ : regSecondaryHitZ) + (lightDirZ >>> secondaryRayBiasShift);
	secondaryRayDirectionCalculator_ShadowRayDirX = lightDirX;
	secondaryRayDirectionCalculator_ShadowRayDirY = lightDirY;
	secondaryRayDirectionCalculator_ShadowRayDirZ = lightDirZ;

	// Reflection ray

	secondaryRayDirectionCalculator_ReflectionRayStartX = regPrimaryHitX + (regPrimaryHitNormalX >>> secondaryRayBiasShift);
	secondaryRayDirectionCalculator_ReflectionRayStartY = regPrimaryHitY + (regPrimaryHitNormalY >>> secondaryRayBiasShift);
	secondaryRayDirectionCalculator_ReflectionRayStartZ = regPrimaryHitZ + (regPrimaryHitNormalZ >>> secondaryRayBiasShift);

	SRDC_NormalDotRay = 16'(FixedMul16x16(primaryRayDirX, regPrimaryHitNormalX)) + 16'(FixedMul16x16(primaryRayDirY, regPrimaryHitNormalY)) + 16'(FixedMul16x16(primaryRayDirZ, regPrimaryHitNormalZ));

	secondaryRayDirectionCalculator_ReflectionRayDirX = primaryRayDirX - 16'(FixedMul16x16(regPrimaryHitNormalX, SRDC_NormalDotRay) <<< 1);
	secondaryRayDirectionCalculator_ReflectionRayDirY = primaryRayDirY - 16'(FixedMul16x16(regPrimaryHitNormalY, SRDC_NormalDotRay) <<< 1);
	secondaryRayDirectionCalculator_ReflectionRayDirZ = primaryRayDirZ - 16'(FixedMul16x16(regPrimaryHitNormalZ, SRDC_NormalDotRay) <<< 1);
	
end
