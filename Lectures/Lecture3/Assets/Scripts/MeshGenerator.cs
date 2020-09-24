using System.Collections.Generic;
using UnityEngine;
using System;
using Unity.Mathematics;

[RequireComponent(typeof(MeshFilter))]
public class MeshGenerator : MonoBehaviour
{
    public MetaBallField Field = new MetaBallField();
    
    private MeshFilter _filter;
    private Mesh _mesh;
    
    private List<Vector3> vertices = new List<Vector3>();
    private List<Vector3> normals = new List<Vector3>();
    private List<int> indices = new List<int>();

    /// <summary>
    /// Executed by Unity upon object initialization. <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// </summary>
    private void Awake()
    {
        // Getting a component, responsible for storing the mesh
        _filter = GetComponent<MeshFilter>();
        
        // instantiating the mesh
        _mesh = _filter.mesh = new Mesh();
        
        // Just a little optimization, telling unity that the mesh is going to be updated frequently
        _mesh.MarkDynamic();
    }


    class Limits {
        public float x_min = float.MaxValue;
        public float x_max = float.MinValue;
        public float y_min = float.MaxValue;
        public float y_max = float.MinValue;
        public float z_min = float.MaxValue;
        public float z_max = float.MinValue;
    }


    private Limits GetLimits() {
        Limits limits = new Limits();
        Vector3[] ballsPos = Field.GetBallsPositions();
        float epsilon = 3;

        foreach (var ballPos in ballsPos) {
           limits.x_min = Math.Min(limits.x_min, ballPos.x - epsilon);
           limits.x_max = Math.Max(limits.x_max, ballPos.x + epsilon);
           limits.y_min = Math.Min(limits.y_min, ballPos.y - epsilon);
           limits.y_max = Math.Max(limits.y_max, ballPos.y + epsilon);
           limits.z_min = Math.Min(limits.z_min, ballPos.z - epsilon);
           limits.z_max = Math.Max(limits.z_max, ballPos.z + epsilon);
        }

        return limits;
    }


    private int GetIndexFromBitArray(int[] bits) {
        int result = 0;
        for (int i = 0; i < bits.Length; i++) {
            result += ((int) Math.Pow(2, i)) * bits[i];
        }
        
        return result;
    }


    private Vector3 GetPointPosition( Vector3 vertex1,   Vector3 vertex2) {
        float func1 = Field.F(vertex1);
        float func2 = Field.F(vertex2);
        return vertex1 + (vertex2 - vertex1) * (-func1) / (func2 - func1);
    }


    public Vector3 GetNormal(Vector3 vertex)
    {
        float d = 0.01f;
        Vector3 dx = new Vector3(d, 0, 0);
        Vector3 dy = new Vector3(0, d, 0);
        Vector3 dz = new Vector3(0, 0, d);
        Vector3 minus_grad = new Vector3(
            Field.F(vertex - dx) - Field.F(vertex + dx),
            Field.F(vertex - dy) - Field.F(vertex + dy), 
            Field.F(vertex - dz) - Field.F(vertex + dz) 
        );

        return Vector3.Normalize(minus_grad);
    }

    /// <summary>
    /// Executed by Unity on every frame <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// You can use it to animate something in runtime.
    /// </summary>
    private void Update()
    {     
        vertices.Clear();
        indices.Clear();
        normals.Clear();
        
        Field.Update();


        Limits limits = GetLimits();
        float step = 0.08f;
        int vertexCount = 8;


        for (float x = limits.x_min; x < limits.x_max - 0.01; x += step) {
            for (float y = limits.y_min; y < limits.y_max - 0.01; y += step) {
                for (float z = limits.z_min; z < limits.z_max - 0.01; z += step) {

                    Vector3[] cube_vertexes = {
                        new Vector3(x, y, z),
                        new Vector3(x, y + step, z),
                        new Vector3(x + step, y + step, z),
                        new Vector3(x + step, y, z),
                        new Vector3(x, y, z + step),
                        new Vector3(x, y + step, z + step),
                        new Vector3(x + step, y + step, z + step),
                        new Vector3(x + step, y, z + step)
                    };
                
                    int[] bits = new int[8];
                    for (int i = 0; i < vertexCount; i++) {
                        bits[i] = Field.F(cube_vertexes[i]) > 0 ? 1 : 0;
                    }

                    int index = GetIndexFromBitArray(bits);

                    int3[] triangles = MarchingCubes.Tables.CaseToVertices[index];
                    foreach (var triangle in triangles) {

                        if (triangle.x == -1) {
                            break;
                        }

                        int[][] edges = {
                            MarchingCubes.Tables._cubeEdges[triangle.x],
                            MarchingCubes.Tables._cubeEdges[triangle.y],
                            MarchingCubes.Tables._cubeEdges[triangle.z]
                        };

                        foreach (var edge in edges) {
                            Vector3 vertex1 = cube_vertexes[edge[0]];
                            Vector3 vertex2 = cube_vertexes[edge[1]];
                            Vector3 new_vertex = GetPointPosition(vertex1, vertex2);
                            indices.Add(vertices.Count);
                            vertices.Add(new_vertex);
                            normals.Add(GetNormal(new_vertex));
                        }
                    }
                }
            }
        }

        _mesh.Clear();
        _mesh.SetVertices(vertices);
        _mesh.SetTriangles(indices, 0);
        _mesh.SetNormals(normals); 

        // Upload mesh data to the GPU
        _mesh.UploadMeshData(false);
    }
}
