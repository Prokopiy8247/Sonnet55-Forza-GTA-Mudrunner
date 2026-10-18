using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace MudRunner.EditorTools
{
    /// <summary>Windows standalone build: Tools/ub.sh build MudRunner.EditorTools.BuildPlayer.BuildWindowsFromCli  ->  Builds/Windows/MireAndIron.exe</summary>
    public static class BuildPlayer
    {
        public const string OutDir = "Builds/Windows";

        [MenuItem("MudRunner/Build/Windows Player")]
        public static void BuildWindows()
        {
            Directory.CreateDirectory(OutDir);
            PlayerSettings.productName = "Mire and Iron";
            PlayerSettings.companyName = "MudRunnerBenchmark";
            PlayerSettings.defaultScreenWidth = 1920; PlayerSettings.defaultScreenHeight = 1080;
            PlayerSettings.fullScreenMode = FullScreenMode.Windowed;
            PlayerSettings.runInBackground = true;
            var opts = new BuildPlayerOptions
            {
                scenes = new[] { "Assets/Scenes/Game.unity" },
                locationPathName = OutDir + "/MireAndIron.exe",
                target = BuildTarget.StandaloneWindows64,
                options = BuildOptions.None,
            };
            var report = BuildPipeline.BuildPlayer(opts);
            Debug.Log("[MudRunner] build result: " + report.summary.result + ", size " + (report.summary.totalSize / 1048576) + " MB, errors " + report.summary.totalErrors + ", time " + report.summary.totalTime);
            if (report.summary.result != BuildResult.Succeeded) EditorApplication.Exit(1);
        }

        public static void BuildWindowsFromCli() { BuildWindows(); }

        /// <summary>macOS standalone build (universal: Apple Silicon + Intel, Mono): Tools/ub.sh buildmac MudRunner.EditorTools.BuildPlayer.BuildMacFromCli  ->  Builds/Mac/MireAndIron.app</summary>
        [MenuItem("MudRunner/Build/macOS Player")]
        public static void BuildMac()
        {
            Directory.CreateDirectory("Builds/Mac");
            PlayerSettings.productName = "Mire and Iron";
            PlayerSettings.companyName = "MudRunnerBenchmark";
            PlayerSettings.defaultScreenWidth = 1600; PlayerSettings.defaultScreenHeight = 900;
            PlayerSettings.fullScreenMode = FullScreenMode.Windowed;
            PlayerSettings.runInBackground = true;
            UnityEditor.OSXStandalone.UserBuildSettings.architecture = UnityEditor.Build.OSArchitecture.x64ARM64;
            var opts = new BuildPlayerOptions
            {
                scenes = new[] { "Assets/Scenes/Game.unity" },
                locationPathName = "Builds/Mac/MireAndIron.app",
                target = BuildTarget.StandaloneOSX,
                options = BuildOptions.None,
            };
            var report = BuildPipeline.BuildPlayer(opts);
            Debug.Log("[MudRunner] mac build result: " + report.summary.result + ", size " + (report.summary.totalSize / 1048576) + " MB, errors " + report.summary.totalErrors + ", time " + report.summary.totalTime);
            if (report.summary.result != BuildResult.Succeeded) EditorApplication.Exit(1);
        }

        public static void BuildMacFromCli() { BuildMac(); }
    }
}
