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

@export_group("跳跃")
## 起跳初速（像素/秒）。方向由 up_direction 决定，不要写死 -y。
@export var JUMP_SPEED: float = 590.0
## 土狼时间：离开平台后仍可起跳的宽限期（秒）。
@export var COYOTE_TIME: float = 0.10
## 跳跃缓冲：落地前提前按跳，落地瞬间自动起跳（秒）。
@export var JUMP_BUFFER_TIME: float = 0.12

@export_group("流程")
## 死亡后多久回到起点。die 动画 16 帧 @ 10fps = 1.6 秒，再留 0.2 秒看清最后一帧。
@export var RESPAWN_DELAY: float = 1.8

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
