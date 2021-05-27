// SuperRT by Ben Carter (c) 2021
// Calculates ray-sphere and ray-plane intersections

reg signed [31:0] c14_raySphere_EntryDepth;
reg signed [31:0] c14_raySphere_ExitDepth;
reg signed [15:0] c14_raySphere_EntryNormalX;
reg signed [15:0] c14_raySphere_EntryNormalY;
reg signed [15:0] c14_raySphere_EntryNormalZ;
reg signed [15:0] c14_raySphere_ExitNormalX;
reg signed [15:0] c14_raySphere_ExitNormalY;
reg signed [15:0] c14_raySphere_ExitNormalZ;

reg signed [31:0] c14_rayPlane_EntryDepth;
reg signed [31:0] c14_rayPlane_ExitDepth;
reg signed [15:0] c14_rayPlane_EntryNormalX;
reg signed [15:0] c14_rayPlane_EntryNormalY;
reg signed [15:0] c14_rayPlane_EntryNormalZ;
reg signed [15:0] c14_rayPlane_ExitNormalX;
reg signed [15:0] c14_rayPlane_ExitNormalY;
reg signed [15:0] c14_rayPlane_ExitNormalZ;

// Calculate 1/(radius or denominator) in parallel, taking 4 cycles
// This is shared by both the sphere and plane logic
// This is also exposed externally for use by RayEngine with the ExecEngine is idle
wire signed [31:0] c9_rs_rcpIn;
reg signed [31:0] c13_rs_rcpResult;
FixedRcpClocked rs_rcpInst(
	.clock(clock),
	.rcpIn(x_busy ? c9_rs_rcpIn : x_rcpIn),
	.result(c13_rs_rcpResult)
);

assign x_rcpOut = c13_rs_rcpResult; // Expose result externally

// Calculate sqrt(distance) in parallel, taking 4 cycles
wire [31:0] c5_rs_sqrtIn;
reg [31:0] rs_sqrtResult;
FixedSqrtClocked rs_sqrtInst(
	.clock(clock),
	.sqrtIn(c5_rs_sqrtIn),
	.result(rs_sqrtResult)
);

// Cycle 2
always @(posedge clock) begin 
	c3_rs_objXRaw <= ConvertFrom8dot7(c2_instructionWord[22:8]);
	c3_rs_objYRaw <= ConvertFrom8dot7(c2_instructionWord[37:23]);
	c3_rs_objZRaw <= ConvertFrom8dot7(c2_instructionWord[52:38]);
	c3_rs_objRad <= ConvertFrom4dot7(c2_instructionWord[63:53]);
	
	c3_rp_objNormalX <= ConvertFrom2dot10(c2_instructionWord[19:8]);
	c3_rp_objNormalY <= ConvertFrom2dot10(c2_instructionWord[31:20]);
	c3_rp_objNormalZ <= ConvertFrom2dot10(c2_instructionWord[43:32]);
	c3_rp_objNormalDist <= ConvertFrom8dot12(c2_instructionWord[63:44]);		
end
	
reg signed [31:0] c3_rs_objXRaw; // Raw just to indicate the fact that origin hasn't been applied yet
reg signed [31:0] c3_rs_objYRaw;
reg signed [31:0] c3_rs_objZRaw;
reg signed [31:0] c3_rs_objRad;

reg signed [15:0] c3_rp_objNormalX;
reg signed [15:0] c3_rp_objNormalY;
reg signed [15:0] c3_rp_objNormalZ;
reg signed [31:0] c3_rp_objNormalDist;
	
// Cycle 3
always @(posedge clock) begin
	reg signed [31:0] ocX;
	reg signed [31:0] ocY;
	reg signed [31:0] ocZ;
	reg signed [31:0] mulResult0;
	reg signed [31:0] mulResult1;
	reg signed [31:0] mulResult2;
	reg isSphere;
	
	isSphere = c3_instructionWord[0]; // See Instruction enum for details	

	// Perform sphere intersection

	ocX = u_rayStartX - (c3_rs_objXRaw + s3_originX); // Delta from ray start point to sphere
   ocY = u_rayStartY - (c3_rs_objYRaw + s3_originY);
   ocZ = u_rayStartZ - (c3_rs_objZRaw + s3_originZ);
	
	// Multiplexed multiply to save a little bit of logic
	
	mulResult0 = FixedMul(isSphere ? ocX : c3_rp_objNormalX, isSphere ? u_rayDirX : c3_rp_objNormalDist);
   mulResult1 = FixedMul(isSphere ? ocY : c3_rp_objNormalY, isSphere ? u_rayDirY : c3_rp_objNormalDist);
	mulResult2 = FixedMul(isSphere ? ocZ : c3_rp_objNormalZ, isSphere ? u_rayDirZ : c3_rp_objNormalDist);

	// Distance along the ray to the closest point in the sphere
	
   c4_rs_closestPointAlongRay <= -(mulResult0 + mulResult1 + mulResult2);
   c4_rs_sphereToRayStartDistSq <= FixedMul(ocX, ocX) + FixedMul(ocY, ocY) + FixedMul(ocZ, ocZ);
   c4_rs_radiusSq <= FixedMul(c3_rs_objRad, c3_rs_objRad);
	
	c4_rs_objX <= c3_rs_objXRaw + s3_originX;
	c4_rs_objY <= c3_rs_objYRaw + s3_originY;
	c4_rs_objZ <= c3_rs_objZRaw + s3_originZ;
	c4_rs_objRad <= c3_rs_objRad;
	
	c4_rp_pointOnPlaneX <= mulResult0 + s3_originX;
	c4_rp_pointOnPlaneY <= mulResult1 + s3_originY;
	c4_rp_pointOnPlaneZ <= mulResult2 + s3_originZ;
	
	c4_rp_objNormalX <= c3_rp_objNormalX;
	c4_rp_objNormalY <= c3_rp_objNormalY;
	c4_rp_objNormalZ <= c3_rp_objNormalZ;	
end

reg signed [31:0] c4_rs_closestPointAlongRay;
reg signed [31:0] c4_rs_sphereToRayStartDistSq;
reg signed [31:0] c4_rs_radiusSq;
reg signed [31:0] c4_rs_objX;
reg signed [31:0] c4_rs_objY;
reg signed [31:0] c4_rs_objZ;
reg signed [31:0] c4_rs_objRad;

reg signed [31:0] c4_rp_pointOnPlaneX;
reg signed [31:0] c4_rp_pointOnPlaneY;
reg signed [31:0] c4_rp_pointOnPlaneZ;
reg signed [15:0] c4_rp_objNormalX;
reg signed [15:0] c4_rp_objNormalY;
reg signed [15:0] c4_rp_objNormalZ;

// Cycle 4
always @(posedge clock) begin
	reg signed [31:0] distFromSphereCentreToClosestPointSq;
	
	distFromSphereCentreToClosestPointSq = c4_rs_sphereToRayStartDistSq - FixedMul(c4_rs_closestPointAlongRay, c4_rs_closestPointAlongRay);

	c5_rs_rayStartInsideSphere <= (c4_rs_sphereToRayStartDistSq < c4_rs_radiusSq);	
   c5_rs_distFromSphereCentreToClosestPointSq <= distFromSphereCentreToClosestPointSq;
	
	c5_rs_sqrtIn <= c4_rs_radiusSq - distFromSphereCentreToClosestPointSq;
	
	c5_rs_objX <= c4_rs_objX;
	c5_rs_objY <= c4_rs_objY;
	c5_rs_objZ <= c4_rs_objZ;
	c5_rs_objRad <= c4_rs_objRad;
	c5_rs_radiusSq <= c4_rs_radiusSq;
	c5_rs_closestPointAlongRay <= c4_rs_closestPointAlongRay;
	
	c5_rp_deltaX <= u_rayStartX - c4_rp_pointOnPlaneX;
	c5_rp_deltaY <= u_rayStartY - c4_rp_pointOnPlaneY;
	c5_rp_deltaZ <= u_rayStartZ - c4_rp_pointOnPlaneZ;
	
	c5_rp_objNormalX <= c4_rp_objNormalX;
	c5_rp_objNormalY <= c4_rp_objNormalY;
	c5_rp_objNormalZ <= c4_rp_objNormalZ;	
end

reg c5_rs_rayStartInsideSphere;
reg signed [31:0] c5_rs_distFromSphereCentreToClosestPointSq;
reg signed [31:0] c5_rs_closestPointAlongRay;
reg signed [31:0] c5_rs_radiusSq;
reg signed [31:0] c5_rs_objX;
reg signed [31:0] c5_rs_objY;
reg signed [31:0] c5_rs_objZ;
reg signed [31:0] c5_rs_objRad;

reg signed [31:0] c5_rp_deltaX;
reg signed [31:0] c5_rp_deltaY;
reg signed [31:0] c5_rp_deltaZ;
reg signed [15:0] c5_rp_objNormalX;
reg signed [15:0] c5_rp_objNormalY;
reg signed [15:0] c5_rp_objNormalZ;

// Cycle 5
always @(posedge clock) begin	
	c6_rs_objX <= c5_rs_objX;
	c6_rs_objY <= c5_rs_objY;
	c6_rs_objZ <= c5_rs_objZ;
	c6_rs_objRad <= c5_rs_objRad;
	c6_rs_distFromSphereCentreToClosestPointSq <= c5_rs_distFromSphereCentreToClosestPointSq;
	c6_rs_rayStartInsideSphere <= c5_rs_rayStartInsideSphere;
	c6_rs_radiusSq <= c5_rs_radiusSq;
	c6_rs_closestPointAlongRay <= c5_rs_closestPointAlongRay;
	
	c6_rp_dotSided <= FixedMul(c5_rp_deltaX, c5_rp_objNormalX) + FixedMul(c5_rp_deltaY, c5_rp_objNormalY) + FixedMul(c5_rp_deltaZ, c5_rp_objNormalZ);
	
	c6_rp_objNormalX <= c5_rp_objNormalX;
	c6_rp_objNormalY <= c5_rp_objNormalY;
	c6_rp_objNormalZ <= c5_rp_objNormalZ;	
end

reg signed [31:0] c6_rs_objX;
reg signed [31:0] c6_rs_objY;
reg signed [31:0] c6_rs_objZ;
reg signed [31:0] c6_rs_objRad;
reg c6_rs_rayStartInsideSphere;
reg signed [31:0] c6_rs_distFromSphereCentreToClosestPointSq;
reg signed [31:0] c6_rs_radiusSq;
reg signed [31:0] c6_rs_closestPointAlongRay;

reg signed [31:0] c6_rp_dotSided;
reg signed [15:0] c6_rp_objNormalX;
reg signed [15:0] c6_rp_objNormalY;
reg signed [15:0] c6_rp_objNormalZ;

// Cycle 6
always @(posedge clock) begin	
	c7_rs_objX <= c6_rs_objX;
	c7_rs_objY <= c6_rs_objY;
	c7_rs_objZ <= c6_rs_objZ;
	c7_rs_objRad <= c6_rs_objRad;
	c7_rs_distFromSphereCentreToClosestPointSq <= c6_rs_distFromSphereCentreToClosestPointSq;
	c7_rs_rayStartInsideSphere <= c6_rs_rayStartInsideSphere;
	c7_rs_radiusSq <= c6_rs_radiusSq;
	c7_rs_closestPointAlongRay <= c6_rs_closestPointAlongRay;
	
	c7_rp_rayStartInsideVolume <= (c6_rp_dotSided < 0);
	
	c7_rp_dotSided <= c6_rp_dotSided;
	c7_rp_objNormalX <= c6_rp_objNormalX;
	c7_rp_objNormalY <= c6_rp_objNormalY;
	c7_rp_objNormalZ <= c6_rp_objNormalZ;	
end

reg signed [31:0] c7_rs_objX;
reg signed [31:0] c7_rs_objY;
reg signed [31:0] c7_rs_objZ;
reg signed [31:0] c7_rs_objRad;
reg c7_rs_rayStartInsideSphere;
reg signed [31:0] c7_rs_distFromSphereCentreToClosestPointSq;
reg signed [31:0] c7_rs_radiusSq;
reg signed [31:0] c7_rs_closestPointAlongRay;

reg c7_rp_rayStartInsideVolume;
reg signed [31:0] c7_rp_dotSided;
reg signed [15:0] c7_rp_objNormalX;
reg signed [15:0] c7_rp_objNormalY;
reg signed [15:0] c7_rp_objNormalZ;

// Cycle 7
always @(posedge clock) begin
	c8_rs_objX <= c7_rs_objX;
	c8_rs_objY <= c7_rs_objY;
	c8_rs_objZ <= c7_rs_objZ;
	c8_rs_objRad <= c7_rs_objRad;
	c8_rs_distFromSphereCentreToClosestPointSq <= c7_rs_distFromSphereCentreToClosestPointSq;
	c8_rs_rayStartInsideSphere <= c7_rs_rayStartInsideSphere;
	c8_rs_radiusSq <= c7_rs_radiusSq;
	c8_rs_closestPointAlongRay <= c7_rs_closestPointAlongRay;
	
	// Flip so we are testing against the back side of the plane
	c8_rp_normalX <= c7_rp_rayStartInsideVolume ? -c7_rp_objNormalX : c7_rp_objNormalX;
	c8_rp_normalY <= c7_rp_rayStartInsideVolume ? -c7_rp_objNormalY : c7_rp_objNormalY;
	c8_rp_normalZ <= c7_rp_rayStartInsideVolume ? -c7_rp_objNormalZ : c7_rp_objNormalZ;
	c8_rp_dot <= c7_rp_rayStartInsideVolume ? -c7_rp_dotSided : c7_rp_dotSided;
	
	c8_rp_rayStartInsideVolume <= c7_rp_rayStartInsideVolume;
end

reg signed [31:0] c8_rs_objX;
reg signed [31:0] c8_rs_objY;
reg signed [31:0] c8_rs_objZ;
reg signed [31:0] c8_rs_objRad;
reg c8_rs_rayStartInsideSphere;
reg signed [31:0] c8_rs_distFromSphereCentreToClosestPointSq;
reg signed [31:0] c8_rs_radiusSq;
reg signed [31:0] c8_rs_closestPointAlongRay;

reg signed [15:0] c8_rp_normalX;
reg signed [15:0] c8_rp_normalY;
reg signed [15:0] c8_rp_normalZ;
reg signed [31:0] c8_rp_dot;
reg c8_rp_rayStartInsideVolume;

// Cycle 8
always @(posedge clock) begin
	reg signed [31:0] rp_denom;
	reg isSphere;
	
	isSphere = c8_instructionWord[0]; // See Instruction enum for details
	
	c9_rs_objX <= c8_rs_objX;
	c9_rs_objY <= c8_rs_objY;
	c9_rs_objZ <= c8_rs_objZ;
	c9_rs_distFromSphereCentreToClosestPointSq <= c8_rs_distFromSphereCentreToClosestPointSq;
	c9_rs_rayStartInsideSphere <= c8_rs_rayStartInsideSphere;
	c9_rs_radiusSq <= c8_rs_radiusSq;
	c9_rs_closestPointAlongRay <= c8_rs_closestPointAlongRay;
	
	rp_denom = FixedMul16x16(u_rayDirX, c8_rp_normalX) + FixedMul16x16(u_rayDirY, c8_rp_normalY) + FixedMul16x16(u_rayDirZ, c8_rp_normalZ);

	// Multiplex the RCP module
	c9_rs_rcpIn <= isSphere ? c8_rs_objRad : (-rp_denom); // Result becomes available on cycle 13
	
	c9_rp_normalX <= c8_rp_normalX;
	c9_rp_normalY <= c8_rp_normalY;
	c9_rp_normalZ <= c8_rp_normalZ;
	c9_rp_dot <= c8_rp_dot;
	c9_rp_rayStartInsideVolume <= c8_rp_rayStartInsideVolume;		
end

reg signed [31:0] c9_rs_objX;
reg signed [31:0] c9_rs_objY;
reg signed [31:0] c9_rs_objZ;
reg c9_rs_rayStartInsideSphere;
reg signed [31:0] c9_rs_distFromSphereCentreToClosestPointSq;
reg signed [31:0] c9_rs_radiusSq;
reg signed [31:0] c9_rs_closestPointAlongRay;

reg signed [15:0] c9_rp_normalX;
reg signed [15:0] c9_rp_normalY;
reg signed [15:0] c9_rp_normalZ;
reg signed [31:0] c9_rp_dot;
reg c9_rp_rayStartInsideVolume;

// Cycle 9
always @(posedge clock) begin
	reg signed [31:0] distAlongRayFromClosestPointToSphereSurface;

	distAlongRayFromClosestPointToSphereSurface = rs_sqrtResult;
	
	c10_rs_entryDepth <= c9_rs_rayStartInsideSphere ? 32'h0 : (c9_rs_closestPointAlongRay - distAlongRayFromClosestPointToSphereSurface);
	c10_rs_exitDepth <= c9_rs_closestPointAlongRay + distAlongRayFromClosestPointToSphereSurface;
	
	c10_rs_objX <= c9_rs_objX;
	c10_rs_objY <= c9_rs_objY;
	c10_rs_objZ <= c9_rs_objZ;
	c10_rs_rayStartInsideSphere <= c9_rs_rayStartInsideSphere;
	c10_rs_distFromSphereCentreToClosestPointSq <= c9_rs_distFromSphereCentreToClosestPointSq;
	c10_rs_radiusSq <= c9_rs_radiusSq;
	c10_rs_closestPointAlongRay <= c9_rs_closestPointAlongRay;
	
	c10_rp_normalX <= c9_rp_normalX;
	c10_rp_normalY <= c9_rp_normalY;
	c10_rp_normalZ <= c9_rp_normalZ;
	c10_rp_dot <= c9_rp_dot;
	c10_rp_rayStartInsideVolume <= c9_rp_rayStartInsideVolume;	
end
	
reg signed [31:0] c10_rs_entryDepth;
reg signed [31:0] c10_rs_exitDepth;
reg signed [31:0] c10_rs_objX;
reg signed [31:0] c10_rs_objY;
reg signed [31:0] c10_rs_objZ;
reg c10_rs_rayStartInsideSphere;
reg signed [31:0] c10_rs_distFromSphereCentreToClosestPointSq;
reg signed [31:0] c10_rs_radiusSq;
reg signed [31:0] c10_rs_closestPointAlongRay;

reg signed [15:0] c10_rp_normalX;
reg signed [15:0] c10_rp_normalY;
reg signed [15:0] c10_rp_normalZ;
reg signed [31:0] c10_rp_dot;
reg c10_rp_rayStartInsideVolume;
	
// Cycle 10
always @(posedge clock) begin
	// Position of entry point
	c11_rs_tempHitX <= u_rayStartX + FixedMul(u_rayDirX, c10_rs_entryDepth);
	c11_rs_tempHitY <= u_rayStartY + FixedMul(u_rayDirY, c10_rs_entryDepth);
	c11_rs_tempHitZ <= u_rayStartZ + FixedMul(u_rayDirZ, c10_rs_entryDepth);
	
	// Position of exit point
	c11_rs_tempHitX2 <= u_rayStartX + FixedMul(u_rayDirX, c10_rs_exitDepth);
	c11_rs_tempHitY2 <= u_rayStartY + FixedMul(u_rayDirY, c10_rs_exitDepth);
	c11_rs_tempHitZ2 <= u_rayStartZ + FixedMul(u_rayDirZ, c10_rs_exitDepth);
	
	c11_rs_objX <= c10_rs_objX;
	c11_rs_objY <= c10_rs_objY;
	c11_rs_objZ <= c10_rs_objZ;
	c11_rs_rayStartInsideSphere <= c10_rs_rayStartInsideSphere;
	c11_rs_entryDepth <= c10_rs_entryDepth;
	c11_rs_exitDepth <= c10_rs_exitDepth;
	c11_rs_distFromSphereCentreToClosestPointSq <= c10_rs_distFromSphereCentreToClosestPointSq;
	c11_rs_radiusSq <= c10_rs_radiusSq;
	c11_rs_closestPointAlongRay <= c10_rs_closestPointAlongRay;
	
	c11_rp_normalX <= c10_rp_normalX;
	c11_rp_normalY <= c10_rp_normalY;
	c11_rp_normalZ <= c10_rp_normalZ;
	c11_rp_dot <= c10_rp_dot;
	c11_rp_rayStartInsideVolume <= c10_rp_rayStartInsideVolume;	
end

reg signed [31:0] c11_rs_tempHitX;
reg signed [31:0] c11_rs_tempHitY;
reg signed [31:0] c11_rs_tempHitZ;
reg signed [31:0] c11_rs_tempHitX2;
reg signed [31:0] c11_rs_tempHitY2;
reg signed [31:0] c11_rs_tempHitZ2;
reg signed [31:0] c11_rs_invSphereRad;
reg signed [31:0] c11_rs_objX;
reg signed [31:0] c11_rs_objY;
reg signed [31:0] c11_rs_objZ;
reg c11_rs_rayStartInsideSphere;
reg signed [31:0] c11_rs_entryDepth;
reg signed [31:0] c11_rs_exitDepth;
reg signed [31:0] c11_rs_distFromSphereCentreToClosestPointSq;
reg signed [31:0] c11_rs_radiusSq;
reg signed [31:0] c11_rs_closestPointAlongRay;

reg signed [15:0] c11_rp_normalX;
reg signed [15:0] c11_rp_normalY;
reg signed [15:0] c11_rp_normalZ;
reg signed [31:0] c11_rp_dot;
reg c11_rp_rayStartInsideVolume;

// Cycle 11
always @(posedge clock) begin	
	c12_rs_tempHitX <= c11_rs_tempHitX;
	c12_rs_tempHitY <= c11_rs_tempHitY;
	c12_rs_tempHitZ <= c11_rs_tempHitZ;
	c12_rs_tempHitX2 <= c11_rs_tempHitX2;
	c12_rs_tempHitY2 <= c11_rs_tempHitY2;
	c12_rs_tempHitZ2 <= c11_rs_tempHitZ2;
	c12_rs_objX <= c11_rs_objX;
	c12_rs_objY <= c11_rs_objY;
	c12_rs_objZ <= c11_rs_objZ;
	c12_rs_rayStartInsideSphere <= c11_rs_rayStartInsideSphere;
	c12_rs_entryDepth <= c11_rs_entryDepth;
	c12_rs_exitDepth <= c11_rs_exitDepth;
	c12_rs_distFromSphereCentreToClosestPointSq <= c11_rs_distFromSphereCentreToClosestPointSq;
	c12_rs_radiusSq <= c11_rs_radiusSq;
	c12_rs_closestPointAlongRay <= c11_rs_closestPointAlongRay;
	c12_rs_invSphereRad <= c11_rs_invSphereRad;
	
	c12_rp_normalX <= c11_rp_normalX;
	c12_rp_normalY <= c11_rp_normalY;
	c12_rp_normalZ <= c11_rp_normalZ;
	c12_rp_dot <= c11_rp_dot;
	c12_rp_rayStartInsideVolume <= c11_rp_rayStartInsideVolume;	
end

reg signed [31:0] c12_rs_tempHitX;
reg signed [31:0] c12_rs_tempHitY;
reg signed [31:0] c12_rs_tempHitZ;
reg signed [31:0] c12_rs_tempHitX2;
reg signed [31:0] c12_rs_tempHitY2;
reg signed [31:0] c12_rs_tempHitZ2;
reg signed [31:0] c12_rs_invSphereRad;
reg signed [31:0] c12_rs_objX;
reg signed [31:0] c12_rs_objY;
reg signed [31:0] c12_rs_objZ;
reg c12_rs_rayStartInsideSphere;
reg signed [31:0] c12_rs_entryDepth;
reg signed [31:0] c12_rs_exitDepth;
reg signed [31:0] c12_rs_distFromSphereCentreToClosestPointSq;
reg signed [31:0] c12_rs_radiusSq;
reg signed [31:0] c12_rs_closestPointAlongRay;

reg signed [15:0] c12_rp_normalX;
reg signed [15:0] c12_rp_normalY;
reg signed [15:0] c12_rp_normalZ;
reg signed [31:0] c12_rp_dot;
reg c12_rp_rayStartInsideVolume;

// Cycle 12
always @(posedge clock) begin	
	c13_rs_tempHitX <= c12_rs_tempHitX;
	c13_rs_tempHitY <= c12_rs_tempHitY;
	c13_rs_tempHitZ <= c12_rs_tempHitZ;
	c13_rs_tempHitX2 <= c12_rs_tempHitX2;
	c13_rs_tempHitY2 <= c12_rs_tempHitY2;
	c13_rs_tempHitZ2 <= c12_rs_tempHitZ2;
	c13_rs_objX <= c12_rs_objX;
	c13_rs_objY <= c12_rs_objY;
	c13_rs_objZ <= c12_rs_objZ;
	c13_rs_rayStartInsideSphere <= c12_rs_rayStartInsideSphere;
	c13_rs_entryDepth <= c12_rs_entryDepth;
	c13_rs_exitDepth <= c12_rs_exitDepth;
	c13_rs_distFromSphereCentreToClosestPointSq <= c12_rs_distFromSphereCentreToClosestPointSq;
	c13_rs_radiusSq <= c12_rs_radiusSq;
	c13_rs_closestPointAlongRay <= c12_rs_closestPointAlongRay;
	c13_rs_invSphereRad <= c12_rs_invSphereRad;
	
	c13_rp_normalX <= c12_rp_normalX;
	c13_rp_normalY <= c12_rp_normalY;
	c13_rp_normalZ <= c12_rp_normalZ;
	c13_rp_dot <= c12_rp_dot;
	c13_rp_rayStartInsideVolume <= c12_rp_rayStartInsideVolume;	
end

reg signed [31:0] c13_rs_tempHitX;
reg signed [31:0] c13_rs_tempHitY;
reg signed [31:0] c13_rs_tempHitZ;
reg signed [31:0] c13_rs_tempHitX2;
reg signed [31:0] c13_rs_tempHitY2;
reg signed [31:0] c13_rs_tempHitZ2;
reg signed [31:0] c13_rs_invSphereRad;
reg signed [31:0] c13_rs_objX;
reg signed [31:0] c13_rs_objY;
reg signed [31:0] c13_rs_objZ;
reg c13_rs_rayStartInsideSphere;
reg signed [31:0] c13_rs_entryDepth;
reg signed [31:0] c13_rs_exitDepth;
reg signed [31:0] c13_rs_distFromSphereCentreToClosestPointSq;
reg signed [31:0] c13_rs_radiusSq;
reg signed [31:0] c13_rs_closestPointAlongRay;

reg signed [15:0] c13_rp_normalX;
reg signed [15:0] c13_rp_normalY;
reg signed [15:0] c13_rp_normalZ;
reg signed [31:0] c13_rp_dot;
reg c13_rp_rayStartInsideVolume;

// Cycle 13
always @(posedge clock) begin	
	reg signed [31:0] t;
	reg signed [31:0] rs_invSphereRad;
	
	rs_invSphereRad = c13_rs_rcpResult;
	
	c14_raySphere_EntryNormalX <= c13_rs_rayStartInsideSphere ? -u_rayDirX : 16'(FixedMul(c13_rs_tempHitX - c13_rs_objX, rs_invSphereRad));
	c14_raySphere_EntryNormalY <= c13_rs_rayStartInsideSphere ? -u_rayDirY : 16'(FixedMul(c13_rs_tempHitY - c13_rs_objY, rs_invSphereRad));
	c14_raySphere_EntryNormalZ <= c13_rs_rayStartInsideSphere ? -u_rayDirZ : 16'(FixedMul(c13_rs_tempHitZ - c13_rs_objZ, rs_invSphereRad));

	c14_raySphere_ExitNormalX <= 16'(FixedMul(c13_rs_tempHitX2 - c13_rs_objX, rs_invSphereRad));
	c14_raySphere_ExitNormalY <= 16'(FixedMul(c13_rs_tempHitY2 - c13_rs_objY, rs_invSphereRad));
	c14_raySphere_ExitNormalZ <= 16'(FixedMul(c13_rs_tempHitZ2 - c13_rs_objZ, rs_invSphereRad));
	
	if (((c13_rs_closestPointAlongRay >= 0) || (c13_rs_rayStartInsideSphere)) && 
	    (c13_rs_distFromSphereCentreToClosestPointSq < c13_rs_radiusSq) && // Check ray actually intersects sphere
		 (c13_rs_entryDepth >= 0)) begin // Check sphere is in front of us
		c14_raySphere_EntryDepth <= c13_rs_entryDepth;
		c14_raySphere_ExitDepth <= c13_rs_exitDepth;
	end else begin
		// No intersection
		c14_raySphere_EntryDepth <= 32'sh7FFFFFFF;
		c14_raySphere_ExitDepth <= 32'sh0;
	end
	
	t = FixedMul(c13_rp_dot, c13_rs_rcpResult);

	if (c13_rs_rcpResult < 0) begin // Technically testing (denom >= 0), but rcpDemon (which is 1/-denom) is available here and saves us passing it through
		// Ray pointing away from plane, so ray is either entirely inside or entirely outside it, depending on where it started

		if (c13_rp_rayStartInsideVolume) begin
			// Entirely inside plane
			c14_rayPlane_EntryDepth <= 32'sh0;
			c14_rayPlane_ExitDepth <= 32'sh7FFFFFFF;
			c14_rayPlane_EntryNormalX <= -u_rayDirX;
			c14_rayPlane_EntryNormalY <= -u_rayDirY;
			c14_rayPlane_EntryNormalZ <= -u_rayDirZ;
			c14_rayPlane_ExitNormalX <= 16'sh0;
			c14_rayPlane_ExitNormalY <= 16'sh0;
			c14_rayPlane_ExitNormalZ <= 16'sh0;
		end else begin
			c14_rayPlane_EntryDepth <= 32'sh7FFFFFFF;
			c14_rayPlane_ExitDepth <= 32'sh0;
			c14_rayPlane_EntryNormalX <= 16'sh0;
			c14_rayPlane_EntryNormalY <= 16'sh0;
			c14_rayPlane_EntryNormalZ <= 16'sh0;
			c14_rayPlane_ExitNormalX <= 16'sh0;
			c14_rayPlane_ExitNormalY <= 16'sh0;
			c14_rayPlane_ExitNormalZ <= 16'sh0;			
		end
	end else begin
		// Ray pointing towards plane

		if (t >= 0) begin
			c14_rayPlane_EntryDepth <= c13_rp_rayStartInsideVolume ? 32'sh0 : t;
			c14_rayPlane_ExitDepth <= c13_rp_rayStartInsideVolume ? t : 32'sh7FFFFFFF;
			c14_rayPlane_EntryNormalX <= c13_rp_normalX;
			c14_rayPlane_EntryNormalY <= c13_rp_normalY;
			c14_rayPlane_EntryNormalZ <= c13_rp_normalZ;
			c14_rayPlane_ExitNormalX <= -c13_rp_normalX;
			c14_rayPlane_ExitNormalY <= -c13_rp_normalY;
			c14_rayPlane_ExitNormalZ <= -c13_rp_normalZ;
		end else begin
			c14_rayPlane_EntryDepth <= 32'sh7FFFFFFF;
			c14_rayPlane_ExitDepth <= 32'sh0;
			c14_rayPlane_EntryNormalX <= 16'sh0;
			c14_rayPlane_EntryNormalY <= 16'sh0;
			c14_rayPlane_EntryNormalZ <= 16'sh0;
			c14_rayPlane_ExitNormalX <= 16'sh0;
			c14_rayPlane_ExitNormalY <= 16'sh0;
			c14_rayPlane_ExitNormalZ <= 16'sh0;				
		end
	end	
end