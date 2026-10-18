using System;
using UnityEditor;
using UnityEngine;

namespace MudRunner.EditorTools
{
    /// <summary>
    /// Reproducible project configuration: layers, physics matrix, solver and time-step settings.
    /// Run from the menu (MudRunner/Setup/Apply Project Settings) or the CLI:
    ///   Unity.exe -batchmode -nographics -projectPath ... -executeMethod MudRunner.EditorTools.ProjectSetup.ApplyFromCli -quit
    /// </summary>
    public static class ProjectSetup
    {
        public const float FixedTimestep = 0.01f;         // 100 Hz vehicle physics
        public const int SolverIterations = 12;
        public const int SolverVelocityIterations = 4;

        [MenuItem("MudRunner/Setup/Apply Project Settings")]
        public static void Apply()
        {
            ApplyLayers();
            ApplyPhysics();
            ApplyTime();
            AssetDatabase.SaveAssets();
            Debug.Log("[MudRunner] Project settings applied (layers, physics matrix, solver, fixed timestep " + FixedTimestep + ").");
        }

        public static void ApplyFromCli()
        {
            try { Apply(); }
            catch (Exception e) { Debug.LogError("[MudRunner] ProjectSetup failed: " + e); EditorApplication.Exit(1); }
        }

        static void ApplyLayers()
        {
            var tagManager = new SerializedObject(AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/TagManager.asset")[0]);
            var layers = tagManager.FindProperty("layers");
            foreach (var (index, name) in GameLayers.Names)
                layers.GetArrayElementAtIndex(index).stringValue = name;
            tagManager.ApplyModifiedPropertiesWithoutUndo();
        }

        static void ApplyPhysics()
        {
            // Start from "everything collides", then carve out the pairs we never want.
            for (int a = 0; a < 32; a++)
                for (int b = a; b < 32; b++)
                    Physics.IgnoreLayerCollision(a, b, false);

            // Vehicle bodies are held up by the project's own ground model, not by the terrain collider.
            Physics.IgnoreLayerCollision(GameLayers.VehicleBody, GameLayers.Terrain, true);
            Physics.IgnoreLayerCollision(GameLayers.Terrain, GameLayers.Terrain, true);
            Physics.IgnoreLayerCollision(GameLayers.Terrain, GameLayers.Props, true);
            Physics.IgnoreLayerCollision(GameLayers.Props, GameLayers.Props, true);
            Physics.IgnoreLayerCollision(GameLayers.Debris, GameLayers.VehicleBody, true);
            for (int i = 0; i < 32; i++)
            {
                Physics.IgnoreLayerCollision(GameLayers.Triggers, i, true);
                Physics.IgnoreLayerCollision(GameLayers.Anchors, i, true);
            }

            var dyn = new SerializedObject(AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/DynamicsManager.asset")[0]);
            SetInt(dyn, "m_DefaultSolverIterations", SolverIterations);
            SetInt(dyn, "m_DefaultSolverVelocityIterations", SolverVelocityIterations);
            SetFloat(dyn, "m_DefaultMaxDepenetrationVelocity", 4f);
            SetFloat(dyn, "m_SleepThreshold", 0.005f);
            SetFloat(dyn, "m_BounceThreshold", 2f);
            SetBool(dyn, "m_QueriesHitTriggers", false);   // wheel casts must not stop on trigger volumes
            SetBool(dyn, "m_QueriesHitBackfaces", false);
            SetBool(dyn, "m_AutoSyncTransforms", false);
            SetInt(dyn, "m_SolverType", 1);                 // Temporal Gauss-Seidel: better for heavy mass ratios / joints
            dyn.ApplyModifiedPropertiesWithoutUndo();
        }

        static void ApplyTime()
        {
            var time = new SerializedObject(AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/TimeManager.asset")[0]);
            // Unity 6 stores the fixed timestep as a rational: seconds = m_Count * m_Denominator / m_Numerator.
            var count = time.FindProperty("Fixed Timestep.m_Count");
            var num = time.FindProperty("Fixed Timestep.m_Rate.m_Numerator");
            var den = time.FindProperty("Fixed Timestep.m_Rate.m_Denominator");
            if (count != null && num != null && den != null)
                count.longValue = (long)System.Math.Round((double)FixedTimestep * num.longValue / den.longValue);
            else
                Debug.LogWarning("[MudRunner] could not find rational Fixed Timestep property");
            var maxStep = time.FindProperty("Maximum Allowed Timestep");
            if (maxStep != null) maxStep.floatValue = 0.05f;
            time.ApplyModifiedPropertiesWithoutUndo();
        }

        static void SetInt(SerializedObject so, string name, int v) { var p = so.FindProperty(name); if (p != null) p.intValue = v; else Debug.LogWarning("[MudRunner] missing physics property " + name); }
        static void SetFloat(SerializedObject so, string name, float v) { var p = so.FindProperty(name); if (p != null) p.floatValue = v; else Debug.LogWarning("[MudRunner] missing physics property " + name); }
        static void SetBool(SerializedObject so, string name, bool v) { var p = so.FindProperty(name); if (p != null) p.boolValue = v; else Debug.LogWarning("[MudRunner] missing physics property " + name); }
    }
}
