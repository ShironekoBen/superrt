using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

#if true

namespace SRTTestbed
{
    partial class ExecEngine
    {
        int c14_RaySphere_EntryDepth;
        int c14_RaySphere_ExitDepth;
        Int16 c14_RaySphere_EntryNormalX;
        Int16 c14_RaySphere_EntryNormalY;
        Int16 c14_RaySphere_EntryNormalZ;
        Int16 c14_RaySphere_ExitNormalX;
        Int16 c14_RaySphere_ExitNormalY;
        Int16 c14_RaySphere_ExitNormalZ;

        int c14_RayPlane_EntryDepth;
        int c14_RayPlane_ExitDepth;
        Int16 c14_RayPlane_EntryNormalX;
        Int16 c14_RayPlane_EntryNormalY;
        Int16 c14_RayPlane_EntryNormalZ;
        Int16 c14_RayPlane_ExitNormalX;
        Int16 c14_RayPlane_ExitNormalY;
        Int16 c14_RayPlane_ExitNormalZ;

        FixedRcpClocked RaySphereAndPlane_RCPModule = new FixedRcpClocked();
        FixedSqrtClocked RaySphere_SqrtModule = new FixedSqrtClocked();

        void RaySphereAndPlane_Tick(ExecEngine destData)
        {
            destData.RaySphereAndPlane_RCPModule = RaySphereAndPlane_RCPModule.Tick();
            destData.RaySphere_SqrtModule = RaySphere_SqrtModule.Tick();
            RaySphereAndPlane_Cycle2(destData);
            RaySphereAndPlane_Cycle3(destData);
            RaySphereAndPlane_Cycle4(destData);
            RaySphereAndPlane_Cycle5(destData);
            RaySphereAndPlane_Cycle6(destData);
            RaySphereAndPlane_Cycle7(destData);
            RaySphereAndPlane_Cycle8(destData);
            RaySphereAndPlane_Cycle9(destData);
            RaySphereAndPlane_Cycle10(destData);
            RaySphereAndPlane_Cycle11(destData);
            RaySphereAndPlane_Cycle12(destData);
            RaySphereAndPlane_Cycle13(destData);
        }

        void RaySphereAndPlane_Cycle2(ExecEngine destData)
        {            
            // Decode sphere object data
            destData.c3_rs_ObjX = FixedMaths.ConvertFrom8Dot7((UInt32)((c2_InstructionWord >> 8) & 0x7FFF));
            destData.c3_rs_ObjY = FixedMaths.ConvertFrom8Dot7((UInt32)((c2_InstructionWord >> 23) & 0x7FFF));
            destData.c3_rs_ObjZ = FixedMaths.ConvertFrom8Dot7((UInt32)((c2_InstructionWord >> 38) & 0x7FFF));
            destData.c3_rs_ObjRad = FixedMaths.ConvertFrom4Dot7((UInt16)((c2_InstructionWord >> 53) & 0x7FF));

            x_PipelineTracer?.AppendLine(2, "  Sphere pos " + FixedMaths.FixedToFloat(destData.c3_rs_ObjX) + ", " + FixedMaths.FixedToFloat(destData.c3_rs_ObjY) + ", " + FixedMaths.FixedToFloat(destData.c3_rs_ObjZ) + ", Radius = " + FixedMaths.FixedToFloat(destData.c3_rs_ObjRad));

            // Decode plane object data

            destData.c3_rp_ObjNormalX = FixedMaths.ConvertFrom2Dot10((UInt16)((c2_InstructionWord >> 8) & 0xFFF));
            destData.c3_rp_ObjNormalY = FixedMaths.ConvertFrom2Dot10((UInt16)((c2_InstructionWord >> 20) & 0xFFF));
            destData.c3_rp_ObjNormalZ = FixedMaths.ConvertFrom2Dot10((UInt16)((c2_InstructionWord >> 32) & 0xFFF));
            destData.c3_rp_ObjNormalDist = FixedMaths.ConvertFrom8Dot12((UInt32)((c2_InstructionWord >> 44) & 0xFFFFF));

            x_PipelineTracer?.AppendLine(2, "  Plane normal " + FixedMaths.FixedToFloat(destData.c3_rp_ObjNormalX) + ", " + FixedMaths.FixedToFloat(destData.c3_rp_ObjNormalY) + ", " + FixedMaths.FixedToFloat(c3_rp_ObjNormalZ) + ", Dist = " + FixedMaths.FixedToFloat(destData.c3_rp_ObjNormalDist));
        }

        int c3_rs_ObjX;
        int c3_rs_ObjY;
        int c3_rs_ObjZ;
        int c3_rs_ObjRad; // Radius (for spheres)

        Int16 c3_rp_ObjNormalX;
        Int16 c3_rp_ObjNormalY;
        Int16 c3_rp_ObjNormalZ;
        int c3_rp_ObjNormalDist;

        void RaySphereAndPlane_Cycle3(ExecEngine destData)
        {
            bool isSphere = (c3_InstructionWord & 1) == 1; // See Instruction enum for details

            // Perform sphere intersection

            int ocX = u_RayStartX - (c3_rs_ObjX + s3_originX); // Delta from ray start point to sphere
            int ocY = u_RayStartY - (c3_rs_ObjY + s3_originY);
            int ocZ = u_RayStartZ - (c3_rs_ObjZ + s3_originZ);

            x_PipelineTracer?.AppendLine(3, "  Sphere ray delta = " + FixedMaths.FixedToFloat(ocX) + ", " + FixedMaths.FixedToFloat(ocY) + ", " + FixedMaths.FixedToFloat(ocZ));

            // Multiplex some of the multiply ops together

            int mulResult0 = FixedMaths.FixedMul(isSphere ? ocX : c3_rp_ObjNormalX, isSphere ? u_RayDirX : c3_rp_ObjNormalDist);
            int mulResult1 = FixedMaths.FixedMul(isSphere ? ocY : c3_rp_ObjNormalY, isSphere ? u_RayDirY : c3_rp_ObjNormalDist);
            int mulResult2 = FixedMaths.FixedMul(isSphere ? ocZ : c3_rp_ObjNormalZ, isSphere ? u_RayDirZ : c3_rp_ObjNormalDist);

            // Distance along the ray to the closest point in the sphere
            destData.c4_rs_closestPointAlongRay = -(mulResult0 + mulResult1 + mulResult2);
            destData.c4_rs_sphereToRayStartDistSq = FixedMaths.FixedMul(ocX, ocX) + FixedMaths.FixedMul(ocY, ocY) + FixedMaths.FixedMul(ocZ, ocZ);
            destData.c4_rs_radiusSq = FixedMaths.FixedMul(c3_rs_ObjRad, c3_rs_ObjRad);

            x_PipelineTracer?.AppendLine(3, "  Sphere closestPointAlongRay = " + FixedMaths.FixedToFloat(destData.c4_rs_closestPointAlongRay));
            x_PipelineTracer?.AppendLine(3, "  Sphere sphereToRayStartDistSq = " + FixedMaths.FixedToFloat(destData.c4_rs_sphereToRayStartDistSq));
            x_PipelineTracer?.AppendLine(3, "  Sphere radiusSq = " + FixedMaths.FixedToFloat(destData.c4_rs_radiusSq));

            destData.c4_rs_ObjX = c3_rs_ObjX + s3_originX;
            destData.c4_rs_ObjY = c3_rs_ObjY + s3_originY;
            destData.c4_rs_ObjZ = c3_rs_ObjZ + s3_originZ;
            destData.c4_rs_ObjRad = c3_rs_ObjRad;

            destData.c4_rp_pointOnPlaneX = mulResult0 + s3_originX;
            destData.c4_rp_pointOnPlaneY = mulResult1 + s3_originY;
            destData.c4_rp_pointOnPlaneZ = mulResult2 + s3_originZ;

            x_PipelineTracer?.AppendLine(3, "  Plane pointOnPlane " + FixedMaths.FixedToFloat(destData.c4_rp_pointOnPlaneX) + ", " + FixedMaths.FixedToFloat(destData.c4_rp_pointOnPlaneY) + ", " + FixedMaths.FixedToFloat(c4_rp_pointOnPlaneZ));

            destData.c4_rp_ObjNormalX = c3_rp_ObjNormalX;
            destData.c4_rp_ObjNormalY = c3_rp_ObjNormalY;
            destData.c4_rp_ObjNormalZ = c3_rp_ObjNormalZ;
        }

        int c4_rs_closestPointAlongRay;
        int c4_rs_sphereToRayStartDistSq;
        int c4_rs_radiusSq;
        int c4_rs_ObjX;
        int c4_rs_ObjY;
        int c4_rs_ObjZ;
        int c4_rs_ObjRad;

        int c4_rp_pointOnPlaneX;
        int c4_rp_pointOnPlaneY;
        int c4_rp_pointOnPlaneZ;
        Int16 c4_rp_ObjNormalX;
        Int16 c4_rp_ObjNormalY;
        Int16 c4_rp_ObjNormalZ;

        void RaySphereAndPlane_Cycle4(ExecEngine destData)
        {
            int distFromSphereCentreToClosestPointSq = c4_rs_sphereToRayStartDistSq - FixedMaths.FixedMul(c4_rs_closestPointAlongRay, c4_rs_closestPointAlongRay);

            destData.c5_rs_rayStartInsideSphere = (c4_rs_sphereToRayStartDistSq < c4_rs_radiusSq);
            destData.c5_rs_distFromSphereCentreToClosestPointSq = distFromSphereCentreToClosestPointSq;

            destData.RaySphere_SqrtModule.sqrtIn = c4_rs_radiusSq - distFromSphereCentreToClosestPointSq; // Feed into Sqrt module, will get result on cycle 9

            x_PipelineTracer?.AppendLine(4, "  Sphere rayStartInsideSphere = " + destData.c5_rs_rayStartInsideSphere);
            x_PipelineTracer?.AppendLine(4, "  Sphere distFromSphereCentreToClosestPointSq = " + FixedMaths.FixedToFloat(destData.c5_rs_distFromSphereCentreToClosestPointSq));
            x_PipelineTracer?.AppendLine(4, "  Sphere Sqrt input = " + FixedMaths.FixedToFloat(destData.RaySphere_SqrtModule.sqrtIn));

            destData.c5_rs_ObjX = c4_rs_ObjX;
            destData.c5_rs_ObjY = c4_rs_ObjY;
            destData.c5_rs_ObjZ = c4_rs_ObjZ;
            destData.c5_rs_radiusSq = c4_rs_radiusSq;
            destData.c5_rs_closestPointAlongRay = c4_rs_closestPointAlongRay;
            destData.c5_rs_ObjRad = c4_rs_ObjRad;

            destData.c5_rp_deltaX = u_RayStartX - c4_rp_pointOnPlaneX;
            destData.c5_rp_deltaY = u_RayStartY - c4_rp_pointOnPlaneY;
            destData.c5_rp_deltaZ = u_RayStartZ - c4_rp_pointOnPlaneZ;

            x_PipelineTracer?.AppendLine(4, "  Plane ray delta " + FixedMaths.FixedToFloat(destData.c5_rp_deltaX) + ", " + FixedMaths.FixedToFloat(destData.c5_rp_deltaY) + ", " + FixedMaths.FixedToFloat(c5_rp_deltaZ));

            destData.c5_rp_ObjNormalX = c4_rp_ObjNormalX;
            destData.c5_rp_ObjNormalY = c4_rp_ObjNormalY;
            destData.c5_rp_ObjNormalZ = c4_rp_ObjNormalZ;
        }

        int c5_rs_ObjX;
        int c5_rs_ObjY;
        int c5_rs_ObjZ;
        int c5_rs_distFromSphereCentreToClosestPointSq;
        bool c5_rs_rayStartInsideSphere;
        int c5_rs_radiusSq;
        int c5_rs_closestPointAlongRay;
        int c5_rs_ObjRad;

        int c5_rp_deltaX;
        int c5_rp_deltaY;
        int c5_rp_deltaZ;
        Int16 c5_rp_ObjNormalX;
        Int16 c5_rp_ObjNormalY;
        Int16 c5_rp_ObjNormalZ;

        void RaySphereAndPlane_Cycle5(ExecEngine destData)
        {
            destData.c6_rs_ObjX = c5_rs_ObjX;
            destData.c6_rs_ObjY = c5_rs_ObjY;
            destData.c6_rs_ObjZ = c5_rs_ObjZ;
            destData.c6_rs_distFromSphereCentreToClosestPointSq = c5_rs_distFromSphereCentreToClosestPointSq;
            destData.c6_rs_rayStartInsideSphere = c5_rs_rayStartInsideSphere;
            destData.c6_rs_radiusSq = c5_rs_radiusSq;
            destData.c6_rs_closestPointAlongRay = c5_rs_closestPointAlongRay;
            destData.c6_rs_ObjRad = c5_rs_ObjRad;

            destData.c6_rp_dotSided = FixedMaths.FixedMul(c5_rp_deltaX, c5_rp_ObjNormalX) + FixedMaths.FixedMul(c5_rp_deltaY, c5_rp_ObjNormalY) + FixedMaths.FixedMul(c5_rp_deltaZ, c5_rp_ObjNormalZ);

            x_PipelineTracer?.AppendLine(5, "  Plane dotSided = " + FixedMaths.FixedToFloat(destData.c6_rp_dotSided));

            destData.c6_rp_ObjNormalX = c5_rp_ObjNormalX;
            destData.c6_rp_ObjNormalY = c5_rp_ObjNormalY;
            destData.c6_rp_ObjNormalZ = c5_rp_ObjNormalZ;
        }

        int c6_rs_ObjX;
        int c6_rs_ObjY;
        int c6_rs_ObjZ;
        int c6_rs_distFromSphereCentreToClosestPointSq;
        bool c6_rs_rayStartInsideSphere;
        int c6_rs_radiusSq;
        int c6_rs_closestPointAlongRay;
        int c6_rs_ObjRad;

        int c6_rp_dotSided;
        Int16 c6_rp_ObjNormalX;
        Int16 c6_rp_ObjNormalY;
        Int16 c6_rp_ObjNormalZ;

        void RaySphereAndPlane_Cycle6(ExecEngine destData)
        {
            destData.c7_rs_ObjX = c6_rs_ObjX;
            destData.c7_rs_ObjY = c6_rs_ObjY;
            destData.c7_rs_ObjZ = c6_rs_ObjZ;
            destData.c7_rs_distFromSphereCentreToClosestPointSq = c6_rs_distFromSphereCentreToClosestPointSq;
            destData.c7_rs_rayStartInsideSphere = c6_rs_rayStartInsideSphere;
            destData.c7_rs_radiusSq = c6_rs_radiusSq;
            destData.c7_rs_closestPointAlongRay = c6_rs_closestPointAlongRay;
            destData.c7_rs_ObjRad = c6_rs_ObjRad;

            destData.c7_rp_rayStartInsideVolume = (c6_rp_dotSided < 0);

            x_PipelineTracer?.AppendLine(6, "  Plane rayStartInsideVolume = " + destData.c7_rp_rayStartInsideVolume);

            destData.c7_rp_ObjNormalX = c6_rp_ObjNormalX;
            destData.c7_rp_ObjNormalY = c6_rp_ObjNormalY;
            destData.c7_rp_ObjNormalZ = c6_rp_ObjNormalZ;
            destData.c7_rp_dotSided = c6_rp_dotSided;
        }

        int c7_rs_ObjX;
        int c7_rs_ObjY;
        int c7_rs_ObjZ;
        int c7_rs_distFromSphereCentreToClosestPointSq;
        bool c7_rs_rayStartInsideSphere;
        int c7_rs_radiusSq;
        int c7_rs_closestPointAlongRay;
        int c7_rs_ObjRad;

        bool c7_rp_rayStartInsideVolume;
        Int16 c7_rp_ObjNormalX;
        Int16 c7_rp_ObjNormalY;
        Int16 c7_rp_ObjNormalZ;
        int c7_rp_dotSided;

        void RaySphereAndPlane_Cycle7(ExecEngine destData)
        {
            destData.c8_rs_ObjX = c7_rs_ObjX;
            destData.c8_rs_ObjY = c7_rs_ObjY;
            destData.c8_rs_ObjZ = c7_rs_ObjZ;
            destData.c8_rs_distFromSphereCentreToClosestPointSq = c7_rs_distFromSphereCentreToClosestPointSq;
            destData.c8_rs_rayStartInsideSphere = c7_rs_rayStartInsideSphere;
            destData.c8_rs_radiusSq = c7_rs_radiusSq;
            destData.c8_rs_closestPointAlongRay = c7_rs_closestPointAlongRay;
            destData.c8_rs_ObjRad = c7_rs_ObjRad;

            // Flip so we are testing against the back side of the plane
            destData.c8_rp_normalX = c7_rp_rayStartInsideVolume ? (Int16)(-c7_rp_ObjNormalX) : c7_rp_ObjNormalX;
            destData.c8_rp_normalY = c7_rp_rayStartInsideVolume ? (Int16)(-c7_rp_ObjNormalY) : c7_rp_ObjNormalY;
            destData.c8_rp_normalZ = c7_rp_rayStartInsideVolume ? (Int16)(-c7_rp_ObjNormalZ) : c7_rp_ObjNormalZ;
            destData.c8_rp_dot = c7_rp_rayStartInsideVolume ? -c7_rp_dotSided : c7_rp_dotSided;

            destData.c8_rp_rayStartInsideVolume = c7_rp_rayStartInsideVolume;
        }

        int c8_rs_ObjX;
        int c8_rs_ObjY;
        int c8_rs_ObjZ;
        int c8_rs_distFromSphereCentreToClosestPointSq;
        bool c8_rs_rayStartInsideSphere;
        int c8_rs_radiusSq;
        int c8_rs_closestPointAlongRay;
        int c8_rs_ObjRad;

        Int16 c8_rp_normalX;
        Int16 c8_rp_normalY;
        Int16 c8_rp_normalZ;
        int c8_rp_dot;
        bool c8_rp_rayStartInsideVolume;

        void RaySphereAndPlane_Cycle8(ExecEngine destData)
        {
            bool isSphere = (c8_InstructionWord & 1) == 1; // See Instruction enum for details

            destData.c9_rs_ObjX = c8_rs_ObjX;
            destData.c9_rs_ObjY = c8_rs_ObjY;
            destData.c9_rs_ObjZ = c8_rs_ObjZ;
            destData.c9_rs_distFromSphereCentreToClosestPointSq = c8_rs_distFromSphereCentreToClosestPointSq;
            destData.c9_rs_rayStartInsideSphere = c8_rs_rayStartInsideSphere;
            destData.c9_rs_radiusSq = c8_rs_radiusSq;
            destData.c9_rs_closestPointAlongRay = c8_rs_closestPointAlongRay;

            int rp_denom = FixedMaths.FixedMul16x16(u_RayDirX, c8_rp_normalX) + FixedMaths.FixedMul16x16(u_RayDirY, c8_rp_normalY) + FixedMaths.FixedMul16x16(u_RayDirZ, c8_rp_normalZ);

            // Multiplex the RCP module
            if (isSphere)
            {
                destData.RaySphereAndPlane_RCPModule.rcpIn = c8_rs_ObjRad; // Result becomes available on cycle 13
            }
            else
            {
                destData.RaySphereAndPlane_RCPModule.rcpIn = -rp_denom; // Result becomes available on cycle 13
            }

            x_PipelineTracer?.AppendLine(8, "  Ray dir = " + FixedMaths.FixedToFloat(u_RayDirX) + ", " + FixedMaths.FixedToFloat(u_RayDirY) + ", " + FixedMaths.FixedToFloat(u_RayDirZ));
            x_PipelineTracer?.AppendLine(8, "  Plane normal = " + FixedMaths.FixedToFloat(c8_rp_normalX) + ", " + FixedMaths.FixedToFloat(c8_rp_normalY) + ", " + FixedMaths.FixedToFloat(c8_rp_normalZ));
            x_PipelineTracer?.AppendLine(8, "  Plane denom = " + FixedMaths.FixedToFloat(rp_denom));

            destData.c9_rp_normalX = c8_rp_normalX;
            destData.c9_rp_normalY = c8_rp_normalY;
            destData.c9_rp_normalZ = c8_rp_normalZ;
            destData.c9_rp_dot = c8_rp_dot;
            destData.c9_rp_rayStartInsideVolume = c8_rp_rayStartInsideVolume;
        }

        int c9_rs_ObjX;
        int c9_rs_ObjY;
        int c9_rs_ObjZ;
        int c9_rs_distFromSphereCentreToClosestPointSq;
        bool c9_rs_rayStartInsideSphere;
        int c9_rs_radiusSq;
        int c9_rs_closestPointAlongRay;

        Int16 c9_rp_normalX;
        Int16 c9_rp_normalY;
        Int16 c9_rp_normalZ;
        int c9_rp_dot;
        bool c9_rp_rayStartInsideVolume;

        void RaySphereAndPlane_Cycle9(ExecEngine destData)
        {
            int distAlongRayFromClosestPointToSphereSurface = RaySphere_SqrtModule.result;
            x_PipelineTracer?.AppendLine(9, "  Sphere Sqrt output = " + FixedMaths.FixedToFloat(distAlongRayFromClosestPointToSphereSurface));

            destData.c10_rs_entryDepth = c9_rs_rayStartInsideSphere ? 0 : (c9_rs_closestPointAlongRay - distAlongRayFromClosestPointToSphereSurface);
            destData.c10_rs_exitDepth = c9_rs_closestPointAlongRay + distAlongRayFromClosestPointToSphereSurface;

            x_PipelineTracer?.AppendLine(9, "  Sphere entryDepth = " + FixedMaths.FixedToFloat(destData.c10_rs_entryDepth));
            x_PipelineTracer?.AppendLine(9, "  Sphere exitDepth = " + FixedMaths.FixedToFloat(destData.c10_rs_exitDepth));

            destData.c10_rs_ObjX = c9_rs_ObjX;
            destData.c10_rs_ObjY = c9_rs_ObjY;
            destData.c10_rs_ObjZ = c9_rs_ObjZ;
            destData.c10_rs_rayStartInsideSphere = c9_rs_rayStartInsideSphere;
            destData.c10_rs_distFromSphereCentreToClosestPointSq = c9_rs_distFromSphereCentreToClosestPointSq;
            destData.c10_rs_radiusSq = c9_rs_radiusSq;
            destData.c10_rs_closestPointAlongRay = c9_rs_closestPointAlongRay;

            destData.c10_rp_normalX = c9_rp_normalX;
            destData.c10_rp_normalY = c9_rp_normalY;
            destData.c10_rp_normalZ = c9_rp_normalZ;
            destData.c10_rp_dot = c9_rp_dot;
            destData.c10_rp_rayStartInsideVolume = c9_rp_rayStartInsideVolume;
        }

        int c10_rs_entryDepth;
        int c10_rs_exitDepth;
        int c10_rs_ObjX;
        int c10_rs_ObjY;
        int c10_rs_ObjZ;
        bool c10_rs_rayStartInsideSphere;
        int c10_rs_distFromSphereCentreToClosestPointSq;
        int c10_rs_radiusSq;
        int c10_rs_closestPointAlongRay;

        Int16 c10_rp_normalX;
        Int16 c10_rp_normalY;
        Int16 c10_rp_normalZ;
        int c10_rp_dot;
        bool c10_rp_rayStartInsideVolume;

        void RaySphereAndPlane_Cycle10(ExecEngine destData)
        {
            destData.c11_rs_tempHitX = u_RayStartX + FixedMaths.FixedMul(u_RayDirX, c10_rs_entryDepth);
            destData.c11_rs_tempHitY = u_RayStartY + FixedMaths.FixedMul(u_RayDirY, c10_rs_entryDepth);
            destData.c11_rs_tempHitZ = u_RayStartZ + FixedMaths.FixedMul(u_RayDirZ, c10_rs_entryDepth);
            destData.c11_rs_tempHitX2 = u_RayStartX + FixedMaths.FixedMul(u_RayDirX, c10_rs_exitDepth);
            destData.c11_rs_tempHitY2 = u_RayStartY + FixedMaths.FixedMul(u_RayDirY, c10_rs_exitDepth);
            destData.c11_rs_tempHitZ2 = u_RayStartZ + FixedMaths.FixedMul(u_RayDirZ, c10_rs_exitDepth);            

            destData.c11_rs_ObjX = c10_rs_ObjX;
            destData.c11_rs_ObjY = c10_rs_ObjY;
            destData.c11_rs_ObjZ = c10_rs_ObjZ;
            destData.c11_rs_rayStartInsideSphere = c10_rs_rayStartInsideSphere;
            destData.c11_rs_entryDepth = c10_rs_entryDepth;
            destData.c11_rs_exitDepth = c10_rs_exitDepth;
            destData.c11_rs_distFromSphereCentreToClosestPointSq = c10_rs_distFromSphereCentreToClosestPointSq;
            destData.c11_rs_radiusSq = c10_rs_radiusSq;
            destData.c11_rs_closestPointAlongRay = c10_rs_closestPointAlongRay;

            destData.c11_rp_normalX = c10_rp_normalX;
            destData.c11_rp_normalY = c10_rp_normalY;
            destData.c11_rp_normalZ = c10_rp_normalZ;
            destData.c11_rp_dot = c10_rp_dot;
            destData.c11_rp_rayStartInsideVolume = c10_rp_rayStartInsideVolume;
        }

        int c11_rs_tempHitX;
        int c11_rs_tempHitY;
        int c11_rs_tempHitZ;
        int c11_rs_tempHitX2;
        int c11_rs_tempHitY2;
        int c11_rs_tempHitZ2;
        int c11_rs_ObjX;
        int c11_rs_ObjY;
        int c11_rs_ObjZ;
        bool c11_rs_rayStartInsideSphere;
        int c11_rs_entryDepth;
        int c11_rs_exitDepth;
        int c11_rs_distFromSphereCentreToClosestPointSq;
        int c11_rs_radiusSq;
        int c11_rs_closestPointAlongRay;

        Int16 c11_rp_normalX;
        Int16 c11_rp_normalY;
        Int16 c11_rp_normalZ;
        int c11_rp_dot;
        bool c11_rp_rayStartInsideVolume;

        void RaySphereAndPlane_Cycle11(ExecEngine destData)
        {
            destData.c12_rs_tempHitX = c11_rs_tempHitX;
            destData.c12_rs_tempHitY = c11_rs_tempHitY;
            destData.c12_rs_tempHitZ = c11_rs_tempHitZ;
            destData.c12_rs_tempHitX2 = c11_rs_tempHitX2;
            destData.c12_rs_tempHitY2 = c11_rs_tempHitY2;
            destData.c12_rs_tempHitZ2 = c11_rs_tempHitZ2;
            destData.c12_rs_ObjX = c11_rs_ObjX;
            destData.c12_rs_ObjY = c11_rs_ObjY;
            destData.c12_rs_ObjZ = c11_rs_ObjZ;
            destData.c12_rs_rayStartInsideSphere = c11_rs_rayStartInsideSphere;
            destData.c12_rs_entryDepth = c11_rs_entryDepth;
            destData.c12_rs_exitDepth = c11_rs_exitDepth;
            destData.c12_rs_distFromSphereCentreToClosestPointSq = c11_rs_distFromSphereCentreToClosestPointSq;
            destData.c12_rs_radiusSq = c11_rs_radiusSq;
            destData.c12_rs_closestPointAlongRay = c11_rs_closestPointAlongRay;

            destData.c12_rp_normalX = c11_rp_normalX;
            destData.c12_rp_normalY = c11_rp_normalY;
            destData.c12_rp_normalZ = c11_rp_normalZ;
            destData.c12_rp_dot = c11_rp_dot;
            destData.c12_rp_rayStartInsideVolume = c11_rp_rayStartInsideVolume;
        }

        int c12_rs_tempHitX;
        int c12_rs_tempHitY;
        int c12_rs_tempHitZ;
        int c12_rs_tempHitX2;
        int c12_rs_tempHitY2;
        int c12_rs_tempHitZ2;
        int c12_rs_ObjX;
        int c12_rs_ObjY;
        int c12_rs_ObjZ;
        bool c12_rs_rayStartInsideSphere;
        int c12_rs_entryDepth;
        int c12_rs_exitDepth;
        int c12_rs_distFromSphereCentreToClosestPointSq;
        int c12_rs_radiusSq;
        int c12_rs_closestPointAlongRay;

        Int16 c12_rp_normalX;
        Int16 c12_rp_normalY;
        Int16 c12_rp_normalZ;
        int c12_rp_dot;
        bool c12_rp_rayStartInsideVolume;

        void RaySphereAndPlane_Cycle12(ExecEngine destData)
        {
            destData.c13_rs_tempHitX = c12_rs_tempHitX;
            destData.c13_rs_tempHitY = c12_rs_tempHitY;
            destData.c13_rs_tempHitZ = c12_rs_tempHitZ;
            destData.c13_rs_tempHitX2 = c12_rs_tempHitX2;
            destData.c13_rs_tempHitY2 = c12_rs_tempHitY2;
            destData.c13_rs_tempHitZ2 = c12_rs_tempHitZ2;
            destData.c13_rs_ObjX = c12_rs_ObjX;
            destData.c13_rs_ObjY = c12_rs_ObjY;
            destData.c13_rs_ObjZ = c12_rs_ObjZ;
            destData.c13_rs_rayStartInsideSphere = c12_rs_rayStartInsideSphere;
            destData.c13_rs_entryDepth = c12_rs_entryDepth;
            destData.c13_rs_exitDepth = c12_rs_exitDepth;
            destData.c13_rs_distFromSphereCentreToClosestPointSq = c12_rs_distFromSphereCentreToClosestPointSq;
            destData.c13_rs_radiusSq = c12_rs_radiusSq;
            destData.c13_rs_closestPointAlongRay = c12_rs_closestPointAlongRay;

            destData.c13_rp_normalX = c12_rp_normalX;
            destData.c13_rp_normalY = c12_rp_normalY;
            destData.c13_rp_normalZ = c12_rp_normalZ;
            destData.c13_rp_dot = c12_rp_dot;
            destData.c13_rp_rayStartInsideVolume = c12_rp_rayStartInsideVolume;
        }

        int c13_rs_tempHitX;
        int c13_rs_tempHitY;
        int c13_rs_tempHitZ;
        int c13_rs_tempHitX2;
        int c13_rs_tempHitY2;
        int c13_rs_tempHitZ2;
        int c13_rs_ObjX;
        int c13_rs_ObjY;
        int c13_rs_ObjZ;
        bool c13_rs_rayStartInsideSphere;
        int c13_rs_entryDepth;
        int c13_rs_exitDepth;
        int c13_rs_distFromSphereCentreToClosestPointSq;
        int c13_rs_radiusSq;
        int c13_rs_closestPointAlongRay;

        Int16 c13_rp_normalX;
        Int16 c13_rp_normalY;
        Int16 c13_rp_normalZ;
        int c13_rp_dot;
        bool c13_rp_rayStartInsideVolume;

        void RaySphereAndPlane_Cycle13(ExecEngine destData)
        {
            x_PipelineTracer?.AppendLine(13, "  RCP result = " + FixedMaths.FixedToFloat(RaySphereAndPlane_RCPModule.result));

            int rs_invSphereRad = RaySphereAndPlane_RCPModule.result;

            destData.c14_RaySphere_EntryNormalX = c13_rs_rayStartInsideSphere ? (Int16)(-u_RayDirX) : (Int16)FixedMaths.FixedMul(c13_rs_tempHitX - c13_rs_ObjX, rs_invSphereRad);
            destData.c14_RaySphere_EntryNormalY = c13_rs_rayStartInsideSphere ? (Int16)(-u_RayDirY) : (Int16)FixedMaths.FixedMul(c13_rs_tempHitY - c13_rs_ObjY, rs_invSphereRad);
            destData.c14_RaySphere_EntryNormalZ = c13_rs_rayStartInsideSphere ? (Int16)(-u_RayDirZ) : (Int16)FixedMaths.FixedMul(c13_rs_tempHitZ - c13_rs_ObjZ, rs_invSphereRad);

            destData.c14_RaySphere_ExitNormalX = (Int16)FixedMaths.FixedMul(c13_rs_tempHitX2 - c13_rs_ObjX, rs_invSphereRad);
            destData.c14_RaySphere_ExitNormalY = (Int16)FixedMaths.FixedMul(c13_rs_tempHitY2 - c13_rs_ObjY, rs_invSphereRad);
            destData.c14_RaySphere_ExitNormalZ = (Int16)FixedMaths.FixedMul(c13_rs_tempHitZ2 - c13_rs_ObjZ, rs_invSphereRad);

            x_PipelineTracer?.AppendLine(13, "  Sphere closestPointAlongRay = " + FixedMaths.FixedToFloat(c13_rs_closestPointAlongRay));
            x_PipelineTracer?.AppendLine(13, "  Sphere rayStartInsideSphere = " + c13_rs_rayStartInsideSphere);
            x_PipelineTracer?.AppendLine(13, "  Sphere distFromSphereCentreToClosestPointSq = " + FixedMaths.FixedToFloat(c13_rs_distFromSphereCentreToClosestPointSq));
            x_PipelineTracer?.AppendLine(13, "  Sphere entryDepth = " + FixedMaths.FixedToFloat(c13_rs_entryDepth));

            // Ray must either point towards the sphere or start inside it to have a chance of intersecting
            if (((c13_rs_closestPointAlongRay >= 0) || (c13_rs_rayStartInsideSphere)) &&
                (c13_rs_distFromSphereCentreToClosestPointSq < c13_rs_radiusSq) && // Check ray actually intersects sphere
                (c13_rs_entryDepth >= 0)) // Check sphere is in front of us
            {
                x_PipelineTracer?.AppendLine(13, "  Sphere hit from " + FixedMaths.FixedToFloat(c13_rs_entryDepth) + " to " + FixedMaths.FixedToFloat(c13_rs_exitDepth));
                destData.c14_RaySphere_EntryDepth = c13_rs_entryDepth;
                destData.c14_RaySphere_ExitDepth = c13_rs_exitDepth;
            }
            else
            {
                x_PipelineTracer?.AppendLine(13, "  Sphere not hit");
                destData.c14_RaySphere_EntryDepth = 0x7FFFFFFF;
                destData.c14_RaySphere_ExitDepth = 0;
            }

            x_PipelineTracer?.AppendLine(13, "  Final cycle sphere hit from " + FixedMaths.FixedToFloat(c14_RaySphere_EntryDepth) + " to " + FixedMaths.FixedToFloat(c14_RaySphere_ExitDepth));

            int rcpDenom = RaySphereAndPlane_RCPModule.result;

            x_PipelineTracer?.AppendLine(13, "  Plane RCPOut = " + FixedMaths.FixedToFloat(rcpDenom) + " dot = " + FixedMaths.FixedToFloat(c13_rp_dot));

            int t = FixedMaths.FixedMul(c13_rp_dot, rcpDenom);

            x_PipelineTracer?.AppendLine(13, "  Plane t = " + FixedMaths.FixedToFloat(t));

            // Assume no collision
            destData.c14_RayPlane_EntryDepth = 0x7FFFFFFF;
            destData.c14_RayPlane_ExitDepth = 0;

            if (rcpDenom < 0) // Was (denom >= 0), but rcpDemon is available here and has the opposite sign
            {
                // Ray pointing away from plane, so ray is either entirely inside or entirely outside it, depending on where it started

                if (c13_rp_rayStartInsideVolume)
                {
                    x_PipelineTracer?.AppendLine(13, "  Ray entirely inside plane");
                    // Entirely inside plane
                    destData.c14_RayPlane_EntryDepth = 0;
                    destData.c14_RayPlane_ExitDepth = 0x7FFFFFFF;
                    destData.c14_RayPlane_EntryNormalX = (Int16)(-u_RayDirX);
                    destData.c14_RayPlane_EntryNormalY = (Int16)(-u_RayDirY);
                    destData.c14_RayPlane_EntryNormalZ = (Int16)(-u_RayDirZ);
                }
                else
                {
                    x_PipelineTracer?.AppendLine(13, "  Ray pointing away from plane");
                }
            }
            else
            {
                // Ray pointing towards plane

                if (t >= 0)
                {
                    x_PipelineTracer?.AppendLine(13, "  Ray pointing towards plane, intersection at " + FixedMaths.FixedToFloat(t));
                    destData.c14_RayPlane_EntryDepth = c13_rp_rayStartInsideVolume ? 0 : t;
                    destData.c14_RayPlane_ExitDepth = c13_rp_rayStartInsideVolume ? t : 0x7FFFFFFF;
                    destData.c14_RayPlane_EntryNormalX = c13_rp_normalX;
                    destData.c14_RayPlane_EntryNormalY = c13_rp_normalY;
                    destData.c14_RayPlane_EntryNormalZ = c13_rp_normalZ;
                    destData.c14_RayPlane_ExitNormalX = (Int16)(-c13_rp_normalX);
                    destData.c14_RayPlane_ExitNormalY = (Int16)(-c13_rp_normalY);
                    destData.c14_RayPlane_ExitNormalZ = (Int16)(-c13_rp_normalZ);
                }
                else
                {
                    x_PipelineTracer?.AppendLine(13, "  Ray pointing towards plane, no intersection");
                }
            }
        }
    }
}

#endif