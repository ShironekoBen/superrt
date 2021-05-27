using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SRTTestbed
{
    partial class RayEngine
    {
        public byte ColourCalculator_RayR;
        public byte ColourCalculator_RayG;
        public byte ColourCalculator_RayB;

        public void ColourCalculator_Tick()
        {
            bool secondaryPhase = ((Phase == ExecEnginePhase.SecondaryRay) || (Phase == ExecEnginePhase.SecondaryShadow));

            if (secondaryPhase ? RegSecondaryHit : RegPrimaryHit)
            {
                int illumination = FixedMaths.FixedMul16x16(secondaryPhase ? RegSecondaryHitNormalX : RegPrimaryHitNormalX, LightDirX) + FixedMaths.FixedMul16x16(secondaryPhase ? RegSecondaryHitNormalY : RegPrimaryHitNormalY, LightDirY) + FixedMaths.FixedMul16x16(secondaryPhase ? RegSecondaryHitNormalZ : RegPrimaryHitNormalZ, LightDirZ);
                int specIllumination = 0;

                if (illumination < 0)
                {
                    // Anti-light
                    illumination = -(illumination >> 2);
                }
                else if (secondaryPhase ? RegSecondaryShadowHit : RegPrimaryShadowHit)
                {
                    illumination >>= 3;
                }
                else
                {
                    // Calculate specular term (primary only for now as an optimisation)

                    if (!secondaryPhase)
                    {
                        int normalDotRay = FixedMaths.FixedMul16x16(PrimaryRayDirX, RegPrimaryHitNormalX) + FixedMaths.FixedMul16x16(PrimaryRayDirY, RegPrimaryHitNormalY) + FixedMaths.FixedMul16x16(PrimaryRayDirZ, RegPrimaryHitNormalZ);

                        int specDirX = PrimaryRayDirX - (FixedMaths.FixedMul16x16(RegPrimaryHitNormalX, normalDotRay) << 1);
                        int specDirY = PrimaryRayDirY - (FixedMaths.FixedMul16x16(RegPrimaryHitNormalY, normalDotRay) << 1);
                        int specDirZ = PrimaryRayDirZ - (FixedMaths.FixedMul16x16(RegPrimaryHitNormalZ, normalDotRay) << 1);

                        specIllumination = FixedMaths.FixedMul16x16(specDirX, LightDirX) + FixedMaths.FixedMul16x16(specDirY, LightDirY) + FixedMaths.FixedMul16x16(specDirZ, LightDirZ);

                        specIllumination = Math.Max(specIllumination, 0);

                        // Power term
                        specIllumination = FixedMaths.FixedMul16x16(specIllumination, specIllumination);
                        specIllumination = FixedMaths.FixedMul16x16(specIllumination, specIllumination);
                        specIllumination = FixedMaths.FixedMul16x16(specIllumination, specIllumination);

                        specIllumination = specIllumination >> (FixedMaths.FixedShift - 8); // Convert to 0-255 range
                    }
                }

                // Modulate by hit object colour

                UInt16 albedo = secondaryPhase ? RegSecondaryHitAlbedo : RegPrimaryHitAlbedo;

                int hitAlbedoR = ((albedo & 0x1F) << 3);
                int hitAlbedoG = (((albedo >> 5) & 0x1F) << 3);
                int hitAlbedoB = (((albedo >> 10) & 0x1F) << 3);

                // Not using FixedMul because the colour is a regular int
                ColourCalculator_RayR = (byte)Math.Min(((hitAlbedoR * illumination) >> FixedMaths.FixedShift) + specIllumination, 255);
                ColourCalculator_RayG = (byte)Math.Min(((hitAlbedoG * illumination) >> FixedMaths.FixedShift) + specIllumination, 255);
                ColourCalculator_RayB = (byte)Math.Min(((hitAlbedoB * illumination) >> FixedMaths.FixedShift) + specIllumination, 255);
            }
            else
            {
                // No hit, so sky colour
                CalcSkyCol(RayDirX, RayDirY, RayDirZ, false, out ColourCalculator_RayR, out ColourCalculator_RayG, out ColourCalculator_RayB);
            }
        }

        void CalcSkyCol(int rayDirX, int rayDirY, int rayDirZ,
                bool inShadow,
                out byte skyR, out byte skyG, out byte skyB)
        {
            // Calculate sun flare term

            int sunDot = FixedMaths.FixedMul(rayDirX, LightDirX) + FixedMaths.FixedMul(rayDirY, LightDirY) + FixedMaths.FixedMul(rayDirZ, LightDirZ);

            if ((sunDot < 0) || (inShadow))
            {
                sunDot = 0;
            }

            int sunFactor = FixedMaths.FixedMul16x16(sunDot, sunDot);
            int sunFactor2 = FixedMaths.FixedMul16x16(sunFactor, sunFactor);

            byte sunCol = (byte)(sunFactor2 >> (FixedMaths.FixedShift - 8));

            int skyLerp = FixedMaths.FloatToFixed(1.0f) + rayDirY;

            if (skyLerp < 0)
            {
                skyLerp = 0;
            }

            int skyColR = (128 * skyLerp) >> FixedMaths.FixedShift;
            int skyColG = (128 * skyLerp) >> FixedMaths.FixedShift;
            int skyColB = 190;

            skyR = (byte)Math.Min(skyColR + sunCol, 255);
            skyG = (byte)Math.Min(skyColG + sunCol, 255);
            skyB = (byte)Math.Min(skyColB + sunCol, 255);
        }
    }
}
