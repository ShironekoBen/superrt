using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using SharpDX;
using Instruction = SRTTestbed.ExecEngine.Instruction;
using Condition = SRTTestbed.ExecEngine.Condition;
using ObjectMergeType = SRTTestbed.ExecEngine.ObjectMergeType;

namespace SRTTestbed
{
    class SceneCompiler
    {
        class CompilerState
        {
            public List<UInt64> Commands;
            public Dictionary<int, int> EditPoints;
            public StringBuilder Messages;
            public Vector3 CurrentOrigin = Vector3.Zero;
            public bool VisualiseCulling = false;
        }

        struct NodeBounds
        {
            public bool Valid; // Is this bounding volume valid?
            public BoundingBox AABB;
            public BoundingSphere Sphere;

            // Additive merge
            public NodeBounds Merge(NodeBounds b)
            {
                if (!b.Valid)
                    return this;

                if (!Valid)
                    return b;

                NodeBounds result = this;

                result.AABB = BoundingBox.Merge(AABB, b.AABB);
                result.Sphere = BoundingSphere.Merge(Sphere, b.Sphere);

                return result;
            }

            // Logical AND two bounding boxes together
            public NodeBounds And(NodeBounds b)
            {
                if (!b.Valid)
                    return this;

                if (!Valid)
                    return b;

                NodeBounds result = this;

                result.AABB.Minimum.X = Math.Max(AABB.Minimum.X, b.AABB.Minimum.X);
                result.AABB.Minimum.Y = Math.Max(AABB.Minimum.Y, b.AABB.Minimum.Y);
                result.AABB.Minimum.Z = Math.Max(AABB.Minimum.Z, b.AABB.Minimum.Z);

                result.Sphere = BoundingSphere.FromBox(result.AABB);

                return result;
            }
        }

        class SceneNode
        {
            public Vector3 Pos;
            public float Yaw, Pitch, Roll;
            public Matrix LocalToWorldMat;
            public List<SceneNode> Children = new List<SceneNode>();

            public virtual bool CanHaveChildren
            {
                get
                {
                    return true;
                }
            }

            public void CalculateMatrices(Matrix current)
            {
                Matrix localMat = 
                    Matrix.RotationYawPitchRoll((Yaw * (float)Math.PI) / 180.0f, (Pitch * (float)Math.PI) / 180.0f, (Roll * (float)Math.PI) / 180.0f) *
                    Matrix.Translation(Pos);

                LocalToWorldMat = localMat * current;

                foreach (SceneNode child in Children)
                {
                    child.CalculateMatrices(LocalToWorldMat);
                }
            }

            // Get the bounds of this node and all children
            // Requires CalculateMatrices() to have been called
            public NodeBounds GetOverallBounds()
            {
                NodeBounds bounds = GetLocalBounds();

                foreach (SceneNode child in Children)
                {
                    NodeBounds childBounds = child.GetOverallBounds();

                    if (child is SceneGeom)
                    {
                        SceneGeom geomChild = (SceneGeom)child;

                        switch (geomChild.MergeType)
                        {
                            case ObjectMergeType.Add: bounds = bounds.Merge(childBounds); break;
                            case ObjectMergeType.And: bounds = bounds.And(childBounds); break;
                            case ObjectMergeType.Sub: break; // Can't do anything more clever with this without a lot of work
                            default: throw new NotImplementedException();
                        }
                        
                    }
                    else
                    {
                        bounds = bounds.Merge(childBounds);
                    }
                }

                return bounds;
            }

            // Get the bounds of just the geometry in this node
            public virtual NodeBounds GetLocalBounds()
            {
                return new NodeBounds();
            }

            public virtual void Compile(CompilerState state)
            {
                foreach (SceneNode child in Children)
                {
                    child.Compile(state);
                }
            }
        }

        class SceneCullingNode : SceneNode
        {
            public override void Compile(CompilerState state)
            {
                int instructionCountBeforeStarting = state.Commands.Count;

                NodeBounds bounds = GetOverallBounds();

                // Add enough to the bounds to make sure they are conservative even after the reduction to lower-precision
                // fixed point values in the primitives (mainly important for AABBs as those only have 8.1 accuracy)
                bounds.AABB.Maximum.X += 0.5f;
                bounds.AABB.Maximum.Y += 0.5f;
                bounds.AABB.Maximum.Z += 0.5f;
                bounds.Sphere.Radius += 1.0f / 25.0f;

                int jumpPoint = -1;

                if (!bounds.Valid)
                {
                    state.Messages.AppendLine("Warning: Ignoring culling box because bounds are not valid");
                }
                else if (bounds.Sphere.Radius > 1000.0f)
                {
                    state.Messages.AppendLine("Warning: Ignoring culling box because bounds are huge");
                }
                else
                {
                    // Pick AABB or sphere check based on which covers the smaller volume

                    float aabbVol = bounds.AABB.Width * bounds.AABB.Height * bounds.AABB.Depth;
                    float sphereVol = (float)Math.Pow(bounds.Sphere.Radius, 3.0f) * (float)Math.PI * (4.0f / 3.0f);

                    if (aabbVol < sphereVol)
                    {
                        AddAABBToCommandBufferNoRegisterHit(state.Commands, state.CurrentOrigin,
                            bounds.AABB.Minimum.X, bounds.AABB.Minimum.Y, bounds.AABB.Minimum.Z,
                            bounds.AABB.Maximum.X, bounds.AABB.Maximum.Y, bounds.AABB.Maximum.Z);
                    }
                    else
                    {
                        AddSphereToCommandBufferNoRegisterHit(state.Commands, state.CurrentOrigin, bounds.Sphere.Center.X, bounds.Sphere.Center.Y, bounds.Sphere.Center.Z, bounds.Sphere.Radius);
                    }

                    if (state.VisualiseCulling)
                    {
                        // Visualise bounding volume
                        AddRegisterHitToCommandBuffer(state.Commands, 0, 255, 255, 0, noReset: true);
                    }

                    jumpPoint = AddJump(state.Commands, Condition.NH, resetHitState: true);
                }

                foreach (SceneNode child in Children)
                {
                    child.Compile(state);
                }

                if (jumpPoint >= 0)
                {
                    const int minInstructionsForCullingToBeWorthwhile = 2 + 2; // Two cycles for the test and jump instructions, plus another two for the jump (this presumes the prediction is correct!)

                    int instructionsInsideCullingBlock = state.Commands.Count - jumpPoint;

                    if (instructionsInsideCullingBlock <= minInstructionsForCullingToBeWorthwhile)
                    {
                        state.Messages.AppendLine("Warning: Removing culling box because culling costs more than the contents");

                        state.Commands.RemoveRange(instructionCountBeforeStarting, state.Commands.Count - instructionCountBeforeStarting);

                        foreach (SceneNode child in Children)
                        {
                            child.Compile(state);
                        }
                    }
                    else
                    {
                        SetJumpTarget(state.Commands, jumpPoint);
                    }
                }
            }
        }

        class SceneEditPoint : SceneNode
        {
            public int EditPointIndex;

            public override void Compile(CompilerState state)
            {
                state.EditPoints[EditPointIndex] = state.Commands.Count;

                foreach (SceneNode child in Children)
                {
                    child.Compile(state);
                }

                if (state.EditPoints[EditPointIndex] == state.Commands.Count)
                {
                    // Nothing was emitted, so erase the edit point
                    state.EditPoints.Remove(EditPointIndex);
                }
            }
        }

        class SceneOriginNode: SceneNode
        {
            public override void Compile(CompilerState state)
            {
                Vector3 oldOrigin = state.CurrentOrigin;

                state.CurrentOrigin = Pos;

                int initialCommand = state.Commands.Count;

                AddOriginToCommandBuffer(state.Commands, Pos.X, Pos.Y, Pos.Z);

                foreach (SceneNode child in Children)
                {
                    child.Compile(state);
                }

                state.CurrentOrigin = oldOrigin;

                if (initialCommand == state.Commands.Count)
                {
                    // Nothing was emitted, so erase the origin command
                    state.Commands.RemoveAt(initialCommand);
                }
                else
                {
                    AddOriginToCommandBuffer(state.Commands, oldOrigin.X, oldOrigin.Y, oldOrigin.Z);
                }
            }
        }

        class SceneObj : SceneNode
        {
            public float ColR, ColG, ColB;
            public float Reflectivity;
            public bool Checkerboard;
            public float CheckerboardColR, CheckerboardColG, CheckerboardColB, CheckerboardReflectivity;

            public override void Compile(CompilerState state)
            {
                // Don't emit anything if it doesn't look like we have any geometry
                if (Children.Count < 1)
                    return;

                foreach (SceneNode child in Children)
                {
                    child.Compile(state);
                }

                EmitRegisterHit(state);
            }

            public void EmitRegisterHit(CompilerState state)
            {
                byte r = (byte)(Math.Min(Math.Max(ColR, 0.0f), 1.0f) * 255.0f);
                byte g = (byte)(Math.Min(Math.Max(ColG, 0.0f), 1.0f) * 255.0f);
                byte b = (byte)(Math.Min(Math.Max(ColB, 0.0f), 1.0f) * 255.0f);
                byte reflectivity = (byte)(Math.Min(Math.Max(Reflectivity, 0.0f), 1.0f) * 255.0f);

                AddRegisterHitToCommandBuffer(state.Commands, r, g, b, reflectivity, noReset: Checkerboard);

                if (Checkerboard)
                {
                    byte checkerboardR = (byte)(Math.Min(Math.Max(CheckerboardColR, 0.0f), 1.0f) * 255.0f);
                    byte checkerboardG = (byte)(Math.Min(Math.Max(CheckerboardColG, 0.0f), 1.0f) * 255.0f);
                    byte checkerboardB = (byte)(Math.Min(Math.Max(CheckerboardColB, 0.0f), 1.0f) * 255.0f);
                    byte checkerboardReflectivity = (byte)(Math.Min(Math.Max(CheckerboardReflectivity, 0.0f), 1.0f) * 255.0f);
                    AddCheckerboardToCommandBuffer(state.Commands, checkerboardR, checkerboardG, checkerboardB, checkerboardReflectivity);
                    state.Commands.Add(ExecEngine.BuildInstruction(ExecEngine.Instruction.ResetHitState));
                }
            }
        }

        class SceneConvexHull : SceneObj
        {
            public override void Compile(CompilerState state)
            {
                // Collect points

                Vector3[] points = GetPoints();

                if (points.Length < 4)
                {
                    throw new Exception("Not enough points to form convex hull");
                }

                // Convert points into planes

                Plane[] planes = GetConvexHullFromPointCloud(points);

                if (planes.Length < 4)
                {
                    throw new Exception("Convex hull did not generate enough planes");
                }

                // Emit planes

                AddPlaneToCommandBufferNoRegisterHit(state.Commands, state.CurrentOrigin, planes[0].Normal.X, planes[0].Normal.Y, planes[0].Normal.Z, planes[0].Dist, ObjectMergeType.Add);
                for (int i = 1; i < planes.Length; i++)
                {
                    AddPlaneToCommandBufferNoRegisterHit(state.Commands, state.CurrentOrigin, planes[i].Normal.X, planes[i].Normal.Y, planes[i].Normal.Z, planes[i].Dist, ObjectMergeType.And);
                }

                // Emit any child elements

                foreach (SceneNode child in Children)
                {
                    child.Compile(state);
                }

                // Emit register hit stuff

                EmitRegisterHit(state);
            }

            public override NodeBounds GetLocalBounds()
            {
                NodeBounds result = new NodeBounds();

                Vector3[] points = GetPoints();

                result.Valid = true;
                result.AABB = BoundingBox.FromPoints(points);
                result.Sphere = BoundingSphere.FromPoints(points);

                return result;
            }

            Vector3[] GetPoints()
            {
                List<Vector3> points = new List<Vector3>();

                foreach (SceneNode child in Children)
                {
                    if (child is SceneConvexHullPoint)
                    {
                        SceneConvexHullPoint pointNode = (SceneConvexHullPoint)child;

                        Vector3 worldPos = Vector3.TransformCoordinate(Vector3.Zero, pointNode.LocalToWorldMat);

                        points.Add(worldPos);
                    }
                }

                return points.ToArray();
            }
        }

        class SceneConvexHullPoint : SceneNode
        {
        }

        class SceneGeom : SceneNode
        {
            public ObjectMergeType MergeType;

            public override bool CanHaveChildren
            {
                get
                {
                    return false;
                }
            }
        }

        class SceneSphere : SceneGeom
        {
            public float Radius;

            public override void Compile(CompilerState state)
            {
                Vector3 worldPos = Vector3.TransformCoordinate(Vector3.Zero, LocalToWorldMat);

                AddSphereToCommandBufferNoRegisterHit(state.Commands, state.CurrentOrigin, worldPos.X, worldPos.Y, worldPos.Z, Radius, MergeType);
            }

            public override NodeBounds GetLocalBounds()
            {
                NodeBounds result = new NodeBounds();

                result.Valid = true;
                result.Sphere = new BoundingSphere(Vector3.TransformCoordinate(Vector3.Zero, LocalToWorldMat), Radius);
                result.AABB = BoundingBox.FromSphere(result.Sphere);

                return result;
            }
        }

        class SceneCuboid : SceneGeom
        {
            public Vector3 Size;
            public bool AllowAABB;

            public override void Compile(CompilerState state)
            {
                if ((LocalToWorldMat.M11 == 1.0f) &&
                    (LocalToWorldMat.M22 == 1.0f) &&
                    (LocalToWorldMat.M33 == 1.0f) &&
                    AllowAABB)
                {
                    // Axis-aligned

                    Vector3 min = Vector3.TransformCoordinate(-Size * 0.5f, LocalToWorldMat);
                    Vector3 max = Vector3.TransformCoordinate(Size * 0.5f, LocalToWorldMat);

                    AddAABBToCommandBufferNoRegisterHit(state.Commands, state.CurrentOrigin, min.X, min.Y, min.Z, max.X, max.Y, max.Z, MergeType);
                }
                else
                {
                    // Rotated, need to use planes

                    if (MergeType != ObjectMergeType.Add)
                    {
                        throw new NotImplementedException("Cannot perform non-add operations on rotated cuboids");
                    }

                    Vector3[] points = new Vector3[8];

                    for (int i = 0; i < 8; i++)
                    {
                        Vector3 localPos = new Vector3(((i & 1) != 0) ? Size.X : -Size.X,
                            ((i & 2) != 0) ? Size.Y : -Size.Y,
                            ((i & 4) != 0) ? Size.Z : -Size.Z) * 0.5f;

                        points[i] = Vector3.TransformCoordinate(localPos, LocalToWorldMat);
                    }

                    AddPlaneToCommandBufferNoRegisterHit(state.Commands, state.CurrentOrigin, new Vector3[] { points[0], points[1], points[3] }, ObjectMergeType.Add); // Front
                    AddPlaneToCommandBufferNoRegisterHit(state.Commands, state.CurrentOrigin, new Vector3[] { points[4], points[6], points[5] }, ObjectMergeType.And); // Back
                    AddPlaneToCommandBufferNoRegisterHit(state.Commands, state.CurrentOrigin, new Vector3[] { points[3], points[7], points[6] }, ObjectMergeType.And); // Bottom
                    AddPlaneToCommandBufferNoRegisterHit(state.Commands, state.CurrentOrigin, new Vector3[] { points[0], points[4], points[5] }, ObjectMergeType.And); // Top
                    AddPlaneToCommandBufferNoRegisterHit(state.Commands, state.CurrentOrigin, new Vector3[] { points[6], points[4], points[0] }, ObjectMergeType.And); // Left
                    AddPlaneToCommandBufferNoRegisterHit(state.Commands, state.CurrentOrigin, new Vector3[] { points[1], points[5], points[7] }, ObjectMergeType.And); // Right
                }
            }

            public override NodeBounds GetLocalBounds()
            {
                NodeBounds result = new NodeBounds();

                Vector3[] points = new Vector3[8];

                for (int i = 0; i < 8; i++)
                {
                    Vector3 localPos = new Vector3(((i & 1) != 0) ? Size.X : -Size.X,
                        ((i & 2) != 0) ? Size.Y : -Size.Y,
                        ((i & 4) != 0) ? Size.Z : -Size.Z) * 0.5f;

                    points[i] = Vector3.TransformCoordinate(localPos, LocalToWorldMat);
                }

                result.Valid = true;
                result.Sphere = BoundingSphere.FromPoints(points);
                result.AABB = BoundingBox.FromPoints(points);

                return result;
            }
        }

        class ScenePlane : SceneGeom
        {
            public Vector3 Normal;
            public float Distance;
            
            public static ScenePlane FromPointAndNormal(float pointX, float pointY, float pointZ, float normalX, float normalY, float normalZ)
            {
                FixedMaths.Normalise(ref normalX, ref normalY, ref normalZ);

                ScenePlane plane = new ScenePlane();
                plane.Normal.X = normalX;
                plane.Normal.Y = normalY;
                plane.Normal.Z = normalZ;

                plane.Distance = (pointX * normalX) + (pointY * normalY) + (pointZ * normalZ);

                return plane;
            }

            public static ScenePlane FromThreePoints(Vector3[] points)
            {
                Vector3 normal = -Vector3.Cross(points[1] - points[0], points[2] - points[0]);
                normal.Normalize();
                float distance = (points[0].X * normal.X) + (points[0].Y * normal.Y) + (points[0].Z * normal.Z);

                ScenePlane plane = new ScenePlane();
                plane.Normal = normal;
                plane.Distance = distance;

                return plane;
            }

            public override void Compile(CompilerState state)
            {
                Vector3 worldPos = Vector3.TransformCoordinate(Normal * Distance, LocalToWorldMat);
                Vector3 worldNormal = Vector3.TransformNormal(Normal, LocalToWorldMat);

                float distance = (worldPos.X * worldNormal.X) + (worldPos.Y * worldNormal.Y) + (worldPos.Z * worldNormal.Z);

                AddPlaneToCommandBufferNoRegisterHit(state.Commands, state.CurrentOrigin, worldNormal.X, worldNormal.Y, worldNormal.Z, distance, MergeType);
            }

            public override NodeBounds GetLocalBounds()
            {
                NodeBounds result = new NodeBounds();

                Vector3 worldPos = Vector3.TransformCoordinate(Normal * Distance, LocalToWorldMat);

                // Effectively infinite size
                result.Valid = true;
                result.Sphere = new BoundingSphere(worldPos, 100000.0f);
                result.AABB = BoundingBox.FromSphere(result.Sphere);

                return result;
            }
        }

        public bool Compile(String source, out UInt64[] commandBuffer, out int[] editPoints, out String messages, bool visualiseCulling)
        {
            StringBuilder msg = new StringBuilder();
            bool success = true;
            commandBuffer = null;
            editPoints = null;

            try
            {
                Stack<SceneNode> nodeStack = new Stack<SceneNode>();

                SceneNode rootNode = new SceneNode();
                nodeStack.Push(rootNode);

                SceneNode currentNode = rootNode;
                bool inBlockComment = false;

                int lineIndex = 0;
                foreach (string rawLine in source.Split('\n'))
                {
                    lineIndex++;
                    string line = rawLine.Trim().ToLower();

                    // Trim comments
                    if (line.IndexOf('#') >= 0)
                    {
                        line = line.Substring(0, line.IndexOf('#')).TrimEnd();
                    }

                    if (line.Length == 0)
                        continue;

                    string[] bits = line.Split(new char[] { ' ', ',', '\t' }, StringSplitOptions.RemoveEmptyEntries);

                    string command = bits[0];

                    if (inBlockComment)
                    {
                        if (command == @"*/")
                        {
                            inBlockComment = false;
                        }
                        continue;
                    }

                    ObjectMergeType mergeType = ObjectMergeType.Add;

                    if (command.Length > 1)
                    {
                        if (command[0] == '+')
                        {
                            mergeType = ObjectMergeType.Add;
                            command = command.Substring(1);
                        }
                        else if (command[0] == '-')
                        {
                            mergeType = ObjectMergeType.Sub;
                            command = command.Substring(1);
                        }
                        else if (command[0] == '&')
                        {
                            mergeType = ObjectMergeType.And;
                            command = command.Substring(1);
                        }
                    }

                    if (command == "{")
                    {
                        if ((currentNode == null) || (!currentNode.CanHaveChildren))
                        {
                            throw new Exception("Unexpected {");
                        }
                        nodeStack.Push(currentNode);
                        currentNode = null;
                    }
                    else if (command == "}")
                    {
                        if (nodeStack.Count == 0)
                        {
                            throw new Exception("Unexpected }");
                        }
                        currentNode = nodeStack.Pop();
                    }
                    else if (command == @"/*")
                    {
                        inBlockComment = true; // Really crappy line-based block comment support
                    }
                    else if (command == "node")
                    {
                        SceneNode obj = new SceneNode();
                        currentNode = obj;
                        nodeStack.Peek().Children.Add(currentNode);
                        obj.Pos.X = (bits.Length > 1) ? float.Parse(bits[1]) : 0.0f;
                        obj.Pos.Y = (bits.Length > 1) ? float.Parse(bits[2]) : 0.0f;
                        obj.Pos.Z = (bits.Length > 1) ? float.Parse(bits[3]) : 0.0f;
                        obj.Yaw = (bits.Length > 4) ? float.Parse(bits[4]) : 0.0f;
                        obj.Pitch = (bits.Length > 5) ? float.Parse(bits[5]) : 0.0f;
                        obj.Roll = (bits.Length > 6) ? float.Parse(bits[6]) : 0.0f;
                    }
                    else if (command == "origin")
                    {
                        SceneOriginNode obj = new SceneOriginNode();
                        currentNode = obj;
                        nodeStack.Peek().Children.Add(currentNode);
                        obj.Pos.X = (bits.Length > 1) ? float.Parse(bits[1]) : 0.0f;
                        obj.Pos.Y = (bits.Length > 1) ? float.Parse(bits[2]) : 0.0f;
                        obj.Pos.Z = (bits.Length > 1) ? float.Parse(bits[3]) : 0.0f;
                        obj.Yaw = (bits.Length > 4) ? float.Parse(bits[4]) : 0.0f;
                        obj.Pitch = (bits.Length > 5) ? float.Parse(bits[5]) : 0.0f;
                        obj.Roll = (bits.Length > 6) ? float.Parse(bits[6]) : 0.0f;
                    }
                    else if (command == "cull")
                    {
                        SceneCullingNode obj = new SceneCullingNode();
                        currentNode = obj;
                        nodeStack.Peek().Children.Add(currentNode);
                    }
                    else if (command == "editpoint")
                    {
                        SceneEditPoint editPoint = new SceneEditPoint();
                        currentNode = editPoint;
                        nodeStack.Peek().Children.Add(currentNode);

                        editPoint.EditPointIndex = int.Parse(bits[1]);
                    }
                    else if (command == "obj")
                    {
                        SceneObj obj = new SceneObj();
                        currentNode = obj;
                        nodeStack.Peek().Children.Add(currentNode);
                        obj.ColR = float.Parse(bits[1]);
                        obj.ColG = float.Parse(bits[2]);
                        obj.ColB = float.Parse(bits[3]);
                        obj.Reflectivity = (bits.Length > 4) ? float.Parse(bits[4]) : 0.0f;
                    }
                    else if (command == "convexhull")
                    {
                        SceneConvexHull obj = new SceneConvexHull();
                        currentNode = obj;
                        nodeStack.Peek().Children.Add(currentNode);
                        obj.ColR = float.Parse(bits[1]);
                        obj.ColG = float.Parse(bits[2]);
                        obj.ColB = float.Parse(bits[3]);
                        obj.Reflectivity = (bits.Length > 4) ? float.Parse(bits[4]) : 0.0f;
                    }
                    else if (command == "sphere")
                    {
                        if (!(nodeStack.Peek() is SceneObj) && !(nodeStack.Peek() is SceneEditPoint))
                        {
                            throw new Exception("Primitives can only be added to objects");
                        }

                        SceneSphere obj = new SceneSphere();
                        currentNode = obj;
                        nodeStack.Peek().Children.Add(currentNode);
                        obj.Pos = new Vector3(float.Parse(bits[1]), float.Parse(bits[2]), float.Parse(bits[3]));
                        obj.Radius = float.Parse(bits[4]);
                        obj.MergeType = mergeType;
                    }
                    else if (command == "plane")
                    {
                        if (!(nodeStack.Peek() is SceneObj) && !(nodeStack.Peek() is SceneEditPoint))
                        {
                            throw new Exception("Primitives can only be added to objects");
                        }

                        ScenePlane obj = ScenePlane.FromPointAndNormal(float.Parse(bits[1]), float.Parse(bits[2]), float.Parse(bits[3]), float.Parse(bits[4]), float.Parse(bits[5]), float.Parse(bits[6]));
                        currentNode = obj;
                        nodeStack.Peek().Children.Add(currentNode);
                        obj.MergeType = mergeType;
                    }
                    else if (command == "planepoints")
                    {
                        if (!(nodeStack.Peek() is SceneObj) && !(nodeStack.Peek() is SceneEditPoint))
                        {
                            throw new Exception("Primitives can only be added to objects");
                        }

                        ScenePlane obj = ScenePlane.FromThreePoints(new Vector3[] {
                            new Vector3(float.Parse(bits[1]), float.Parse(bits[2]), float.Parse(bits[3])),
                            new Vector3(float.Parse(bits[4]), float.Parse(bits[5]), float.Parse(bits[6])),
                            new Vector3(float.Parse(bits[7]), float.Parse(bits[8]), float.Parse(bits[9])) });
                        currentNode = obj;
                        nodeStack.Peek().Children.Add(currentNode);
                        obj.MergeType = mergeType;
                    }
                    else if (command == "cuboid")
                    {
                        if (!(nodeStack.Peek() is SceneObj) && !(nodeStack.Peek() is SceneEditPoint))
                        {
                            throw new Exception("Primitives can only be added to objects");
                        }

                        SceneCuboid obj = new SceneCuboid();
                        currentNode = obj;
                        nodeStack.Peek().Children.Add(currentNode);
                        obj.Pos = new Vector3(float.Parse(bits[1]), float.Parse(bits[2]), float.Parse(bits[3]));
                        obj.Size = new Vector3(float.Parse(bits[4]), float.Parse(bits[5]), float.Parse(bits[6]));
                        obj.MergeType = mergeType;
                        obj.AllowAABB = false;
                    }
                    else if (command == "aabb")
                    {
                        if (!(nodeStack.Peek() is SceneObj) && !(nodeStack.Peek() is SceneEditPoint))
                        {
                            throw new Exception("Primitives can only be added to objects");
                        }

                        SceneCuboid obj = new SceneCuboid();
                        currentNode = obj;
                        nodeStack.Peek().Children.Add(currentNode);
                        obj.Pos = new Vector3(float.Parse(bits[1]), float.Parse(bits[2]), float.Parse(bits[3]));
                        obj.Size = new Vector3(float.Parse(bits[4]), float.Parse(bits[5]), float.Parse(bits[6]));
                        obj.MergeType = mergeType;
                        obj.AllowAABB = true;
                    }
                    else if (command == "point")
                    {
                        if (!(nodeStack.Peek() is SceneConvexHull))
                        {
                            throw new Exception("Points can only be added to convex hulls");
                        }

                        SceneConvexHullPoint obj = new SceneConvexHullPoint();
                        currentNode = obj;
                        nodeStack.Peek().Children.Add(currentNode);
                        obj.Pos = new Vector3(float.Parse(bits[1]), float.Parse(bits[2]), float.Parse(bits[3]));
                    }
                    else if (command == "checkerboard")
                    {
                        SceneObj parent = nodeStack.Peek() as SceneObj;

                        if (parent == null)
                        {
                            throw new Exception("Checkerboard command must be a child of an object");
                        }

                        parent.Checkerboard = true;
                        parent.CheckerboardColR = float.Parse(bits[1]);
                        parent.CheckerboardColG = float.Parse(bits[2]);
                        parent.CheckerboardColB = float.Parse(bits[3]);
                        parent.CheckerboardReflectivity = (bits.Length > 4) ? float.Parse(bits[4]) : 0.0f;
                    }                   
                    else
                    {
                        throw new Exception("Unknown command " + command);
                    }
                }

                List<UInt64> commands = new List<UInt64>();
                CompilerState state = new CompilerState();
                state.EditPoints = new Dictionary<int, int>();
                state.Commands = commands;
                state.Messages = msg;
                state.VisualiseCulling = visualiseCulling;

                state.Commands.Add(ExecEngine.BuildInstruction(Instruction.Start));

                rootNode.CalculateMatrices(Matrix.Identity);
                rootNode.Compile(state);

                state.Commands.Add(ExecEngine.BuildInstruction(Instruction.End));

                msg.AppendLine("Compiled to " + state.Commands.Count + " instructions with " + state.EditPoints.Count + " edit points");

                commandBuffer = commands.ToArray();

                int maxEditPoint = -1;
                foreach (var editPoint in state.EditPoints)
                {
                    maxEditPoint = Math.Max(maxEditPoint, editPoint.Key);
                }

                editPoints = new int[maxEditPoint + 1];

                foreach (var editPoint in state.EditPoints)
                {
                    editPoints[editPoint.Key] = editPoint.Value;
                }
            }
            catch (Exception e)
            {
                msg.AppendLine(e.ToString());
                success = false;
            }
            
            messages = msg.ToString();

            return success;
        }

        static void AddOriginToCommandBuffer(List<UInt64> commands, float x, float y, float z, bool eliminateRedundantOperations = true)
        {
            // If the previous command was also an origin command then it's redundant and can be removed
            if ((commands.Count > 0) && eliminateRedundantOperations)
            {
                Instruction inst = (Instruction)(commands[commands.Count - 1] & 0x3F);
                if (inst == Instruction.Origin)
                {
                    commands.RemoveAt(commands.Count - 1);
                }
            }

            UInt64 packedX = unchecked((UInt64)FixedMaths.ConvertTo8Dot7(FixedMaths.FloatToFixed(x)));
            UInt64 packedY = unchecked((UInt64)FixedMaths.ConvertTo8Dot7(FixedMaths.FloatToFixed(y)));
            UInt64 packedZ = unchecked((UInt64)FixedMaths.ConvertTo8Dot7(FixedMaths.FloatToFixed(z)));

            UInt64 extraBits = (packedX << 8) | (packedY << 23) | (packedZ << 38);

            commands.Add(ExecEngine.BuildInstruction(ExecEngine.Instruction.Origin, ExecEngine.Condition.AL, extraBits));
        }

        static void AddSphereToCommandBufferNoRegisterHit(List<UInt64> commands, Vector3 offset, float x, float y, float z, float rad, ExecEngine.ObjectMergeType mergeType = ExecEngine.ObjectMergeType.Add)
        {
            ExecEngine.Instruction instruction;

            switch (mergeType)
            {
                case ExecEngine.ObjectMergeType.Add: instruction = ExecEngine.Instruction.Sphere; break;
                case ExecEngine.ObjectMergeType.Sub: instruction = ExecEngine.Instruction.SphereSub; break;
                case ExecEngine.ObjectMergeType.And: instruction = ExecEngine.Instruction.SphereAnd; break;
                default: throw new NotImplementedException();
            }

            UInt64 packedX = unchecked((UInt64)FixedMaths.ConvertTo8Dot7(FixedMaths.FloatToFixed(x - offset.X)));
            UInt64 packedY = unchecked((UInt64)FixedMaths.ConvertTo8Dot7(FixedMaths.FloatToFixed(y - offset.Y)));
            UInt64 packedZ = unchecked((UInt64)FixedMaths.ConvertTo8Dot7(FixedMaths.FloatToFixed(z - offset.Z)));
            UInt64 packedRad = unchecked((UInt64)FixedMaths.ConvertTo4Dot7(FixedMaths.FloatToFixed(rad)));

            UInt64 extraBits = (packedX << 8) | (packedY << 23) | (packedZ << 38) | (packedRad << 53);

            commands.Add(ExecEngine.BuildInstruction(instruction, (mergeType != ExecEngine.ObjectMergeType.Add) ? ExecEngine.Condition.OH : ExecEngine.Condition.AL, extraBits));
        }

        static void AddPlaneToCommandBufferNoRegisterHit(List<UInt64> commands, Vector3 offset, float normalX, float normalY, float normalZ, float distance, ExecEngine.ObjectMergeType mergeType = ExecEngine.ObjectMergeType.Add)
        {
            ExecEngine.Instruction instruction;

            switch (mergeType)
            {
                case ExecEngine.ObjectMergeType.Add: instruction = ExecEngine.Instruction.Plane; break;
                case ExecEngine.ObjectMergeType.Sub: instruction = ExecEngine.Instruction.PlaneSub; break;
                case ExecEngine.ObjectMergeType.And: instruction = ExecEngine.Instruction.PlaneAnd; break;
                default: throw new NotImplementedException();
            }

            Vector3 pointOnPlane = new Vector3(normalX * distance, normalY * distance, normalZ * distance);
            pointOnPlane -= offset;
            float newDist = (pointOnPlane.X * normalX) + (pointOnPlane.Y * normalY) + (pointOnPlane.Z * normalZ);

            UInt64 packedNormalX = unchecked((UInt64)FixedMaths.ConvertTo2Dot10(FixedMaths.FloatToFixed(normalX)));
            UInt64 packedNormalY = unchecked((UInt64)FixedMaths.ConvertTo2Dot10(FixedMaths.FloatToFixed(normalY)));
            UInt64 packedNormalZ = unchecked((UInt64)FixedMaths.ConvertTo2Dot10(FixedMaths.FloatToFixed(normalZ)));
            UInt64 packedDist = unchecked((UInt64)FixedMaths.ConvertTo8Dot12(FixedMaths.FloatToFixed(newDist)));

            UInt64 extraBits = (packedNormalX << 8) | (packedNormalY << 20) | (packedNormalZ << 32) | (packedDist << 44);

            commands.Add(ExecEngine.BuildInstruction(instruction, (mergeType != ExecEngine.ObjectMergeType.Add) ? ExecEngine.Condition.OH : ExecEngine.Condition.AL, extraBits));
        }

        // Add plane using three points on plane
        static void AddPlaneToCommandBufferNoRegisterHit(List<UInt64> commands, Vector3 offset, Vector3[] points, ExecEngine.ObjectMergeType mergeType = ExecEngine.ObjectMergeType.Add)
        {
            ExecEngine.Instruction instruction;

            switch (mergeType)
            {
                case ExecEngine.ObjectMergeType.Add: instruction = ExecEngine.Instruction.Plane; break;
                case ExecEngine.ObjectMergeType.Sub: instruction = ExecEngine.Instruction.PlaneSub; break;
                case ExecEngine.ObjectMergeType.And: instruction = ExecEngine.Instruction.PlaneAnd; break;
                default: throw new NotImplementedException();
            }

            Vector3 normal = -Vector3.Cross(points[1] - points[0], points[2] - points[0]);
            normal.Normalize();
            float distance = ((points[0].X - offset.X) * normal.X) + ((points[0].Y - offset.Y) * normal.Y) + ((points[0].Z - offset.Z) * normal.Z);

            UInt64 packedNormalX = unchecked((UInt64)FixedMaths.ConvertTo2Dot10(FixedMaths.FloatToFixed(normal.X)));
            UInt64 packedNormalY = unchecked((UInt64)FixedMaths.ConvertTo2Dot10(FixedMaths.FloatToFixed(normal.Y)));
            UInt64 packedNormalZ = unchecked((UInt64)FixedMaths.ConvertTo2Dot10(FixedMaths.FloatToFixed(normal.Z)));
            UInt64 packedDist = unchecked((UInt64)FixedMaths.ConvertTo8Dot12(FixedMaths.FloatToFixed(distance)));

            UInt64 extraBits = (packedNormalX << 8) | (packedNormalY << 20) | (packedNormalZ << 32) | (packedDist << 44);

            commands.Add(ExecEngine.BuildInstruction(instruction, (mergeType != ExecEngine.ObjectMergeType.Add) ? ExecEngine.Condition.OH : ExecEngine.Condition.AL, extraBits));
        }

        static void AddAABBToCommandBufferNoRegisterHit(List<UInt64> commands, Vector3 offset, float minX, float minY, float minZ, float maxX, float maxY, float maxZ, ExecEngine.ObjectMergeType mergeType = ExecEngine.ObjectMergeType.Add)
        {
            ExecEngine.Instruction instruction;

            switch (mergeType)
            {
                case ExecEngine.ObjectMergeType.Add: instruction = ExecEngine.Instruction.AABB; break;
                case ExecEngine.ObjectMergeType.Sub: instruction = ExecEngine.Instruction.AABBSub; break;
                case ExecEngine.ObjectMergeType.And: instruction = ExecEngine.Instruction.AABBAnd; break;
                default: throw new NotImplementedException();
            }

            UInt64 packedMinX = unchecked((UInt64)FixedMaths.ConvertTo8Dot1(FixedMaths.FloatToFixed(minX - offset.X)));
            UInt64 packedMinY = unchecked((UInt64)FixedMaths.ConvertTo8Dot1(FixedMaths.FloatToFixed(minY - offset.Y)));
            UInt64 packedMinZ = unchecked((UInt64)FixedMaths.ConvertTo8Dot1(FixedMaths.FloatToFixed(minZ - offset.Z)));
            UInt64 packedMaxX = unchecked((UInt64)FixedMaths.ConvertTo8Dot1(FixedMaths.FloatToFixed(maxX - offset.X))); 
            UInt64 packedMaxY = unchecked((UInt64)FixedMaths.ConvertTo8Dot1(FixedMaths.FloatToFixed(maxY - offset.Y)));
            UInt64 packedMaxZ = unchecked((UInt64)FixedMaths.ConvertTo8Dot1(FixedMaths.FloatToFixed(maxZ - offset.Z)));

            UInt64 extraBits = (packedMinX << 8) | (packedMinY << 17) | (packedMinZ << 26) | (packedMaxX << 35) | (packedMaxY << 44) | (packedMaxZ << 53);

            commands.Add(ExecEngine.BuildInstruction(instruction, (mergeType != ExecEngine.ObjectMergeType.Add) ? ExecEngine.Condition.OH : ExecEngine.Condition.AL, extraBits));
        }

        static void AddRegisterHitToCommandBuffer(List<UInt64> commands, byte r, byte g, byte b, byte reflectivity, bool noReset = false)
        {
            UInt16 packedCol = (UInt16)((r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10));
            UInt32 extraBits = (UInt32)((packedCol << 16) | (reflectivity << 8));

            commands.Add(ExecEngine.BuildInstruction(noReset ? ExecEngine.Instruction.RegisterHitNoReset : ExecEngine.Instruction.RegisterHit, ExecEngine.Condition.AL, extraBits));
        }

        static void AddCheckerboardToCommandBuffer(List<UInt64> commands, byte r, byte g, byte b, byte reflectivity)
        {
            UInt16 packedCol = (UInt16)((r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10));
            UInt32 extraBits = (UInt32)((packedCol << 16) | (reflectivity << 8));

            commands.Add(ExecEngine.BuildInstruction(ExecEngine.Instruction.Checkerboard, ExecEngine.Condition.ORH, extraBits));
        }

        // Add a jump instructions with no target, returning the index of the instruction
        static int AddJump(List<UInt64> commands, ExecEngine.Condition condition, bool resetHitState)
        {
            int index = commands.Count;
            commands.Add(ExecEngine.BuildInstruction(resetHitState ? ExecEngine.Instruction.ResetHitStateAndJump : ExecEngine.Instruction.Jump, condition));
            return index;
        }

        // Patch a previously-added jump instruction with the next command as the target
        static void SetJumpTarget(List<UInt64> commands, int jumpIndex)
        {
            int target = commands.Count;
            if (target > 0xFFFF)
            {
                throw new Exception("Jump target overflow!");
            }
            commands[jumpIndex] = (commands[jumpIndex] & 0xFF) | ((UInt64)target << 8);
        }

        struct Plane
        {
            public Vector3 Normal;
            public float Dist;
            
            public static Plane FromThreePoints(Vector3[] points)
            {
                Vector3 normal = -Vector3.Cross(points[1] - points[0], points[2] - points[0]);
                normal.Normalize();
                float distance = (points[0].X * normal.X) + (points[0].Y * normal.Y) + (points[0].Z * normal.Z);

                Plane plane = new Plane();
                plane.Normal = normal;
                plane.Dist = distance;

                return plane;
            }
        }

        // Find the intersection point of three planes (if it exists)
        static Vector3? IntersectPlanes(Plane planeA, Plane planeB, Plane planeC)
        {
            Matrix3x3 mat = new Matrix3x3(
                planeA.Normal.X, planeA.Normal.Y, planeA.Normal.Z,
                planeB.Normal.X, planeB.Normal.Y, planeB.Normal.Z,
                planeC.Normal.X, planeC.Normal.Y, planeC.Normal.Z);

            float det = mat.Determinant();

            if (det == 0.0f)
                return null;

            return ((Vector3.Cross(planeB.Normal, planeC.Normal) * -planeA.Dist) +
                    (Vector3.Cross(planeC.Normal, planeA.Normal) * -planeB.Dist) +
                    (Vector3.Cross(planeA.Normal, planeB.Normal) * -planeC.Dist)) / det;
        }

        // Get the AABB enclosing the convex hull formed by a series of planes
        static BoundingBox? GetConvexHullBounds(Plane[] planes)
        {
            if (planes.Length < 4)
            {
                return null;
            }

            // Very brute-force algorithm to find the hull exterior points
            List<Vector3> points = new List<Vector3>();

            // First list every possible point formed from the intersection of the planes
            for (int i = 0; i < planes.Length; i++)
            {
                for (int j = 0; j < planes.Length; j++)
                {
                    if (i == j)
                        continue;

                    for (int k = 0; k < planes.Length; k++)
                    {
                        if ((k == i) || (k == j))
                            continue;

                        Vector3? intersection = IntersectPlanes(planes[i], planes[j], planes[k]);

                        if (intersection != null)
                        {
                            points.Add(intersection.Value);
                        }
                    }
                }
            }

            // Next cull any point which lies outside a plane

            for (int i = 0; i < planes.Length; i++)
            {
                Vector3 pointOnPlane = planes[i].Normal * planes[i].Dist;

                points.RemoveAll((p) => 
                {
                    Vector3 delta = p - pointOnPlane;

                    return (Vector3.Dot(delta, planes[i].Normal) > 0.0001f);
                });
            }

            if (points.Count < 1)
            {
                return null;
            }

            // Then return the bounding box formed by those points

            return BoundingBox.FromPoints(points.ToArray());
        }

        // Calculate, in a very brute-force manner, the planes forming the convex hull for a point cloud
        static Plane[] GetConvexHullFromPointCloud(Vector3[] points)
        {
            List<Plane> results = new List<Plane>();

            // Test every possible plane and see if there are any points lying outside it
            for (int i = 0; i < points.Length; i++)
            {
                for (int j = 0; j < points.Length; j++)
                {
                    if (i == j)
                        continue;

                    for (int k = 0; k < points.Length; k++)
                    {
                        if ((k == i) || (k == j))
                            continue;

                        Plane plane = Plane.FromThreePoints(new Vector3[] { points[i], points[j], points[k] });

                        Vector3 pointOnPlane = plane.Normal * plane.Dist;

                        bool anyPointsOutside = false;

                        for (int l = 0; l < points.Length; l++)
                        {
                            if ((l == i) || (l == j) || (l == k))
                                continue;

                            Vector3 delta = points[l] - pointOnPlane;

                            if (Vector3.Dot(delta, plane.Normal) > 0.0001f)
                            {
                                anyPointsOutside = true;
                                break;
                            }
                        }

                        if (!anyPointsOutside)
                        {
                            // Check if this plane is a duplicate of an existing one

                            bool havePlaneAlready = false;

                            foreach (Plane existing in results)
                            {
                                if ((Math.Abs(plane.Dist - existing.Dist) < 0.00001f) &&
                                    (Vector3.Dot(plane.Normal, existing.Normal) > 0.999999f))
                                {
                                    havePlaneAlready = true;
                                    break;
                                }
                            }

                            if (!havePlaneAlready)
                            {
                                results.Add(plane);
                            }
                        }
                    }
                }
            }

            return results.ToArray();
        }
    }
}
