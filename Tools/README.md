# Tools —— 构建与辅助脚本

## CI 检查器（`Tools/ci/`，10/31 新增）

| 文件 | 作用 |
|---|---|
| `checks.py` | 五项静态检查：仓库卫生 / `.meta` 配对 / 命名 / C# 硬约束 / 提交信息与文档链接。**只用 Python 标准库** |
| `test_checks.py` | 检查器自测（16 项，含"不该报的不能报"）。CI 每次先跑自测再查仓库 |
| `commit-msg` | 本地提交信息钩子，**只用 bash + grep + sed，不需要 Python** |
| `install-hooks.sh` | 把钩子装进 `.git/hooks/`，装完自动做正反两次自检 |

**六个人 clone 后都要执行一次：**

```bash
bash Tools/ci/install-hooks.sh
```

有 Python 的话也可以本地跑全量检查（没有就交给 PR 上的 CI）：

```bash
python Tools/ci/checks.py all
python Tools/ci/checks.py commits --range origin/main..HEAD
```

规则与误报处理见 `docs/工程规范.md` §5.2、§5.10。**改检查器必须同时补自测。**

## 出包

**全队共用同一份构建脚本**：`Assets/Editor/DSHBuild.cs`。
10/30 出包成功（Mono2x / 0 错误 / 13.54 秒 / 89 MB）用的是同 API 的**测试脚本**——那个脚本会新建空场景并覆盖 Build Settings，只适合验证链路，不能当产品脚本。仓库这份是它的改写版：**保留同一套 API，去掉"覆盖场景列表"和"新建场景"两个行为**，改为读 `Build Settings` 里已勾选的场景。

- 已逐条比对：`BuildPlayerOptions` / `BuildPipeline.BuildPlayer` / `BuildSummary` / `BuildResult` / `EditorApplication.Exit` / `EditorBuildSettings.scenes` 均在实测脚本里跑过
- 未被实测覆盖的只有 `Application.isBatchMode`（防止在编辑器里点菜单时把编辑器关掉）与 `[MenuItem]`，都是长期稳定 API
- **所以第一次用先点一次菜单 `Tools > 闪切 > 出一份 Windows 包`**：能出包说明编译与链路都通；报错就把日志贴出来，别自己猜着改

不要各写一套构建命令——六个人六种出包方式，是这类项目最常见的分叉点。

用法要点：

- 命令行 `-executeMethod FlickCut.DSHBuild.BuildWindows`
- `Build Settings` 必须先勾选 `Arena.unity`，没有勾选时脚本会主动报错退出（故意这样，避免出一份空包还以为成功）
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
