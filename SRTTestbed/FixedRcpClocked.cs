using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SRTTestbed
{
    // Clocked version of FixedRcp, latency 4 cycles, throughput 1 cycle
    // (we just emulate the four cycle latency of the hardware version)
    class FixedRcpClocked
    {
        public int rcpIn;
        public int result;

        public FixedRcpClocked Tick()
        {
            FixedRcpClocked destData = (FixedRcpClocked)this.MemberwiseClone();

            Cycle1(destData);
            Cycle2(destData);
            Cycle3(destData);
            Cycle4(destData);

            return destData;
        }

        void Cycle1(FixedRcpClocked destData)
        {
            destData.c2_rcpIn = rcpIn;
        }

        int c2_rcpIn;

        void Cycle2(FixedRcpClocked destData)
        {
            destData.c3_rcpIn = c2_rcpIn;
        }

        int c3_rcpIn;

        void Cycle3(FixedRcpClocked destData)
        {
            destData.c4_rcpIn = c3_rcpIn;
        }

        int c4_rcpIn;

        void Cycle4(FixedRcpClocked destData)
        {
            destData.result = FixedMaths.FixedRcp(c4_rcpIn);
        }
    }
}
