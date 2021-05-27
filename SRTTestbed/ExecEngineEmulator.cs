using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Instruction = SRTTestbed.ExecEngine.Instruction;
using Condition = SRTTestbed.ExecEngine.Condition;
using ObjectMergeType = SRTTestbed.ExecEngine.ObjectMergeType;

namespace SRTTestbed
{
    // A fast version of ExecEngine that doesn't try to be cycle-accurate or anything (but is a *lot* faster)
    class ExecEngineEmulator
    {
        // Inputs
        public bool x_Start_tick;
        public UInt64[] u_CommandBuffer;

        // Current ray information
        public int u_RayStartX;
        public int u_RayStartY;
        public int u_RayStartZ;
        public Int16 u_RayDirX;
        public Int16 u_RayDirY;
        public Int16 u_RayDirZ;
        public int u_RayDirRcpX; // Do not use these here - they have latency emulation in RayEngine and thus
        public int u_RayDirRcpY; // aren't necessarily set correctly when ExecEngine isn't doing cycle-correct
        public int u_RayDirRcpZ; // timings
        public bool u_ShadowRay;
        public bool u_SecondaryRay;

        // Outputs
        public bool x_Busy;

        // Hit information
        // If HitEntryDepth < HitExitDepth then the ray hit something
        int s14_HitEntryDepth; // Depth of the hit (entering the object)
        int s14_HitExitDepth; // Depth of the hit (exiting the object)
        Int16 s14_HitNormalX; // Hit normal
        Int16 s14_HitNormalY;
        Int16 s14_HitNormalZ;
        bool s14_ObjRegisteredHit; // Has this object registered a hit?
        int s14_HitCalculation_HitX;
        int s14_HitCalculation_HitY;
        int s14_HitCalculation_HitZ;

        // Origin
        int s3_originX;
        int s3_originY;
        int s3_originZ;

        // Externally visible outputs
        public bool s14_RegHit;
        public int s14_RegHitDepth;
        public int s14_RegHitX;
        public int s14_RegHitY;
        public int s14_RegHitZ;
        public Int16 s14_RegHitNormalX;
        public Int16 s14_RegHitNormalY;
        public Int16 s14_RegHitNormalZ;
        public UInt16 s14_RegHitAlbedo;
        public byte s14_RegHitReflectiveness;
        public UInt32 s14_InstructionInvalidated = 0; // One bit for each pipeline stage indicating if the instruction currently at that stage is valid

        // Performance counters
        public int p_CycleCount;
        public int p_BranchPredictionHits;
        public int p_BranchPredictionMisses;
        public int p_InstructionsExecuted;
        public int p_InstructionsAbandoned;

        public void ResetPerfCounters()
        {
            p_CycleCount = 0;
            p_BranchPredictionHits = 0;
            p_BranchPredictionMisses = 0;
            p_InstructionsExecuted = 0;
            p_InstructionsAbandoned = 0;
        }

        // Debug
        public StringBuilder x_TraceDebug = null;

        // Reset state
        public void Reset()
        {
            x_Busy = false;
        }

        // Perform a single execution tick
        // Returns the mutated engine state
        public ExecEngineEmulator Tick()
        {
            // Do nothing until we are started
            if (!x_Start_tick)
                return this;

            int pc = 0;
            x_Busy = true;

            while (x_Busy)
            {
                UInt64 instructionWord = u_CommandBuffer[pc++];

                Condition condition = (Condition)((instructionWord >> 6) & 3);

                bool execute;

                switch (condition)
                {
                    default:
                    case Condition.AL:
                        execute = true;
                        break;
                    case Condition.OH:
                        execute = s14_HitEntryDepth < s14_HitExitDepth;
                        break;
                    case Condition.NH:
                        execute = !(s14_HitEntryDepth < s14_HitExitDepth);
                        break;
                    case Condition.ORH:
                        execute = s14_ObjRegisteredHit;
                        break;
                }

                Instruction inst = (Instruction)(instructionWord & 0x3F);

                x_TraceDebug?.AppendLine("  Dispatching " + inst + " " + condition + (execute ? "" : " (not executing)"));

                if (execute && (inst != Instruction.NOP))
                {
                    p_InstructionsExecuted++;
                }
                else
                {
                    p_InstructionsAbandoned++;
                }

                switch (inst)
                {
                    case Instruction.Start:
                    {
                        if (execute)
                        {
                            s14_HitEntryDepth = 0x7FFFFFFF;
                            s14_HitExitDepth = 0;
                            s14_ObjRegisteredHit = false;
                            s14_RegHit = false;
                            s3_originX = 0;
                            s3_originY = 0;
                            s3_originZ = 0;
                        }
                        break;
                    }
                    case Instruction.Sphere:
                    case Instruction.SphereSub:
                    case Instruction.SphereAnd:
                    case Instruction.Plane:
                    case Instruction.PlaneSub:
                    case Instruction.PlaneAnd:
                    case Instruction.AABB:
                    case Instruction.AABBSub:
                    case Instruction.AABBAnd:
                    {
                        if (execute)
                        {
                            // Perform intersection

                            int entryDepth;
                            int exitDepth;
                            Int16 entryNormalX = 0;
                            Int16 entryNormalY = 0;
                            Int16 entryNormalZ = 0;
                            Int16 exitNormalX = 0;
                            Int16 exitNormalY = 0;
                            Int16 exitNormalZ = 0;

                            switch (inst)
                            {
                                case Instruction.Sphere:
                                case Instruction.SphereSub:
                                case Instruction.SphereAnd:
                                {
                                    int c3_rs_ObjX = FixedMaths.ConvertFrom8Dot7((UInt32)((instructionWord >> 8) & 0x7FFF));
                                    int c3_rs_ObjY = FixedMaths.ConvertFrom8Dot7((UInt32)((instructionWord >> 23) & 0x7FFF));
                                    int c3_rs_ObjZ = FixedMaths.ConvertFrom8Dot7((UInt32)((instructionWord >> 38) & 0x7FFF));
                                    int c3_rs_ObjRad = FixedMaths.ConvertFrom4Dot7((UInt16)((instructionWord >> 53) & 0x7FF));

                                    int ocX = u_RayStartX - (c3_rs_ObjX + s3_originX); // Delta from ray start point to sphere
                                    int ocY = u_RayStartY - (c3_rs_ObjY + s3_originY);
                                    int ocZ = u_RayStartZ - (c3_rs_ObjZ + s3_originZ);

                                    x_TraceDebug?.AppendLine("  Sphere ray delta = " + FixedMaths.FixedToFloat(ocX) + ", " + FixedMaths.FixedToFloat(ocY) + ", " + FixedMaths.FixedToFloat(ocZ));

                                    // Distance along the ray to the closest point in the sphere
                                    int c4_rs_closestPointAlongRay = -(FixedMaths.FixedMul(ocX, u_RayDirX) + FixedMaths.FixedMul(ocY, u_RayDirY) + FixedMaths.FixedMul(ocZ, u_RayDirZ));
                                    int c4_rs_sphereToRayStartDistSq = FixedMaths.FixedMul(ocX, ocX) + FixedMaths.FixedMul(ocY, ocY) + FixedMaths.FixedMul(ocZ, ocZ);
                                    int c4_rs_radiusSq = FixedMaths.FixedMul(c3_rs_ObjRad, c3_rs_ObjRad);

                                    int distFromSphereCentreToClosestPointSq = c4_rs_sphereToRayStartDistSq - FixedMaths.FixedMul(c4_rs_closestPointAlongRay, c4_rs_closestPointAlongRay);

                                    bool c5_rs_rayStartInsideSphere = (c4_rs_sphereToRayStartDistSq < c4_rs_radiusSq);
                                    int c5_rs_distFromSphereCentreToClosestPointSq = distFromSphereCentreToClosestPointSq;

                                    x_TraceDebug?.AppendLine("  Sphere rayStartInsideSphere = " + c5_rs_rayStartInsideSphere);
                                    x_TraceDebug?.AppendLine("  Sphere distFromSphereCentreToClosestPointSq = " + FixedMaths.FixedToFloat(c5_rs_distFromSphereCentreToClosestPointSq));

                                    int c8_rs_invSphereRad = FixedMaths.FixedRcp(c3_rs_ObjRad);

                                    int distAlongRayFromClosestPointToSphereSurface = FixedMaths.FixedSqrt(c4_rs_radiusSq - distFromSphereCentreToClosestPointSq);

                                    int c10_rs_entryDepth = c5_rs_rayStartInsideSphere ? 0 : (c4_rs_closestPointAlongRay - distAlongRayFromClosestPointToSphereSurface);
                                    int c10_rs_exitDepth = c4_rs_closestPointAlongRay + distAlongRayFromClosestPointToSphereSurface;

                                    x_TraceDebug?.AppendLine("  Sphere entryDepth = " + FixedMaths.FixedToFloat(c10_rs_entryDepth));
                                    x_TraceDebug?.AppendLine("  Sphere exitDepth = " + FixedMaths.FixedToFloat(c10_rs_exitDepth));

                                    int c11_rs_tempHitX = u_RayStartX + FixedMaths.FixedMul(u_RayDirX, c10_rs_entryDepth);
                                    int c11_rs_tempHitY = u_RayStartY + FixedMaths.FixedMul(u_RayDirY, c10_rs_entryDepth);
                                    int c11_rs_tempHitZ = u_RayStartZ + FixedMaths.FixedMul(u_RayDirZ, c10_rs_entryDepth);
                                    int c11_rs_tempHitX2 = u_RayStartX + FixedMaths.FixedMul(u_RayDirX, c10_rs_exitDepth);
                                    int c11_rs_tempHitY2 = u_RayStartY + FixedMaths.FixedMul(u_RayDirY, c10_rs_exitDepth);
                                    int c11_rs_tempHitZ2 = u_RayStartZ + FixedMaths.FixedMul(u_RayDirZ, c10_rs_exitDepth);

                                    entryNormalX = c5_rs_rayStartInsideSphere ? (Int16)(-u_RayDirX) : (Int16)FixedMaths.FixedMul(c11_rs_tempHitX - (c3_rs_ObjX + s3_originX), c8_rs_invSphereRad);
                                    entryNormalY = c5_rs_rayStartInsideSphere ? (Int16)(-u_RayDirY) : (Int16)FixedMaths.FixedMul(c11_rs_tempHitY - (c3_rs_ObjY + s3_originY), c8_rs_invSphereRad);
                                    entryNormalZ = c5_rs_rayStartInsideSphere ? (Int16)(-u_RayDirZ) : (Int16)FixedMaths.FixedMul(c11_rs_tempHitZ - (c3_rs_ObjZ + s3_originZ), c8_rs_invSphereRad);

                                    exitNormalX = (Int16)FixedMaths.FixedMul(c11_rs_tempHitX2 - (c3_rs_ObjX + s3_originX), c8_rs_invSphereRad);
                                    exitNormalY = (Int16)FixedMaths.FixedMul(c11_rs_tempHitY2 - (c3_rs_ObjY + s3_originY), c8_rs_invSphereRad);
                                    exitNormalZ = (Int16)FixedMaths.FixedMul(c11_rs_tempHitZ2 - (c3_rs_ObjZ + s3_originZ), c8_rs_invSphereRad);

                                    x_TraceDebug?.AppendLine("  Sphere closestPointAlongRay = " + FixedMaths.FixedToFloat(c4_rs_closestPointAlongRay));
                                    x_TraceDebug?.AppendLine("  Sphere rayStartInsideSphere = " + c5_rs_rayStartInsideSphere);
                                    x_TraceDebug?.AppendLine("  Sphere distFromSphereCentreToClosestPointSq = " + FixedMaths.FixedToFloat(c5_rs_distFromSphereCentreToClosestPointSq));
                                    x_TraceDebug?.AppendLine("  Sphere entryDepth = " + FixedMaths.FixedToFloat(c10_rs_entryDepth));

                                    // Ray must either point towards the sphere or start inside it to have a chance of intersecting
                                    if (((c4_rs_closestPointAlongRay >= 0) || (c5_rs_rayStartInsideSphere)) &&
                                        (distFromSphereCentreToClosestPointSq < c4_rs_radiusSq) && // Check ray actually intersects sphere
                                        (c10_rs_entryDepth >= 0)) // Check sphere is in front of us
                                    {
                                        x_TraceDebug?.AppendLine("  Sphere hit from " + FixedMaths.FixedToFloat(c10_rs_entryDepth) + " to " + FixedMaths.FixedToFloat(c10_rs_exitDepth));
                                        entryDepth = c10_rs_entryDepth;
                                        exitDepth = c10_rs_exitDepth;
                                    }
                                    else
                                    {
                                        x_TraceDebug?.AppendLine("  Sphere not hit");
                                        entryDepth = 0x7FFFFFFF;
                                        exitDepth = 0;
                                    }
                                    break;
                                }
                                case Instruction.Plane:
                                case Instruction.PlaneSub:
                                case Instruction.PlaneAnd:
                                {
                                    Int16 c3_rp_ObjNormalX = FixedMaths.ConvertFrom2Dot10((UInt16)((instructionWord >> 8) & 0xFFF));
                                    Int16 c3_rp_ObjNormalY = FixedMaths.ConvertFrom2Dot10((UInt16)((instructionWord >> 20) & 0xFFF));
                                    Int16 c3_rp_ObjNormalZ = FixedMaths.ConvertFrom2Dot10((UInt16)((instructionWord >> 32) & 0xFFF));
                                    int c3_rp_ObjNormalDist = FixedMaths.ConvertFrom8Dot12((UInt32)((instructionWord >> 44) & 0xFFFFF));

                                    x_TraceDebug?.AppendLine("  Plane normal " + FixedMaths.FixedToFloat(c3_rp_ObjNormalX) + ", " + FixedMaths.FixedToFloat(c3_rp_ObjNormalY) + ", " + FixedMaths.FixedToFloat(c3_rp_ObjNormalZ) + ", Dist = " + FixedMaths.FixedToFloat(c3_rp_ObjNormalDist));

                                    int c4_rp_pointOnPlaneX = FixedMaths.FixedMul(c3_rp_ObjNormalX, c3_rp_ObjNormalDist);
                                    int c4_rp_pointOnPlaneY = FixedMaths.FixedMul(c3_rp_ObjNormalY, c3_rp_ObjNormalDist);
                                    int c4_rp_pointOnPlaneZ = FixedMaths.FixedMul(c3_rp_ObjNormalZ, c3_rp_ObjNormalDist);

                                    x_TraceDebug?.AppendLine("  Plane pointOnPlane " + FixedMaths.FixedToFloat(c4_rp_pointOnPlaneX) + ", " + FixedMaths.FixedToFloat(c4_rp_pointOnPlaneY) + ", " + FixedMaths.FixedToFloat(c4_rp_pointOnPlaneZ));

                                    int c5_rp_deltaX = u_RayStartX - (c4_rp_pointOnPlaneX + s3_originX);
                                    int c5_rp_deltaY = u_RayStartY - (c4_rp_pointOnPlaneY + s3_originY);
                                    int c5_rp_deltaZ = u_RayStartZ - (c4_rp_pointOnPlaneZ + s3_originZ);

                                    x_TraceDebug?.AppendLine("  Plane ray delta " + FixedMaths.FixedToFloat(c5_rp_deltaX) + ", " + FixedMaths.FixedToFloat(c5_rp_deltaY) + ", " + FixedMaths.FixedToFloat(c5_rp_deltaZ));

                                    int c6_rp_dotSided = FixedMaths.FixedMul(c5_rp_deltaX, c3_rp_ObjNormalX) + FixedMaths.FixedMul(c5_rp_deltaY, c3_rp_ObjNormalY) + FixedMaths.FixedMul(c5_rp_deltaZ, c3_rp_ObjNormalZ);

                                    x_TraceDebug?.AppendLine("  Plane dotSided = " + FixedMaths.FixedToFloat(c6_rp_dotSided));

                                    bool c7_rp_rayStartInsideVolume = (c6_rp_dotSided < 0);

                                    x_TraceDebug?.AppendLine("  Plane rayStartInsideVolume = " + c7_rp_rayStartInsideVolume);

                                    // Flip so we are testing against the back side of the plane
                                    Int16 c8_rp_normalX = c7_rp_rayStartInsideVolume ? (Int16)(-c3_rp_ObjNormalX) : c3_rp_ObjNormalX;
                                    Int16 c8_rp_normalY = c7_rp_rayStartInsideVolume ? (Int16)(-c3_rp_ObjNormalY) : c3_rp_ObjNormalY;
                                    Int16 c8_rp_normalZ = c7_rp_rayStartInsideVolume ? (Int16)(-c3_rp_ObjNormalZ) : c3_rp_ObjNormalZ;
                                    int c8_rp_dot = c7_rp_rayStartInsideVolume ? -c6_rp_dotSided : c6_rp_dotSided;

                                    int rp_denom = FixedMaths.FixedMul16x16(u_RayDirX, c8_rp_normalX) + FixedMaths.FixedMul16x16(u_RayDirY, c8_rp_normalY) + FixedMaths.FixedMul16x16(u_RayDirZ, c8_rp_normalZ);

                                    x_TraceDebug?.AppendLine("  Ray dir = " + FixedMaths.FixedToFloat(u_RayDirX) + ", " + FixedMaths.FixedToFloat(u_RayDirY) + ", " + FixedMaths.FixedToFloat(u_RayDirZ));
                                    x_TraceDebug?.AppendLine("  Plane normal = " + FixedMaths.FixedToFloat(c8_rp_normalX) + ", " + FixedMaths.FixedToFloat(c8_rp_normalY) + ", " + FixedMaths.FixedToFloat(c8_rp_normalZ));
                                    x_TraceDebug?.AppendLine("  Plane denom = " + FixedMaths.FixedToFloat(rp_denom));

                                    int rcpDenom = FixedMaths.FixedRcp(-rp_denom);

                                    x_TraceDebug?.AppendLine("  Plane RCPOut = " + FixedMaths.FixedToFloat(rcpDenom) + " dot = " + FixedMaths.FixedToFloat(c8_rp_dot));

                                    int t = FixedMaths.FixedMul(c8_rp_dot, rcpDenom);

                                    x_TraceDebug?.AppendLine("  Plane t = " + FixedMaths.FixedToFloat(t));

                                    // Assume no collision
                                    entryDepth = 0x7FFFFFFF;
                                    exitDepth = 0;

                                    if (rcpDenom < 0) // Was (denom >= 0), but rcpDemon is available here and has the opposite sign
                                    {
                                        // Ray pointing away from plane, so ray is either entirely inside or entirely outside it, depending on where it started

                                        if (c7_rp_rayStartInsideVolume)
                                        {
                                            x_TraceDebug?.AppendLine("  Ray entirely inside plane");
                                            // Entirely inside plane
                                            entryDepth = 0;
                                            exitDepth = 0x7FFFFFFF;
                                            entryNormalX = (Int16)(-u_RayDirX);
                                            entryNormalY = (Int16)(-u_RayDirY);
                                            entryNormalZ = (Int16)(-u_RayDirZ);
                                        }
                                        else
                                        {
                                            x_TraceDebug?.AppendLine("  Ray pointing away from plane");
                                        }
                                    }
                                    else
                                    {
                                        // Ray pointing towards plane

                                        if (t >= 0)
                                        {
                                            x_TraceDebug?.AppendLine("  Ray pointing towards plane, intersection at " + FixedMaths.FixedToFloat(t));
                                            entryDepth = c7_rp_rayStartInsideVolume ? 0 : t;
                                            exitDepth = c7_rp_rayStartInsideVolume ? t : 0x7FFFFFFF;
                                            entryNormalX = c8_rp_normalX;
                                            entryNormalY = c8_rp_normalY;
                                            entryNormalZ = c8_rp_normalZ;
                                            exitNormalX = (Int16)(-c8_rp_normalX);
                                            exitNormalY = (Int16)(-c8_rp_normalY);
                                            exitNormalZ = (Int16)(-c8_rp_normalZ);
                                        }
                                        else
                                        {
                                            x_TraceDebug?.AppendLine("  Ray pointing towards plane, no intersection");
                                        }
                                    }
                                    break;
                                }
                                case Instruction.AABB:
                                case Instruction.AABBSub:
                                case Instruction.AABBAnd:
                                {
                                    int c3_ra_ObjMinX = FixedMaths.ConvertFrom8Dot1((UInt16)((instructionWord >> 8) & 0x1FF));
                                    int c3_ra_ObjMinY = FixedMaths.ConvertFrom8Dot1((UInt16)((instructionWord >> 17) & 0x1FF));
                                    int c3_ra_ObjMinZ = FixedMaths.ConvertFrom8Dot1((UInt16)((instructionWord >> 26) & 0x1FF));
                                    int c3_ra_ObjMaxX = FixedMaths.ConvertFrom8Dot1((UInt16)((instructionWord >> 35) & 0x1FF));
                                    int c3_ra_ObjMaxY = FixedMaths.ConvertFrom8Dot1((UInt16)((instructionWord >> 44) & 0x1FF));
                                    int c3_ra_ObjMaxZ = FixedMaths.ConvertFrom8Dot1((UInt16)((instructionWord >> 53) & 0x1FF));

                                    x_TraceDebug?.AppendLine("  AABB " + FixedMaths.FixedToFloat(c3_ra_ObjMinX) + ", " + FixedMaths.FixedToFloat(c3_ra_ObjMinY) + ", " + FixedMaths.FixedToFloat(c3_ra_ObjMinZ) + " - " + FixedMaths.FixedToFloat(c3_ra_ObjMaxX) + ", " + FixedMaths.FixedToFloat(c3_ra_ObjMaxY) + ", " + FixedMaths.FixedToFloat(c3_ra_ObjMaxZ));

                                    int c4_ra_t0PosX = (c3_ra_ObjMinX + s3_originX) - u_RayStartX;
                                    int c4_ra_t0PosY = (c3_ra_ObjMinY + s3_originY) - u_RayStartY;
                                    int c4_ra_t0PosZ = (c3_ra_ObjMinZ + s3_originZ) - u_RayStartZ;
                                    int c4_ra_t1PosX = (c3_ra_ObjMaxX + s3_originX) - u_RayStartX;
                                    int c4_ra_t1PosY = (c3_ra_ObjMaxY + s3_originY) - u_RayStartY;
                                    int c4_ra_t1PosZ = (c3_ra_ObjMaxZ + s3_originZ) - u_RayStartZ;

                                    x_TraceDebug?.AppendLine("    AABB t0PosX = " + FixedMaths.FixedToFloat(c4_ra_t0PosX) + ", " + FixedMaths.FixedToFloat(c4_ra_t0PosY) + ", " + FixedMaths.FixedToFloat(c4_ra_t0PosZ));
                                    x_TraceDebug?.AppendLine("    AABB t1PosX = " + FixedMaths.FixedToFloat(c4_ra_t1PosX) + ", " + FixedMaths.FixedToFloat(c4_ra_t1PosY) + ", " + FixedMaths.FixedToFloat(c4_ra_t1PosZ));
                                    x_TraceDebug?.AppendLine("    AABB RayDir = " + FixedMaths.FixedToFloat(u_RayDirX) + ", " + FixedMaths.FixedToFloat(u_RayDirY) + ", " + FixedMaths.FixedToFloat(u_RayDirZ));

                                    // We can't use u_RayDirRcp because that's calculated by RayEngine with cycle-emulation and so isn't ready when we do this
                                    int rayDirRcpX = FixedMaths.FixedRcp(u_RayDirX);
                                    int rayDirRcpY = FixedMaths.FixedRcp(u_RayDirY);
                                    int rayDirRcpZ = FixedMaths.FixedRcp(u_RayDirZ);

                                    x_TraceDebug?.AppendLine("    AABB RayDirRcp = " + FixedMaths.FixedToFloat(rayDirRcpX) + ", " + FixedMaths.FixedToFloat(rayDirRcpY) + ", " + FixedMaths.FixedToFloat(rayDirRcpZ));

                                    int c5_ra_t0x = FixedMaths.FixedMul48(c4_ra_t0PosX, rayDirRcpX);
                                    int c5_ra_t0y = FixedMaths.FixedMul48(c4_ra_t0PosY, rayDirRcpY);
                                    int c5_ra_t0z = FixedMaths.FixedMul48(c4_ra_t0PosZ, rayDirRcpZ);
                                    int c5_ra_t1x = FixedMaths.FixedMul48(c4_ra_t1PosX, rayDirRcpX);
                                    int c5_ra_t1y = FixedMaths.FixedMul48(c4_ra_t1PosY, rayDirRcpY);
                                    int c5_ra_t1z = FixedMaths.FixedMul48(c4_ra_t1PosZ, rayDirRcpZ);

                                    x_TraceDebug?.AppendLine("    AABB t0x = " + FixedMaths.FixedToFloat(c5_ra_t0x) + ", " + FixedMaths.FixedToFloat(c5_ra_t0y) + ", " + FixedMaths.FixedToFloat(c5_ra_t0z));
                                    x_TraceDebug?.AppendLine("    AABB t1x = " + FixedMaths.FixedToFloat(c5_ra_t1x) + ", " + FixedMaths.FixedToFloat(c5_ra_t1y) + ", " + FixedMaths.FixedToFloat(c5_ra_t1z));

                                    int c5_ra_t0PosX = c4_ra_t0PosX;
                                    int c5_ra_t0PosY = c4_ra_t0PosY;
                                    int c5_ra_t0PosZ = c4_ra_t0PosZ;
                                    int c5_ra_t1PosX = c4_ra_t1PosX;
                                    int c5_ra_t1PosY = c4_ra_t1PosY;
                                    int c5_ra_t1PosZ = c4_ra_t1PosZ;

                                    int c6_ra_tMinX = Math.Min(c5_ra_t0x, c5_ra_t1x);
                                    int c6_ra_tMinY = Math.Min(c5_ra_t0y, c5_ra_t1y);
                                    int c6_ra_tMinZ = Math.Min(c5_ra_t0z, c5_ra_t1z);

                                    int c6_ra_tMaxX = Math.Max(c5_ra_t0x, c5_ra_t1x);
                                    int c6_ra_tMaxY = Math.Max(c5_ra_t0y, c5_ra_t1y);
                                    int c6_ra_tMaxZ = Math.Max(c5_ra_t0z, c5_ra_t1z);

                                    x_TraceDebug?.AppendLine("    AABB t0   = " + FixedMaths.FixedToFloat(c5_ra_t0x) + ", " + FixedMaths.FixedToFloat(c5_ra_t0y) + ", " + FixedMaths.FixedToFloat(c5_ra_t0z));
                                    x_TraceDebug?.AppendLine("    AABB t1   = " + FixedMaths.FixedToFloat(c5_ra_t1x) + ", " + FixedMaths.FixedToFloat(c5_ra_t1y) + ", " + FixedMaths.FixedToFloat(c5_ra_t1z));
                                    x_TraceDebug?.AppendLine("    AABB tMin = " + FixedMaths.FixedToFloat(c6_ra_tMinX) + ", " + FixedMaths.FixedToFloat(c6_ra_tMinY) + ", " + FixedMaths.FixedToFloat(c6_ra_tMinZ));
                                    x_TraceDebug?.AppendLine("    AABB tMax = " + FixedMaths.FixedToFloat(c6_ra_tMaxX) + ", " + FixedMaths.FixedToFloat(c6_ra_tMaxY) + ", " + FixedMaths.FixedToFloat(c6_ra_tMaxZ));
                               
                                    Int16 fixedOne = (Int16)FixedMaths.FloatToFixed(1.0f);
                                    Int16 fixedMinusOne = (Int16)FixedMaths.FloatToFixed(-1.0f);

                                    if ((c6_ra_tMaxX < c6_ra_tMaxY) && (c6_ra_tMaxX < c6_ra_tMaxZ))
                                    {
                                        // Ray hit X side of box
                                        exitDepth = c6_ra_tMaxX;
                                        exitNormalX = (u_RayDirX > 0) ? fixedOne : fixedMinusOne;
                                        exitNormalY = 0;
                                        exitNormalZ = 0;
                                    }
                                    else if (c6_ra_tMaxY < c6_ra_tMaxZ)
                                    {
                                        // Ray hit Y side of box
                                        exitDepth = c6_ra_tMaxY;
                                        exitNormalX = 0;
                                        exitNormalY = (u_RayDirY > 0) ? fixedOne : fixedMinusOne;
                                        exitNormalZ = 0;
                                    }
                                    else
                                    {
                                        // Ray hit Z side of box
                                        exitDepth = c6_ra_tMaxZ;
                                        exitNormalX = 0;
                                        exitNormalY = 0;
                                        exitNormalZ = (u_RayDirZ > 0) ? fixedOne : fixedMinusOne;
                                    }

                                    // When rayDir is too small 1/rayDir is huge and overflows our 40-bit multiply, so ignore those values
                                    bool rayDirXIsEffectivelyZero = ((u_RayDirX & 0xFF00) == 0) || ((u_RayDirX & 0xFF00) == 0xFF00);
                                    bool rayDirYIsEffectivelyZero = ((u_RayDirY & 0xFF00) == 0) || ((u_RayDirY & 0xFF00) == 0xFF00);
                                    bool rayDirZIsEffectivelyZero = ((u_RayDirZ & 0xFF00) == 0) || ((u_RayDirZ & 0xFF00) == 0xFF00);

                                    if ((exitDepth < 0) ||
                                        ((rayDirXIsEffectivelyZero) && ((c5_ra_t0PosX >= 0) || (c5_ra_t1PosX < 0))) ||
                                        ((rayDirYIsEffectivelyZero) && ((c5_ra_t0PosY >= 0) || (c5_ra_t1PosY < 0))) ||
                                        ((rayDirZIsEffectivelyZero) && ((c5_ra_t0PosZ >= 0) || (c5_ra_t1PosZ < 0))))
                                    {
                                        // AABB entirely behind camera, or one of the ray direction components is zero and we're entirely outside the AABB on that axis
                                        entryDepth = 0x7FFFFFFF;
                                        exitDepth = 0;
                                    }
                                    else if ((c6_ra_tMinX > c6_ra_tMinY) && (c6_ra_tMinX > c6_ra_tMinZ))
                                    {
                                        // Ray hit X side of box
                                        entryDepth = Math.Max(c6_ra_tMinX, 0);
                                        entryNormalX = (u_RayDirX < 0) ? fixedOne : fixedMinusOne;
                                        entryNormalY = 0;
                                        entryNormalZ = 0;
                                    }
                                    else if (c6_ra_tMinY > c6_ra_tMinZ)
                                    {
                                        // Ray hit Y side of box
                                        entryDepth = Math.Max(c6_ra_tMinY, 0);
                                        entryNormalX = 0;
                                        entryNormalY = (u_RayDirY < 0) ? fixedOne : fixedMinusOne;
                                        entryNormalZ = 0;
                                    }
                                    else
                                    {
                                        // Ray hit Z side of box
                                        entryDepth = Math.Max(c6_ra_tMinZ, 0);
                                        entryNormalX = 0;
                                        entryNormalY = 0;
                                        entryNormalZ = (u_RayDirZ < 0) ? fixedOne : fixedMinusOne;
                                    }

                                    break;
                                }
                                default:
                                {
                                    throw new NotImplementedException();
                                }
                            }

                            // Merge

                            x_TraceDebug?.AppendLine("   Intersection range " + FixedMaths.FixedToFloat(entryDepth) + " to " + FixedMaths.FixedToFloat(exitDepth));

                            if (entryDepth >= exitDepth)
                            {
                                // No intersection

                                x_TraceDebug?.AppendLine("   No intersection");
                            }
                            else
                            {
                                // Intersection occurred

                                x_TraceDebug?.AppendLine("   Ray intersects from " + FixedMaths.FixedToFloat(entryDepth) + " - " + FixedMaths.FixedToFloat(exitDepth));
                                x_TraceDebug?.AppendLine("   Entry normal " + FixedMaths.FixedToFloat(entryNormalX) + ", " + FixedMaths.FixedToFloat(entryNormalY) + ", " + FixedMaths.FixedToFloat(entryNormalZ));
                                x_TraceDebug?.AppendLine("   Exit normal " + FixedMaths.FixedToFloat(exitNormalX) + ", " + FixedMaths.FixedToFloat(exitNormalY) + ", " + FixedMaths.FixedToFloat(exitNormalZ));
                            }

                            ObjectMergeType objMergeType;

                            if ((inst == Instruction.PlaneSub) || (inst == Instruction.SphereSub) || (inst == Instruction.AABBSub))
                                objMergeType = ObjectMergeType.Sub;
                            else if ((inst == Instruction.PlaneAnd) || (inst == Instruction.SphereAnd) || (inst == Instruction.AABBAnd))
                                objMergeType = ObjectMergeType.And;
                            else
                                objMergeType = ObjectMergeType.Add;

                            x_TraceDebug?.AppendLine("   Performing " + objMergeType + " merge");
                            x_TraceDebug?.AppendLine("    Hit depth range " + FixedMaths.FixedToFloat(entryDepth) + " - " + FixedMaths.FixedToFloat(exitDepth));
                            x_TraceDebug?.AppendLine("    Existing shape depth range " + FixedMaths.FixedToFloat(s14_HitEntryDepth) + " - " + FixedMaths.FixedToFloat(s14_HitExitDepth));

                            int newEntryDepth = s14_HitEntryDepth;

                            switch (objMergeType)
                            {
                                case ObjectMergeType.Add:
                                {
                                    // Normal object

                                    if (entryDepth < exitDepth)
                                    {
                                        if (s14_HitEntryDepth >= s14_HitExitDepth)
                                        {
                                            // No existing shape, just write our data to the buffer

                                            newEntryDepth = entryDepth;
                                            s14_HitExitDepth = exitDepth;

                                            s14_HitNormalX = entryNormalX;
                                            s14_HitNormalY = entryNormalY;
                                            s14_HitNormalZ = entryNormalZ;
                                        }
                                        else
                                        {
                                            if (entryDepth < s14_HitEntryDepth)
                                            {
                                                x_TraceDebug?.AppendLine("     Updating entry depth " + FixedMaths.FixedToFloat(s14_HitEntryDepth) + " -> " + FixedMaths.FixedToFloat(entryDepth));

                                                newEntryDepth = entryDepth;

                                                s14_HitNormalX = entryNormalX;
                                                s14_HitNormalY = entryNormalY;
                                                s14_HitNormalZ = entryNormalZ;
                                            }
                                            else
                                            {
                                                x_TraceDebug?.AppendLine("     Depth test failed - " + FixedMaths.FixedToFloat(s14_HitEntryDepth) + " > " + FixedMaths.FixedToFloat(entryDepth));
                                            }

                                            if (exitDepth > s14_HitExitDepth)
                                            {
                                                x_TraceDebug?.AppendLine("     Updating exit depth " + FixedMaths.FixedToFloat(s14_HitExitDepth) + " -> " + FixedMaths.FixedToFloat(exitDepth));
                                                s14_HitExitDepth = exitDepth;
                                            }
                                        }
                                    }
                                    break;
                                }
                                case ObjectMergeType.Sub:
                                {
                                    // Subtractive object
                                    // This isn't completely accurate - we don't support clipping out the middle of an object,
                                    // which isn't an issue with only one subtraction but can cause problems if multiple subtractions
                                    // are performed.

                                    if (s14_HitEntryDepth < s14_HitExitDepth) // Only do this if there is an existing shape
                                    {
                                        if ((entryDepth <= s14_HitEntryDepth) && (exitDepth >= s14_HitExitDepth))
                                        {
                                            // Clipping the entire shape
                                            x_TraceDebug?.AppendLine("     Clipping entire shape");
                                            newEntryDepth = 0x7FFFFFFF;
                                            s14_HitExitDepth = 0;
                                        }
                                        else if ((entryDepth < s14_HitEntryDepth) && (exitDepth > s14_HitEntryDepth) && (exitDepth <= s14_HitExitDepth))
                                        {
                                            // Clipping the front part of the shape

                                            x_TraceDebug?.AppendLine("     Clipping front of shape " + FixedMaths.FixedToFloat(s14_HitEntryDepth) + " -> " + FixedMaths.FixedToFloat(exitDepth));

                                            newEntryDepth = exitDepth;

                                            // Normal will be the inverse of our exit normal

                                            s14_HitNormalX = (Int16)(-exitNormalX);
                                            s14_HitNormalY = (Int16)(-exitNormalY);
                                            s14_HitNormalZ = (Int16)(-exitNormalZ);
                                        }
                                        else if ((entryDepth > s14_HitEntryDepth) && (entryDepth < s14_HitExitDepth) && (exitDepth >= s14_HitExitDepth))
                                        {
                                            // Clipping the rear part of the shape

                                            x_TraceDebug?.AppendLine("     Clipping rear of shape " + FixedMaths.FixedToFloat(s14_HitExitDepth) + " -> " + FixedMaths.FixedToFloat(entryDepth));

                                            s14_HitExitDepth = entryDepth;
                                        }

                                        if (newEntryDepth < s14_HitExitDepth)
                                            x_TraceDebug?.AppendLine("     Post-clip shape depth range " + FixedMaths.FixedToFloat(newEntryDepth) + " - " + FixedMaths.FixedToFloat(s14_HitExitDepth));
                                        else
                                            x_TraceDebug?.AppendLine("     Post-clip shape hit was removed");
                                    }
                                    break;
                                }
                                case ObjectMergeType.And:
                                {
                                    // ANDing object
                                    // This isn't completely accurate - we don't support clipping out the middle/rear of an object,
                                    // which isn't an issue with only one subtraction but can cause problems if multiple subtractions
                                    // are performed.

                                    if (s14_HitEntryDepth < s14_HitExitDepth) // Only do this if there is an existing shape
                                    {
                                        if (entryDepth >= exitDepth)
                                        {
                                            x_TraceDebug?.AppendLine("     Operation removed entire shape");
                                            newEntryDepth = 0x7FFFFFFF;
                                            s14_HitExitDepth = 0;
                                        }
                                        else
                                        {
                                            if (entryDepth > s14_HitEntryDepth)
                                            {
                                                x_TraceDebug?.AppendLine("     Updating entry depth " + FixedMaths.FixedToFloat(s14_HitEntryDepth) + " -> " + FixedMaths.FixedToFloat(entryDepth));
                                                newEntryDepth = entryDepth;

                                                s14_HitNormalX = entryNormalX;
                                                s14_HitNormalY = entryNormalY;
                                                s14_HitNormalZ = entryNormalZ;
                                            }

                                            if (exitDepth < s14_HitExitDepth)
                                            {
                                                x_TraceDebug?.AppendLine("     Updating exit depth " + FixedMaths.FixedToFloat(s14_HitExitDepth) + " -> " + FixedMaths.FixedToFloat(exitDepth));
                                                s14_HitExitDepth = exitDepth;
                                            }

                                            if (newEntryDepth >= s14_HitExitDepth)
                                            {
                                                x_TraceDebug?.AppendLine("     Operation removed entire shape");
                                            }
                                        }
                                    }
                                    break;
                                }
                            }

                            s14_HitEntryDepth = newEntryDepth;

                            x_TraceDebug?.AppendLine("    Post-clip depth range " + FixedMaths.FixedToFloat(newEntryDepth) + " - " + FixedMaths.FixedToFloat(s14_HitExitDepth));

                            // Update hit position
                            s14_HitCalculation_HitX = u_RayStartX + FixedMaths.FixedMul(u_RayDirX, newEntryDepth);
                            s14_HitCalculation_HitY = u_RayStartY + FixedMaths.FixedMul(u_RayDirY, newEntryDepth);
                            s14_HitCalculation_HitZ = u_RayStartZ + FixedMaths.FixedMul(u_RayDirZ, newEntryDepth);

                            x_TraceDebug?.AppendLine("    Pos-clip hit pos " + FixedMaths.FixedToFloat(s14_HitCalculation_HitX) + ", " + FixedMaths.FixedToFloat(s14_HitCalculation_HitY) + ", " + FixedMaths.FixedToFloat(s14_HitCalculation_HitZ));
                        }
                        break;
                    }
                    case Instruction.Checkerboard:
                    {
                        if (execute)
                        {
                            x_TraceDebug?.AppendLine("   Checkerboard hit pos " + FixedMaths.FixedToFloat(s14_HitCalculation_HitX) + ", " + FixedMaths.FixedToFloat(s14_HitCalculation_HitY) + ", " + FixedMaths.FixedToFloat(s14_HitCalculation_HitZ));

                            bool tile = (((s14_HitCalculation_HitX >> FixedMaths.FixedShift) & 1) != 0) ^ (((s14_HitCalculation_HitZ >> FixedMaths.FixedShift) & 1) != 0);

                            if (tile)
                            {
                                UInt16 albedo = (UInt16)((instructionWord >> 16) & 0xFFFF);
                                byte reflectiveness = (byte)((instructionWord >> 8) & 0xFF);

                                x_TraceDebug?.AppendLine("   Checkerboard updating albedo to " + ExecEngine.RGB15ToString(albedo) + " reflectiveness " + reflectiveness);

                                s14_RegHitAlbedo = albedo;
                                s14_RegHitReflectiveness = reflectiveness;
                            }
                        }

                        break;
                    }
                    case Instruction.RegisterHit:
                    case Instruction.RegisterHitNoReset:
                    {
                        if (execute)
                        {
                            s14_ObjRegisteredHit = false;

                            if (s14_HitEntryDepth < s14_HitExitDepth)
                            {
                                UInt16 albedo = (UInt16)((instructionWord >> 16) & 0xFFFF);
                                byte reflectiveness = (byte)((instructionWord >> 8) & 0xFF);

                                if ((!s14_RegHit) || (s14_HitEntryDepth < s14_RegHitDepth))
                                {
                                    x_TraceDebug?.AppendLine("  Registering primary hit with albedo " + ExecEngine.RGB15ToString(albedo) + " reflectiveness " + reflectiveness);
                                    x_TraceDebug?.AppendLine("   Hit depth " + FixedMaths.FixedToFloat(s14_HitEntryDepth) + " pos " + FixedMaths.FixedToFloat(s14_HitCalculation_HitX) + ", " + FixedMaths.FixedToFloat(s14_HitCalculation_HitY) + ", " + FixedMaths.FixedToFloat(s14_HitCalculation_HitZ));

                                    s14_RegHit = true;
                                    s14_RegHitDepth = s14_HitEntryDepth;
                                    s14_RegHitX = s14_HitCalculation_HitX;
                                    s14_RegHitY = s14_HitCalculation_HitY;
                                    s14_RegHitZ = s14_HitCalculation_HitZ;
                                    s14_RegHitNormalX = s14_HitNormalX;
                                    s14_RegHitNormalY = s14_HitNormalY;
                                    s14_RegHitNormalZ = s14_HitNormalZ;
                                    s14_RegHitAlbedo = albedo;
                                    s14_RegHitReflectiveness = reflectiveness;
                                    s14_ObjRegisteredHit = true;

                                    if (u_ShadowRay)
                                    {
                                        x_Busy = false;
                                    }
                                }
                                else
                                {
                                    x_TraceDebug?.AppendLine("  Not registering hit because Z-test failed");
                                }

                                if (inst != Instruction.RegisterHitNoReset)
                                {
                                    // Reset hit state
                                    x_TraceDebug?.AppendLine("  Reset hit state");
                                    s14_HitEntryDepth = 0x7FFFFFFF;
                                    s14_HitExitDepth = 0;
                                }
                            }
                            else
                            {
                                x_TraceDebug?.AppendLine("  No hit to register");
                            }
                        }

                        break;
                    }
                    case Instruction.ResetHitState:
                    {
                        if (execute)
                        {
                            s14_HitEntryDepth = 0x7FFFFFFF;
                            s14_HitExitDepth = 0;
                        }

                        break;
                    }

                    case Instruction.Jump:
                    case Instruction.ResetHitStateAndJump:
                    {
                        // The reset happens even if the jump isn't taken
                        if (inst == Instruction.ResetHitStateAndJump)
                        {
                            s14_HitEntryDepth = 0x7FFFFFFF;
                            s14_HitExitDepth = 0;
                        }

                        if (execute)
                        {
                            pc = (int)((instructionWord >> 8) & 0xFFFF);
                        }

                        break;
                    }
                    case Instruction.Origin:
                    {
                        s3_originX = FixedMaths.ConvertFrom8Dot7((UInt32)((instructionWord >> 8) & 0x7FFF));
                        s3_originY = FixedMaths.ConvertFrom8Dot7((UInt32)((instructionWord >> 23) & 0x7FFF));
                        s3_originZ = FixedMaths.ConvertFrom8Dot7((UInt32)((instructionWord >> 38) & 0x7FFF));

                        break;
                    }
                    case Instruction.End:
                    {
                        if (execute)
                        {
                            x_Busy = false;
                        }
                        break;
                    }
                }
            }

            return this;
        }
    }
}
