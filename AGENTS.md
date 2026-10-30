# AGENTS.md —— 给 AI 编程助手的硬约束

> 每次开新对话，先把本文件贴进去。不贴，AI 会按 2022 LTS 的训练习惯写，专挑 Unity 6 已废弃的 API。

## 项目坐标
- 项目：FLICKCUT PROTOCOL（闪切协议），2D 俯视角动作生存 + 蓄力闪切
- 引擎：**Unity 6000.3.7f1（Unity 6.3 线，不是 2022 LTS）**
- 渲染：**2D Built-In Render Pipeline**，不是 URP
- 后端：**Mono2x**，不切换 IL2CPP
- 输入：**旧版 Input Manager**（`Input.GetAxis` / `Input.GetMouseButton`），项目已设为 `Input Manager (Old)`
- 命名空间：所有脚本统一 `namespace FlickCut`
- 语言：C# 8.0。**不要用 C# 10+ 的 file-scoped namespace**

## 禁止引入
- URP / HDRP / Shader Graph / 后处理栈
- 新 Input System / Cinemachine / DOTween / 任何第三方包
- Rigidbody2D 与物理碰撞（**判定全部手写**，用线段-圆距离）
- 通用技能框架 / 事件总线 / 数据驱动卡池（这次只做 4 张写死的卡）

## Unity 6 废弃 API（不要写）
- `FindObjectOfType` → 用 `FindFirstObjectByType`
- `FindObjectsOfType` → 用 `FindObjectsByType`
- 其余 API 你若不确定在 6000.3 是否还存在，**先说明不确定，不要直接写**
- 不要照抄 2021/2022 LTS 时代的 Stack Overflow 答案

## 架构硬规则
- 时间缩放**只能通过 `GameFlow.TimeScale`**，不得直接写 `Time.timeScale`
- 伤害**只能通过 `IDamageable.TakeDamage`** 进入，不得直接扣血
- 跨模块通信用事件，不用 Find 系列四处找对象
- `Arena.unity` 只有技术负责人（珈百璃）能改；其他人用 `Dev_<名字>.unity`

## 代码风格（详见 docs/工程规范.md）
- 文件名 = 类名，PascalCase；私有字段 camelCase；常量 PascalCase
- **不要写 `public` 字段**，用 `[SerializeField] private`
- 每个 public 方法写一行中文 `/// <summary>`
- 魔法数字进 `GameConfig` 或常量，不要散落在代码里
- 单文件超过 200 行必须先说明为什么不能拆
- 不用 `#region`

## 不要替我们决定的事
- **闪切判定公式、三段蓄力参数、手感数值**：这些我们自己写和调，AI 只作参考
- 新增功能：先问。清单之外的想法进 `docs/08_以后再说.md`
- 改构建方式、换渲染管线、升级引擎：一律不做

## 构建
- 用 `Assets/Editor/DSHBuild.cs`（命令行 `-executeMethod`），不要自己另写构建脚本
- **不要在受限沙箱里跑构建**：WMI 被拒 + named pipe 被禁会导致 `Upm-32312` 超时、Unity 直接退出，报错伪装成"UPM 坏了"。构建在普通终端里跑
