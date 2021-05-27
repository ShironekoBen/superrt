using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SRTTestbed
{
    partial class RayEngine
    {
        public byte FinalColourCalculator_R;
        public byte FinalColourCalculator_G;
        public byte FinalColourCalculator_B;

        public void FinalColourCalculator_Tick()
        {
            if (RegPrimaryHit && (RegPrimaryHitReflectiveness > 0))
            {
                int invReflectiveness = 255 - RegPrimaryHitReflectiveness;
                int baseR = (PrimaryRayColourR * invReflectiveness) >> 8;
                int baseG = (PrimaryRayColourG * invReflectiveness) >> 8;
                int baseB = (PrimaryRayColourB * invReflectiveness) >> 8;

                int addR = (SecondaryRayColourR * RegPrimaryHitReflectiveness) >> 8;
                int addG = (SecondaryRayColourG * RegPrimaryHitReflectiveness) >> 8;
                int addB = (SecondaryRayColourB * RegPrimaryHitReflectiveness) >> 8;

                FinalColourCalculator_R = (byte)Math.Min(baseR + addR, 255);
                FinalColourCalculator_G = (byte)Math.Min(baseG + addG, 255);
                FinalColourCalculator_B = (byte)Math.Min(baseB + addB, 255);
            }
            else
            {
                // No reflection
                FinalColourCalculator_R = PrimaryRayColourR;
                FinalColourCalculator_G = PrimaryRayColourG;
                FinalColourCalculator_B = PrimaryRayColourB;
            }
        }
    }
}
