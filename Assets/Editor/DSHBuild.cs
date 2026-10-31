using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace FlickCut
{
    /// <summary>
    /// 全队共用的命令行出包入口（Mono 后端，Windows x64）。
    /// 用法（在**普通终端**里跑，不要在受限沙箱里跑）：
    ///   "&lt;Unity 安装路径&gt;\Editor\Unity.exe" -quit -batchmode -nographics ^
    ///     -projectPath "D:\git\FLICKCUT-PROTOCOL" ^
    ///     -executeMethod FlickCut.DSHBuild.BuildWindows -logFile build.log
    /// 也可以在编辑器里用菜单 Tools > 闪切 > 出一份 Windows 包。
    /// </summary>
    public static class DSHBuild
    {
        private const string OutputPath = "Build/FLICKCUT-PROTOCOL.exe";

        /// <summary>按 Build Settings 里已勾选的场景出一份 Windows x64 包；成功退出码 0，失败 1。</summary>
        public static void BuildWindows()
        {
            string[] scenes = CollectEnabledScenes();
            if (scenes.Length == 0)
            {
                Debug.LogError("[DSHBuild] Build Settings 里没有勾选任何场景。" +
                               "先 File > Build Settings 把 Assets/_Project/Scenes/Arena.unity 加进去并打勾，再出包。");
                Finish(1);
                return;
            }

            string directory = Path.GetDirectoryName(OutputPath);
            if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var options = new BuildPlayerOptions
            {
                scenes = scenes,
                locationPathName = OutputPath,
                target = BuildTarget.StandaloneWindows64,
                options = BuildOptions.None
            };

            BuildReport report = BuildPipeline.BuildPlayer(options);
            BuildSummary summary = report.summary;

            if (summary.result == BuildResult.Succeeded)
            {
                double megabytes = summary.totalSize / 1048576.0;
                Debug.Log(string.Format("[DSHBuild] 出包成功：{0}（{1:F0} MB，{2:F1} 秒）。拷贝给别人时整个 Build 目录一起拷。",
                    OutputPath, megabytes, summary.totalTime.TotalSeconds));
                Finish(0);
                return;
            }

            Debug.LogError(string.Format("[DSHBuild] 出包失败：{0}，共 {1} 条错误。往上翻日志找第一条错误，先修它。",
                summary.result, summary.totalErrors));
            Finish(1);
        }

        // 只在命令行批处理模式下退出进程；在编辑器里点菜单时不能 Exit，否则会把正在用的编辑器关掉。
        private static void Finish(int exitCode)
        {
            if (Application.isBatchMode)
            {
                EditorApplication.Exit(exitCode);
            }
        }

        /// <summary>菜单入口，方便在编辑器里直接点一次验证。</summary>
        [MenuItem("Tools/闪切/出一份 Windows 包")]
        private static void BuildFromMenu()
        {
            BuildWindows();
        }

        private static string[] CollectEnabledScenes()
        {
            var list = new List<string>();
            foreach (EditorBuildSettingsScene scene in EditorBuildSettings.scenes)
            {
                if (scene.enabled && !string.IsNullOrEmpty(scene.path))
                {
                    list.Add(scene.path);
                }
            }

            return list.ToArray();
        }
    }
}
