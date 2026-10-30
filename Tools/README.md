# Tools —— 构建与辅助脚本

## 出包

**全队共用同一份构建脚本**：`Assets/Editor/DSHBuild.cs`（已在 10/30 实测可用）。
不要各写一套构建命令——六个人六种出包方式，是这类项目最常见的分叉点。

用法要点：

- 命令行 `-executeMethod` 调用，改场景名与输出路径即可复用
- 后端 **Mono2x**，不要切 IL2CPP
- **在普通终端里跑**。受限沙箱会因 WMI / named pipe 被禁而失败：
  报 `Unable to open database file` + `Upm-32312` 超时 → Unity 直接退出，
  看起来像"UPM 坏了"，实际是执行环境的问题

## 产物检查

出包后确认 `Build/` 下这几样都在，缺一个就是"双击没反应"：

```
<名字>.exe
UnityPlayer.dll
<名字>_Data/
MonoBleedingEdge/
D3D12/ D3D12Core.dll
```

**拷贝给别人时整个目录一起拷，不要只拷 exe。**

## 参考基线

空场景：89 MB / 13.5 秒 / 0 错误（10/30 实测）。
有内容后会涨，别把这个当最终包的预期。
