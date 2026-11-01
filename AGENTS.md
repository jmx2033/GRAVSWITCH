# AGENTS.md —— 给 AI 编程助手的硬约束

> 每次开新对话，先把本文件贴进去。不贴，AI 会按 **Godot 3** 的习惯写：`KinematicBody2D`、`yield`、`export var`、`instance()`——全是 4.x 已经删掉的东西，一贴进编辑器就是一屏红色报错。

## 项目坐标

- 项目：**GRAVSWITCH（重力开关）** —— 2D 像素平台跳跃解谜，玩法见 `docs/01_重力_核心机制与切片.md`
- 引擎：**Godot `4.7.2-stable`**（六人共用一个 exe，不许各自升级）
- 语言：**只用 GDScript**。不要写 C#、不要混用（标准版编辑器打不开带 `.cs` 的工程）
- 渲染：**Compatibility 渲染器**（不是 Forward+，也不是 Mobile）。2D 像素项目本来就该用它——启动快、低端机跑得动。顺带的好处是 Web 导出因此可用，但 **Web 不是交付项**
- 分辨率：**逻辑 640×360**，整数缩放到窗口（1280×720 为 2×，1920×1080 为 3×）
- 关卡：**20 × 11 格，一屏一关，不做相机跟随**

## 建工程那一刻就要定死的三项（后面改很贵）

| 项 | 值 | 选错的后果 |
|---|---|---|
| 渲染器 | **Compatibility** | Forward+ 对 2D 像素没有任何好处；中途换渲染器要重导素材、重调光照 |
| 视口 + 拉伸 | 视口 **640 × 360**；拉伸模式 `canvas_items`；宽高比 `keep`；缩放模式 `integer`（4.2 之后有这一项） | 非整数缩放，像素图被插值糊成一团 |
| 默认纹理过滤 | **Nearest**（项目设置 `rendering/textures/canvas_textures/default_texture_filter`） | 像素图默认被双线性插值糊掉，且要一个 sprite 一个 sprite 去改 |

三项都由技术负责人在建工程时设置，设完不再改。像素游戏里这三项错了，整套美术素材等于白画。

**另外两项建工程时一并定掉：**

- **窗口覆盖尺寸** `display/window/size/window_width_override` = `1280`、`window_height_override` = `720`。视口还是 640×360，这只是让窗口以 2× 显示；不设的话窗口只有 640×360，投到投影仪上巴掌大。**这一项默认藏在「高级设置」开关后面，不开看不到**
- **主场景** `application/run/main_scene` 必须设。空工程没有主场景时，导出的 exe 双击会直接报错退出，不是「开个空窗口」

**640×360 不会「太小」——它是画布，不是窗口大小。** 一屏固定 20 格不变，屏幕上的实际大小只由缩放倍率决定：

| 屏幕 | 全屏时 | 倍率 | 结果 |
|---|---|---|---|
| 1920×1080 | 1920×1080 | **3×** | 正好铺满，无黑边 |
| 2560×1440 | 2560×1440 | **4×** | 正好铺满 |
| 3840×2160 | 3840×2160 | **6×** | 正好铺满 |
| 1366×768 | 1366×768 | **2×** | 上下留黑边 |

改逻辑分辨率等于所有素材重画、关卡格子重排，等于重做。所以定死。

## 输入（只有三个动词）

| action | 键 |
|---|---|
| `move_left` / `move_right` | `A` `D` / `←` `→` |
| `jump` | `空格` |
| `restart` | `R` |

走 **InputMap action**，**不要硬编码 `KEY_SPACE`**。没有攻击、冲刺、抓取、二段跳、能力切换——多一个动词这个游戏就不是它了。

## 物理与碰撞（和上一版规则相反，注意）

- 角色用 **`CharacterBody2D` + `move_and_slide()`**，**不要手写积分**。平台跳跃的手感靠引擎原生的贴地判定，手写只会更难调
- 重力区用 **`Area2D`** 检测玩家进入/离开，允许使用
- **起跳方向必须写 `up_direction * JUMP_SPEED`，不许写死 `velocity.y = -620`。** 这个游戏的重力会翻转，写死 `-y` 之后一进重力区人就往墙上撞
- 同一时刻**只认一个重力区**（重叠时取最后进入的），不做多区权重混合
- **离开重力区后，重力恢复成世界默认的「向下」，不保持最后一个区的方向。** 每次切换（进区、出区）都是 0.12 s 过渡，过渡期间贴地判定跟着转 —— 所以玩家出区的头 0.12 s 还会有约一格的惯性漂移，这条不要"优化掉"
- **可动平台用 `AnimatableBody2D`，`sync_to_physics` 保持默认的 `true`，别关。** 玩家能被平台带走全靠这个属性；如果用 `StaticBody2D` 再拿代码挪位置，人站上去会被平台从脚底下抽走，肉眼看着像"人在原地踏步"。位移用 `Tween` 循环，不引插件

### 磁场（重力区的表现，10/31 定）

- 代码名永远是 `gravity_zone`。**「磁场」只是美术叫法，不改任何文件名、类名、提交 scope**
- 场体 = `ColorRect` + `#9B7FD4`，`modulate.a` 取 0.22–0.30；边界 = 2px 实线 + 四角 4×4 角标
- **石粒 = 代码生成的小方块，不用贴图、不用 `CPUParticles2D`、不用 shader。** 每 32×32 格 3 颗，但**每个磁场总数封顶 24 颗**（6×9 的场按 3 颗/格会到 162 颗，那是沙尘暴）；2×2px，`#FFF2E0` 且 alpha 0.55，沿重力方向匀速 10 px/s，出界从反方向重入，每颗相位错开
- 石粒存在的唯一理由是**让方向可读**：玩家不看箭头，靠「东西在往哪边掉」就知道重力朝哪。所以石粒不许闪、不许加速、不许变大小
- 箭头 `rotation_degrees` 取 0 / 90 / 180 / 270，因为像素图 90° 旋转无损

## 禁止引入

- 任何 addon / 第三方插件 / Asset Library 资源
- 状态机框架、事件总线、数据驱动配置系统（这次只有 4 关，写死）
- 自定义 shader、后处理、视差多层背景、粒子系统做核心表现
- 存档、排行榜、联机、关卡编辑器

## Godot 3 写法（4.x 已删除，不要写）

| 不要写 | 改成 |
|---|---|
| `KinematicBody2D` | `CharacterBody2D` |
| `yield(get_tree(), "idle_frame")` | `await get_tree().process_frame` |
| `export var x = 1` | `@export var x: int = 1` |
| `onready var n = $A` | `@onready var n: Node = $A` |
| `instance()` | `instantiate()` |
| `connect("pressed", self, "_on_pressed")` | `pressed.connect(_on_pressed)` |
| `rand_range(a, b)` | `randf_range(a, b)` |
| `OS.window_size` | `DisplayServer.window_set_size()` |
| `PoolVector2Array` | `PackedVector2Array` |
| `Spatial` / `Transform` | `Node3D` / `Transform3D` |

**不确定某个 API 在 4.7 是否还存在时，先说明不确定，不要直接写。** 不要照抄 Godot 3 时代的教程。

## 缩进（最容易踩死的一条）

**GDScript 用 Tab 缩进，且一个文件里不许混用 Tab 和空格。** 混用会直接报 `Used space character for indentation instead of tab`，报错位置还指在别处，极难查。

- 新建 `.gd` 一律 Tab
- 从聊天窗口复制代码后，先看一眼缩进是不是变成了空格

## 架构硬规则

- 所有可调数值放进 **一个 autoload 单例 `Config`**，不许散落在各个脚本里。调手感时只改这一处
- **跳跃参数（重力加速度、跳跃初速、最大速度、土狼时间、跳预输入、转向过渡）只有技术负责人能改**，改完全队重测
- 节点之间用 **signal** 通信，不要 `get_node("../../..")` 这种深路径
- 状态只有四个：`MENU / PLAYING / DEAD / WIN`，写在 `game.gd` 里
- 关卡用 `level_0.tscn` … `level_3.tscn`，主场景只负责切关

## 工作顺序：先竖切，后铺开

**第一条能玩的链路优先，完整框架其次。** 顺序是：

1. 空目录结构建好（10 分钟，只是建文件夹，不写代码）
2. 一个场景 → 一个 `CharacterBody2D` 方块 → 能左右走、能跳 → 出一次 Windows 包
3. 这条通了，才开始加重力区、加关卡、加 UI

**不许先搭「完整框架」再填内容。** 8 天里，没人跑过的框架等于零：
抽象层写错一次，比直接写多花的返工大得多。框架是在第 2 步跑通的过程中长出来的，
不是事先设计的。

**但目录结构必须第一天就定**——建文件夹几乎不花时间，而后期挪文件会导致
所有 `res://` 路径失效、场景引用断掉。

## 关卡怎么搭（瓦片地图）

**4.7 里没有 `TileMap` 这个节点了**，建的是 **`TileMapLayer`**。`TileMap` 已废弃，加进来会报黄字，网上 4.0/4.1 的老教程按 `TileMap` 讲，别照抄。需要多张图叠在一起就加多个 `TileMapLayer` 节点，不是一个节点配多层。

**关卡场景层级固定成这样**，四关一致：

```
level_1 (Node2D)
├─ Terrain  (TileMapLayer)  collision_layer = 1，勾 Collision Enabled
├─ Deco     (TileMapLayer)  collision 全关，只画背景与装饰
├─ Zones    (Node2D)        里面实例化 gravity_zone
├─ Spawn    (Marker2D)      玩家出生点
└─ Player   (玩家场景实例)
```

**TileSet 只建一次**，存 `levels/tileset_cave.tres` 进仓库，四关共用：

| 项 | 值 |
|---|---|
| 纹理 | `Art/tiles/tile_cave.png`（横排、32×32、间距 0） |
| `texture_region_size` | 32 × 32，分离值全 0 |
| 碰撞 | 1–4 号砖给**整格方形**碰撞多边形，放进 Physics Layer 1 |
| 单向平台（5 号） | 半格高碰撞多边形 + 该物理层勾 **One Way** |

**谁配碰撞**：`tileset_cave.tres` 和碰撞多边形由**程序（或会用的那个人）配一次**，半小时内做完。之后策划摆格子不需要再碰碰撞。

**谁摆格子**：关卡布局由策划摆（见 `docs/03` 第六、七节）。第一关必须由会的人陪着摆一遍当模板，后面三关照模板摆——不要让一个没摆过的人自己摸编辑器，20×11 摆一关能磨掉两小时。

**8 天内不许做的**：Terrain 自动拼接（autotile）、多层地形、tile 里塞场景（`TileSetScenesCollectionSource`）、砖块的随机变化。手工摆，一关 400 个格子不到。

## 代码风格

- 文件名 `snake_case.gd`，与节点同名：`player.gd` 挂在 `Player` 节点上
- 变量与函数 `snake_case`；`class_name` 与节点名 `PascalCase`
- 变量尽量带类型：`var speed: float = 240.0`
- 每个公开函数写一行中文 `##` 注释
- 单文件超过 150 行先说明为什么不能拆
- 不用 `#region`

## 不要替我们决定的事

- **跳跃参数、重力转向过渡时长、关卡格子布局**：这些我们自己调，AI 只给参考值
- 新增功能：先问。清单外的想法进 `docs/08_以后再说.md`
- 换引擎版本、加插件、加 shader：一律不做

## 导出

- Windows：导出预设 `Windows Desktop`，输出到 `build/win/`
- Web：导出预设 `Web`，输出到 `build/web/`。**前提是渲染器为 Compatibility**；并且必须关掉多线程（GitHub Pages 不支持自定义响应头）
- 命令行导出：`godot --headless --export-release "<预设名>" <输出路径>`
- **`export_templates` 没下载就导不出任何东西**。报错是「找不到导出模板」，不是代码问题
