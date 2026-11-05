extends Node

## 玩家音效控制器：监听 player.gd 发出的信号并播放对应声音。
## 随机选择、播放间隔、坠地音量映射都集中在这里。

## 跳跃音效；真正起跳时随机选一个播放。
const JUMP_SFX: Array[AudioStream] = [
	preload("res://Audio/sfx/jump_1.wav"),
	preload("res://Audio/sfx/jump_2.wav"),
	preload("res://Audio/sfx/jump_3.wav"),
]
## 行走音效；贴地行走时轮流随机播放。
const WALK_SFX: Array[AudioStream] = [
	preload("res://Audio/sfx/walk_1.wav"),
	preload("res://Audio/sfx/walk_2.wav"),
	preload("res://Audio/sfx/walk_3.wav"),
	preload("res://Audio/sfx/walk_4.wav"),
]
## 行走音效的播放间隔；音效本身 0.5 秒，留 0.1 秒重叠让脚步更连贯。
const WALK_SFX_INTERVAL := 0.4
## 坠地音效；落地时根据冲击速度调整音量。
const LAND_SFX: AudioStream = preload("res://Audio/sfx/land.wav")
## 2.0 倍音量对应的自由落体高度（像素）：288px 的落地速度约为 1018。
const LAND_SFX_LOUD_HEIGHT := 288.0
## 低于这个冲击速度不播放，避免贴地抖动误触。
const LAND_SFX_MIN_SPEED := 50.0
## 音量倍率下限，避免低速落地换算成分贝时出错。
const LAND_SFX_MIN_SCALE := 0.05
## 坠地音效的整体音量偏移（dB），负值表示整体调小。
const LAND_SFX_VOLUME_OFFSET_DB := -6.0

@onready var _jump_sfx: AudioStreamPlayer = $JumpSfx
@onready var _land_sfx: AudioStreamPlayer = $LandSfx
@onready var _walk_sfx: Array[AudioStreamPlayer] = [
	$WalkSfx1 as AudioStreamPlayer,
	$WalkSfx2 as AudioStreamPlayer,
]

# 是否处于行走状态；由 player.gd 的 walking_changed 信号驱动。
var _walking: bool = false

# 行走音效计时；<= 0 时播放下一个。
var _walk_timer: float = 0.0

# 下一次使用哪个行走音效播放器。
var _walk_next: int = 0

# 上一次播放的跳跃/行走音效下标；-1 表示还没播放过。
var _last_jump_sfx: int = -1
var _last_walk_sfx: int = -1


func _ready() -> void:
	var player: Node = get_parent()
	player.connect("jumped", _on_jumped)
	player.connect("landed", _on_landed)
	player.connect("walking_changed", _on_walking_changed)


func _physics_process(delta: float) -> void:
	if not _walking:
		return
	_walk_timer -= delta
	if _walk_timer <= 0.0:
		_play_walk()
		_walk_timer = WALK_SFX_INTERVAL


## 真正起跳时播放一个不与上次重复的跳跃音效。
func _on_jumped() -> void:
	_last_jump_sfx = _pick_index(JUMP_SFX.size(), _last_jump_sfx)
	_jump_sfx.stream = JUMP_SFX[_last_jump_sfx]
	_jump_sfx.play()


## 落地时按冲击速度播放坠地音效：
## 起跳落回同高度（速度 = JUMP_SPEED）为 1.0 倍音量，
## 自由落体 288px（约 1018 px/s）为 2.0 倍，最后整体偏移。
func _on_landed(impact_speed: float) -> void:
	if impact_speed < LAND_SFX_MIN_SPEED:
		return
	var ref_speed: float = Config.JUMP_SPEED
	var loud_speed: float = sqrt(2.0 * Config.GRAVITY * LAND_SFX_LOUD_HEIGHT)
	var weight: float = (impact_speed - ref_speed) / (loud_speed - ref_speed)
	var scale: float = lerpf(1.0, 2.0, weight)
	_land_sfx.stream = LAND_SFX
	_land_sfx.volume_db = (
		linear_to_db(clampf(scale, LAND_SFX_MIN_SCALE, 2.0))
		+ LAND_SFX_VOLUME_OFFSET_DB
	)
	_land_sfx.play()


## 行走状态变化：开始立即播放第一步，停止立即静音。
func _on_walking_changed(walking: bool) -> void:
	if walking == _walking:
		return
	_walking = walking
	_walk_timer = WALK_SFX_INTERVAL
	if walking:
		_play_walk()
	else:
		for player in _walk_sfx:
			player.stop()


## 播放一个不与上次重复的行走音效；两个播放器交替以允许重叠。
func _play_walk() -> void:
	_last_walk_sfx = _pick_index(WALK_SFX.size(), _last_walk_sfx)
	var player: AudioStreamPlayer = _walk_sfx[_walk_next]
	_walk_next = (_walk_next + 1) % _walk_sfx.size()
	player.stream = WALK_SFX[_last_walk_sfx]
	player.play()


## 均匀随机选一个下标；若与上次相同，从其余下标中重选。
func _pick_index(count: int, last: int) -> int:
	var index: int = randi_range(0, count - 1)
	if index == last:
		index = (index + randi_range(1, count - 1)) % count
	return index
