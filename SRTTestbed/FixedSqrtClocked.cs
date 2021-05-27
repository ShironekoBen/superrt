using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SRTTestbed
{
    // Clocked version of FixedRSqrt latency 4 cycles, throughput 1 cycle
    // (we just emulate the four cycle latency of the hardware version)
    class FixedSqrtClocked
    {
        public int sqrtIn;
        public int result;

        public FixedSqrtClocked Tick()
        {
            FixedSqrtClocked destData = (FixedSqrtClocked)this.MemberwiseClone();

            Cycle1(destData);
            Cycle2(destData);
            Cycle3(destData);
            Cycle4(destData);

            return destData;
        }

        void Cycle1(FixedSqrtClocked destData)
        {
            destData.c2_sqrtIn = sqrtIn;
        }

        int c2_sqrtIn;

        void Cycle2(FixedSqrtClocked destData)
        {
            destData.c3_sqrtIn = c2_sqrtIn;
        }

        int c3_sqrtIn;

        void Cycle3(FixedSqrtClocked destData)
        {
            destData.c4_sqrtIn = c3_sqrtIn;
        }

        int c4_sqrtIn;

        void Cycle4(FixedSqrtClocked destData)
        {
            destData.result = FixedMaths.FixedSqrt(c4_sqrtIn);
        }
    }
}
