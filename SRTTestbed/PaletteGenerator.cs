using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Drawing;
using System.Diagnostics;

namespace SRTTestbed
{
    public class PaletteGenerator
    {
        int[] ColourCount = new int[0x8000];

        UInt16[] Entry = new ushort[256];
        int NumEntries = 0;
        byte[] Map = new byte[0x8000]; // One entry for each 15bpp colour indicating what 8bpp index it maps to

        public static UInt16 ColourToRGB555(Color col)
        {
            return (UInt16)((col.R >> 3) | ((col.G >> 3) << 5) | ((col.B >> 3) << 10));
        }

        public static Color RGB555ToColour(UInt16 col)
        {
            byte r, g, b;
            RGB555Split(col, out r, out g, out b);
            return Color.FromArgb(0xFF, r, g, b);
        }

        public static UInt16 ColourToRGB555(byte r, byte g, byte b)
        {
            return (UInt16)((r>> 3) | ((g >> 3) << 5) | ((b >> 3) << 10));
        }

        public static void RGB555Split(UInt16 col, out byte r, out byte g, out byte b)
        {
            r = (byte)((col & 0x1F) << 3);
            g = (byte)(((col >> 5) & 0x1F) << 3);
            b = (byte)(((col >> 10) & 0x1F) << 3);

            // Replicate low bits

            if (((r >> 3) & 1) != 0)
                r |= 0x7;
            if (((g >> 3) & 1) != 0)
                g |= 0x7;
            if (((b >> 3) & 1) != 0)
                b |= 0x7;
        }

        // Dither matrix
        const int orderedDitherMatrixWidth = 4;
        const int orderedDitherMatrixHeight = 2;

        // The 4x2 matrix here is "right" in that values are in the 0-7 (3 bit range), however the 4x4 matrix
        // results in the whole scene ending up slightly dithered rather than having bands of dither/non-dither.
        // However it's mathematically more "wrong".
        static byte[,] orderedDitherMatrix = new byte[orderedDitherMatrixWidth, orderedDitherMatrixHeight]
        {
            { 0, 3 },
            { 4, 7 },
            { 2, 1 },
            { 6, 5 }
        };
        /*{
            { 0, 8, 2, 10 },
            { 12, 4, 14, 6 },
            { 3, 11, 1, 9 },
            { 15, 7, 13, 5 }
        };     */   

        public void AddImage(Bitmap src, bool dither)
        {
            for (int y = 0; y < src.Height; y++)
            {
                for (int x = 0; x < src.Width; x++)
                {
                    Color srcCol = src.GetPixel(x, y);

                    if (dither)
                    {
                        byte ditherVal = orderedDitherMatrix[x % orderedDitherMatrixWidth, y % orderedDitherMatrixHeight];
                        srcCol = Color.FromArgb(Math.Min(srcCol.R + ditherVal, 255), Math.Min(srcCol.G + ditherVal, 255), Math.Min(srcCol.B + ditherVal, 255));
                    }

                    UInt16 c = ColourToRGB555(srcCol);

                    ColourCount[c]++;
                }
            }
        }

        // Converts a bitmap to RGB555 format (no actual format conversion, just reducing the colour depth)
        public static Bitmap ConvertBitmapToRGB555(Bitmap src, bool dither)
        {
            Bitmap dest = new Bitmap(src.Width, src.Height);

            for (int y = 0; y < src.Height; y++)
            {
                for (int x = 0; x < src.Width; x++)
                {
                    Color srcCol = src.GetPixel(x, y);

                    if (dither)
                    {
                        byte ditherVal = orderedDitherMatrix[x % orderedDitherMatrixWidth, y % orderedDitherMatrixHeight];
                        srcCol = Color.FromArgb(Math.Min(srcCol.R + ditherVal, 255), Math.Min(srcCol.G + ditherVal, 255), Math.Min(srcCol.B + ditherVal, 255));
                    }

                    UInt16 c = ColourToRGB555(srcCol);

                    Color actualCol = RGB555ToColour(c);

                    dest.SetPixel(x, y, actualCol);
                }
            }

            return dest;
        }

        // Converts a bitmap image to this palette
        // (output bitmap is not actually an 8bpp bitmap, just reduced to only use 256 colours)
        public Bitmap ConvertBitmap(Bitmap src, bool dither)
        {
            Bitmap dest = new Bitmap(src.Width, src.Height);

            for (int y = 0; y < src.Height; y++)
            {
                for (int x = 0; x < src.Width; x++)
                {
                    Color srcCol = src.GetPixel(x, y);

                    if (dither)
                    {
                        byte ditherVal = orderedDitherMatrix[x % orderedDitherMatrixWidth, y % orderedDitherMatrixHeight];
                        srcCol = Color.FromArgb(Math.Min(srcCol.R + ditherVal, 255), Math.Min(srcCol.G + ditherVal, 255), Math.Min(srcCol.B + ditherVal, 255));
                    }

                    UInt16 c = ColourToRGB555(srcCol);

                    byte palIndex = Map[c];

                    Color actualCol = RGB555ToColour(Entry[palIndex]);

                    dest.SetPixel(x, y, actualCol);
                }
            }

            return dest;
        }

        // Map a single colour to the palette
        public byte MapColour(UInt16 col)
        {
            return Map[col];
        }

        // Generate a test bitmap with the whole palette in it
        public Bitmap GeneratePaletteBitmap()
        {
            int width = 256;
            int height = 256;

            int xStep = width / 16;
            int yStep = height / 16;

            Bitmap dest = new Bitmap(width, height);

            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    int index = (x / xStep) + ((y / yStep) * 16);

                    Color actualCol = RGB555ToColour(Entry[index]);

                    dest.SetPixel(x, y, actualCol);
                }
            }

            return dest;
        }

        // Returns a SNES-format 256-entry palette
        public byte[] GetSNESPaletteData()
        {
            byte[] palData = new byte[256 * 2];

            for (int i = 0; i < 256; i++)
            {
                byte r, g, b;

                if (i < NumEntries)
                {
                    RGB555Split(Entry[i], out r, out g, out b);
                }
                else
                {
                    r = g = b = 0;
                }

                palData[i * 2] = (byte)((r >> 3) | (((g >> 3) & 7) << 5));
                palData[(i * 2) + 1] = (byte)((g >> 6) | ((b >> 3) << 2));
            }

            return palData;
        }

        // Returns a palette map (one entry per 15 bit source colour)
        public byte[] GetPaletteMap()
        {
            return Map;
        }

        public void AddFixedColour(int index, Color col)
        {
            if (index != NumEntries)
                throw new Exception("Fixed colours must be added in index order");

            Entry[NumEntries++] = ColourToRGB555(col);
        }

        class Node
        {
            public Node Parent; // Our parent node
        }

        class SplitNode : Node
        {
            public int Axis; // Which axis is this split on?
            public int SplitPoint; // Where is the split point?
            public Node Left; // Left (<SplitPoint)
            public Node Right; // Right (>=SplitPoint)
        }

        class LeafNode : Node
        {            
            public UInt16 Colour; // Leaf colour
            public int Index; // Leaf colour index
            public float ErrorR; // Leaf error factor
            public float ErrorG; // Leaf error factor
            public float ErrorB; // Leaf error factor
            public int NumPixels; // Number of pixels in leaf
            public int[] ColourCount = new int[0x10000]; // Colours in leaf (technically we could calculate this when needed, but this is easier)
        }

        public void GeneratePalette()
        {
            // Create initial node

            Node rootNode = new LeafNode();
            ((LeafNode)rootNode).ColourCount = ColourCount;
            UpdateLeafData((LeafNode)rootNode);

            List<LeafNode> allLeaves = new List<LeafNode>();
            allLeaves.Add((LeafNode)rootNode);

            int numSplitsNeeded = (256 - NumEntries) - 1;

            for (int i = 0; i < numSplitsNeeded; i++)
            {
                // Find the leaf with the highest error

                allLeaves.Sort((x, y) => -((x.ErrorR + x.ErrorG + x.ErrorB).CompareTo(y.ErrorR + y.ErrorG + y.ErrorB)));

                LeafNode leafToSplit = allLeaves[0];

                Node newSplitNode = SplitLeaf(leafToSplit);

                if (newSplitNode == leafToSplit)
                {
                    // Split achieved nothing, so give up
                    break;
                }

                allLeaves.Remove(leafToSplit);
                AddLeaves(allLeaves, newSplitNode);

                if (leafToSplit.Parent != null)
                {
                    if (((SplitNode)leafToSplit.Parent).Left == leafToSplit)
                    {
                        ((SplitNode)leafToSplit.Parent).Left = newSplitNode;
                    }
                    else if (((SplitNode)leafToSplit.Parent).Right == leafToSplit)
                    {
                        ((SplitNode)leafToSplit.Parent).Right = newSplitNode;
                    }
                    else
                    {
                        throw new Exception("Malformed tree");
                    }
                }
                else
                {
                    rootNode = newSplitNode;
                }
            }

            // Now we have a list representing all the colours we want, so add them to our colour entries

            // Order palette by importance
            //allLeaves.Sort((x, y) => (-x.NumPixels.CompareTo(y.NumPixels)));
            // Order palette by colour
            allLeaves.Sort((x, y) => (-x.Colour.CompareTo(y.Colour)));

            foreach (LeafNode leaf in allLeaves)
            {
                leaf.Index = NumEntries;
                Entry[NumEntries++] = leaf.Colour;
            }

            // And generate a palette map from the node tree

            GeneratePaletteMap(rootNode);

            //DumpNode(rootNode);
        }

        // Recursively add all leaves to a list
        void AddLeaves(List<LeafNode> leafList, Node node)
        {
            if (node == null)
                return;

            if (node is LeafNode)
            {
                leafList.Add((LeafNode)node);
            }
            else if (node is SplitNode)
            {
                AddLeaves(leafList, ((SplitNode)node).Left);
                AddLeaves(leafList, ((SplitNode)node).Right);
            }
        }

        // Update the colour and error factor/etc of a leaf
        void UpdateLeafData(LeafNode leaf)
        {
            // Calculate average colour

            float totalR, totalG, totalB;
            float totalSamples = 0;
            totalR = totalG = totalB = 0;
            leaf.NumPixels = 0;

            for (int i = 0; i < leaf.ColourCount.Length; i++)
            {
                if (leaf.ColourCount[i] > 0)
                {
                    byte r, g, b;
                    RGB555Split((UInt16)i, out r, out g, out b);
                    totalR += r * leaf.ColourCount[i];
                    totalG += g * leaf.ColourCount[i];
                    totalB += b * leaf.ColourCount[i];
                    totalSamples += leaf.ColourCount[i];
                    leaf.NumPixels += leaf.ColourCount[i];
                }
            }

            int leafR = (int)Math.Round(totalR / totalSamples);
            int leafG = (int)Math.Round(totalG / totalSamples);
            int leafB = (int)Math.Round(totalB / totalSamples);

            leaf.Colour = ColourToRGB555((byte)leafR, (byte)leafG, (byte)leafB);

            // Calculate error factors

            float totalErrorR = 0.0f;
            float totalErrorG = 0.0f;
            float totalErrorB = 0.0f;

            for (int i = 0; i < leaf.ColourCount.Length; i++)
            {
                if (leaf.ColourCount[i] > 0)
                {
                    byte r, g, b;
                    RGB555Split((UInt16)i, out r, out g, out b);

                    float errorR = Math.Abs(r - leafR);
                    float errorG = Math.Abs(g - leafG);
                    float errorB = Math.Abs(b - leafB);

                    //float error = (float)Math.Sqrt(/*(errorR * errorR) + (errorB * errorB) +*/ (errorB * errorB));

                    totalErrorR += (float)Math.Sqrt(errorR * errorR) * leaf.ColourCount[i];
                    totalErrorG += (float)Math.Sqrt(errorG * errorG) * leaf.ColourCount[i];
                    totalErrorB += (float)Math.Sqrt(errorB * errorB) * leaf.ColourCount[i];
                }
            }

            leaf.ErrorR = totalErrorR;
            leaf.ErrorG = totalErrorG;
            leaf.ErrorB = totalErrorB;
        }

        // Split a leaf node (if possible)
        Node SplitLeaf(LeafNode srcLeaf)
        {
            int minR, minG, minB, maxR, maxG, maxB;
            float totalR, totalG, totalB;
            float totalSamples = 0;
            minR = minG = minB = 255;
            maxR = maxG = maxB = 0;
            totalR = totalG = totalB = 0;

            for (int i = 0; i < srcLeaf.ColourCount.Length; i++)
            {
                if (srcLeaf.ColourCount[i] > 0)
                {
                    byte r, g, b;
                    RGB555Split((UInt16)i, out r, out g, out b);
                    minR = Math.Min(minR, r);
                    minG = Math.Min(minG, g);
                    minB = Math.Min(minB, b);
                    maxR = Math.Max(maxR, r);
                    maxG = Math.Max(maxG, g);
                    maxB = Math.Max(maxB, b);
                    totalR += r;
                    totalG += g;
                    totalB += b;
                    totalSamples += 1;
                }
            }

            if (totalSamples < 2)
            {
                // Not enough samples to split
                return srcLeaf;
            }

            if ((minR == maxR) && (minG == maxG) && (minB == maxB))
            {
                // Entire leaf is one colour, so cannot split
                return srcLeaf;
            }

            // Pick the axis with the largest variance to split on

            int splitAxis;
            int splitPoint;

            int varianceR = maxR - minR;
            int varianceG = maxG - minG;
            int varianceB = maxB - minB;

            if ((srcLeaf.ErrorG > srcLeaf.ErrorR) && (srcLeaf.ErrorG > srcLeaf.ErrorB))
            {
                splitAxis = 1;
                splitPoint = (maxG + minG) / 2;// (int)Math.Floor(totalG / totalSamples);
            }
            else if (srcLeaf.ErrorB > srcLeaf.ErrorR)
            {
                splitAxis = 2;
                splitPoint = (maxB + minB) / 2;// (int)Math.Floor(totalB / totalSamples);
            }
            else
            {
                splitAxis = 0;
                splitPoint = (maxR + minR) / 2;// (int)Math.Floor(totalR / totalSamples);
            }

            SplitNode splitNode = new SplitNode();
            splitNode.Axis = splitAxis;
            splitNode.SplitPoint = splitPoint;

            LeafNode leftLeaf = new LeafNode();
            LeafNode rightLeaf = new LeafNode();
            splitNode.Left = leftLeaf;
            splitNode.Right = rightLeaf;

            bool leftHasData = false;
            bool rightHasData = false;

            for (int i = 0; i < srcLeaf.ColourCount.Length; i++)
            {
                byte r, g, b;
                RGB555Split((UInt16)i, out r, out g, out b);

                bool isLeft = false;

                switch(splitAxis)
                {
                    case 0: isLeft = r <= splitPoint; break;
                    case 1: isLeft = g <= splitPoint; break;
                    case 2: isLeft = b <= splitPoint; break;
                }

                if (isLeft)
                {
                    leftLeaf.ColourCount[i] = srcLeaf.ColourCount[i];
                    if (leftLeaf.ColourCount[i] > 0)
                        leftHasData = true;
                }
                else
                {
                    rightLeaf.ColourCount[i] = srcLeaf.ColourCount[i];
                    if (rightLeaf.ColourCount[i] > 0)
                        rightHasData = true;
                }
            }

            if ((!leftHasData) || (!rightHasData))
            {
                // Split achieved nothing, so abandon it
                return srcLeaf;
            }

            splitNode.Parent = srcLeaf.Parent;
            leftLeaf.Parent = splitNode;
            rightLeaf.Parent = splitNode;

            UpdateLeafData(leftLeaf);
            UpdateLeafData(rightLeaf);

            return splitNode;
        }

        // Returns a palette map (one entry per 15 bit source colour)
        void GeneratePaletteMap(Node rootNode)
        {
            for (int i = 0; i < 0x8000; i++)
            {
                byte r, g, b;
                RGB555Split((UInt16)i, out r, out g, out b);

                // Traverse tree
                
                Node current = rootNode;

                while (current is SplitNode)
                {
                    SplitNode splitNode = (SplitNode)current;

                    bool isLeft = false;

                    switch (splitNode.Axis)
                    {
                        case 0: isLeft = r <= splitNode.SplitPoint; break;
                        case 1: isLeft = g <= splitNode.SplitPoint; break;
                        case 2: isLeft = b <= splitNode.SplitPoint; break;
                    }

                    current = isLeft ? splitNode.Left : splitNode.Right;
                }

                LeafNode leaf = (LeafNode)current; // If this isn't a leaf at this point then something went very wrong

                Map[i] = (byte)leaf.Index;
            }
        }

        void DumpNode(Node node)
        {
            if (node is LeafNode)
            {
                LeafNode leaf = (LeafNode)node;

                byte r, g, b;
                RGB555Split(leaf.Colour, out r, out g, out b);

                Debug.WriteLine("Leaf " + r + ", " + g + ", " + b + " error " + leaf.ErrorR + ", " + leaf.ErrorG + ", " + leaf.ErrorB + " pixels " + leaf.NumPixels);
            }
            else if (node is SplitNode)
            {
                SplitNode split = (SplitNode)node;

                string splitAxisName = "??";

                switch (split.Axis)
                {
                    case 0: splitAxisName = "R"; break;
                    case 1: splitAxisName = "G"; break;
                    case 2: splitAxisName = "B"; break;
                }


                Debug.WriteLine("Split axis " + splitAxisName + " point " + split.SplitPoint);
                Debug.WriteLine(splitAxisName + "<=" + split.SplitPoint);
                Debug.Indent();
                DumpNode(split.Left);
                Debug.Unindent();
                Debug.WriteLine(splitAxisName + ">" + split.SplitPoint);
                Debug.Indent();
                DumpNode(split.Right);
                Debug.Unindent();
            }
            else
            {
                Debug.WriteLine("Unknown node type!");
            }
        }
    }
}