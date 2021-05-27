using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SRTTestbed
{
    partial class RayEngine
    {
        int SecondaryRayDirectionCalculator_ShadowRayStartX;
        int SecondaryRayDirectionCalculator_ShadowRayStartY;
        int SecondaryRayDirectionCalculator_ShadowRayStartZ;
        Int16 SecondaryRayDirectionCalculator_ShadowRayDirX;
        Int16 SecondaryRayDirectionCalculator_ShadowRayDirY;
        Int16 SecondaryRayDirectionCalculator_ShadowRayDirZ;

        int SecondaryRayDirectionCalculator_ReflectionRayStartX;
        int SecondaryRayDirectionCalculator_ReflectionRayStartY;
        int SecondaryRayDirectionCalculator_ReflectionRayStartZ;
        Int16 SecondaryRayDirectionCalculator_ReflectionRayDirX;
        Int16 SecondaryRayDirectionCalculator_ReflectionRayDirY;
        Int16 SecondaryRayDirectionCalculator_ReflectionRayDirZ;

        public void SecondaryRayDirectionCalculator_Tick()
        {
            bool secondaryPhase = ((Phase == ExecEnginePhase.SecondaryRay) || (Phase == ExecEnginePhase.SecondaryShadow));

            int secondaryRayBiasShift = 4; // Bias for shadow/secondary rays, in terms of a shift (so 4 == /16)

            // Shadow ray

            SecondaryRayDirectionCalculator_ShadowRayStartX = (secondaryPhase ? RegSecondaryHitX : RegPrimaryHitX) + (LightDirX >> secondaryRayBiasShift);
            SecondaryRayDirectionCalculator_ShadowRayStartY = (secondaryPhase ? RegSecondaryHitY : RegPrimaryHitY) + (LightDirY >> secondaryRayBiasShift);
            SecondaryRayDirectionCalculator_ShadowRayStartZ = (secondaryPhase ? RegSecondaryHitZ : RegPrimaryHitZ) + (LightDirZ >> secondaryRayBiasShift);
            SecondaryRayDirectionCalculator_ShadowRayDirX = LightDirX;
            SecondaryRayDirectionCalculator_ShadowRayDirY = LightDirY;
            SecondaryRayDirectionCalculator_ShadowRayDirZ = LightDirZ;

            // Reflection ray

            SecondaryRayDirectionCalculator_ReflectionRayStartX = RegPrimaryHitX + (RegPrimaryHitNormalX >> secondaryRayBiasShift);
            SecondaryRayDirectionCalculator_ReflectionRayStartY = RegPrimaryHitY + (RegPrimaryHitNormalY >> secondaryRayBiasShift);
            SecondaryRayDirectionCalculator_ReflectionRayStartZ = RegPrimaryHitZ + (RegPrimaryHitNormalZ >> secondaryRayBiasShift);

            int normalDotRay = FixedMaths.FixedMul16x16(PrimaryRayDirX, RegPrimaryHitNormalX) + FixedMaths.FixedMul16x16(PrimaryRayDirY, RegPrimaryHitNormalY) + FixedMaths.FixedMul16x16(PrimaryRayDirZ, RegPrimaryHitNormalZ);
            
            SecondaryRayDirectionCalculator_ReflectionRayDirX = (Int16)(PrimaryRayDirX - (FixedMaths.FixedMul16x16(RegPrimaryHitNormalX, normalDotRay) << 1));
            SecondaryRayDirectionCalculator_ReflectionRayDirY = (Int16)(PrimaryRayDirY - (FixedMaths.FixedMul16x16(RegPrimaryHitNormalY, normalDotRay) << 1));
            SecondaryRayDirectionCalculator_ReflectionRayDirZ = (Int16)(PrimaryRayDirZ - (FixedMaths.FixedMul16x16(RegPrimaryHitNormalZ, normalDotRay) << 1));
        }
    }
}
