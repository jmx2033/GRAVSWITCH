extends Node

## 全局数值单例。
##
## 【11/6 改】从「autoload 脚本」改成「autoload 场景」（Scenes/config.tscn），
## 除两个结构常量外全部改成 @export —— 打开 config.tscn 就能在检查器里调手感，
## 不用改代码、不用重新跑一遍确认有没有敲错字。
##
## 变量名保持全大写不变：全仓库有 28 处 `Config.XXX` 引用，改名要动 6 个文件，
## 属于纯改名的风险改动，冻结前一天不做。它们原来是 const，大写是 Godot 的常量惯例；
## 现在语义变成「可调参数」，但名字保留以维持引用不变。

## 一个格子的边长（像素）。与美术规格绑定，不是手感参数。
const TILE_SIZE: int = 32

## 逻辑分辨率。AGENTS.md 定死 640×360，改这个等于所有素材重画。
const LEVEL_SIZE: Vector2 = Vector2(640, 352)

@export_group("重力")
## 基础重力加速度（像素/秒²）。调大更"沉"，调小更"飘"。
@export var GRAVITY: float = 1800.0
## 转向过渡时长（秒）：180° 反转用满这个值，90° 用一半。
@export var GRAVITY_TURN_TIME: float = 0.12


@export_group("水平移动")
## 最大水平速度（像素/秒）。
@export var MAX_SPEED: float = 240.0
## 加速度：越大起步越"跟手"，越小越"飘"。
@export var ACCEL: float = 2400.0
## 松开方向键后的减速度。
@export var DECEL: float = 3200.0
## 空中加速度。
@export var AIR_ACCEL: float = 2400.0
## 掉头加速度：只有「输入方向与当前速度相反」时用，比 ACCEL 大很多。
## 作用是让「按反方向」比「松手刹车」更干脆，否则地面掉头会像冰面打滑。
## 掉头用时 = MAX_SPEED × 2 ÷ TURN_ACCEL（4800 → 0.10 秒 / 6 帧）。
@export var TURN_ACCEL: float = 4800.0

@export_group("跳跃")
## 起跳初速（像素/秒）。方向由 up_direction 决定，不要写死 -y。
@export var JUMP_SPEED: float = 590.0
## 土狼时间：离开平台后仍可起跳的宽限期（秒）。
@export var COYOTE_TIME: float = 0.10
## 跳跃缓冲：落地前提前按跳，落地瞬间自动起跳（秒）。
@export var JUMP_BUFFER_TIME: float = 0.12
## 可变跳跃高度：提前松开跳跃键时，剩余上升速度保留的比例。
## 1.0 = 关掉（跳多高与按住多久无关）；0.5 = 点按约 1 格、长按约 2.3 格（实测）。
## 只影响"松手那一刻还在上升"的情况，按住到最高点不受影响。
@export var JUMP_CUT: float = 0.5

@export_group("流程")
## 死亡后多久回到起点。die 动画 16 帧 @ 16fps ≈ 1.0 秒。
## 【11/7】过渡接管重生时机后，这个值不再决定重生时刻（重生发生在黑幕全黑时），
## 保留是为了不破坏 game.gd 里 RespawnTimer 的初始化。
@export var RESPAWN_DELAY: float = 1.8

@export_group("转场")
## 黑幕盖满屏幕的时长（秒）。对齐 die 动画长度，玩家看不到被重置的那一帧。
@export var TRANSITION_FADE_OUT: float = 1.0
## 全黑之后停住多久（秒）。真正的重生 / 切场景就发生在这段全黑里。
@export var TRANSITION_HOLD: float = 0.08
## 黑幕退开的时长（秒）。退幕期间玩家已经能动，所以别拉太长。
@export var TRANSITION_FADE_IN: float = 0.45

@export_group("可动平台")
## 平台移动速度，单位像素/秒。
@export var MOVING_PLATFORM_SPEED: float = 40.0
## 可动平台从摆放位置向左右各移动的格数。
@export var MOVING_PLATFORM_TRAVEL_TILES: int = 2

## 当前所有重力来源的合力加速度（像素/秒²）；无重力区时是基础向下重力 g。
## 在 _ready() 里赋值：导出值要到实例化时才写进来，写在声明处会读到脚本默认值。
var gravity_acceleration: Vector2


func _ready() -> void:
	gravity_acceleration = Vector2.DOWN * GRAVITY
