extends Node

## 玩家音效控制器：监听 player.gd 发出的信号并播放对应声音。
## 随机选择、播放间隔、坠地音量映射、生死与翻转音都集中在这里。

## 跳跃音效；真正起跳时播放。
const JUMP_SFX: AudioStream = preload("res://Audio/sfx/sfx_jump_1.wav")
## 行走音效；贴地行走时轮播。
const WALK_SFX: Array[AudioStream] = [
	preload("res://Audio/sfx/sfx_walk_1.wav"),
	preload("res://Audio/sfx/sfx_walk_2.wav"),
	preload("res://Audio/sfx/sfx_walk_3.wav"),
	preload("res://Audio/sfx/sfx_walk_4.wav"),
]
## 行走音效的播放间隔。音效本身 0.25 秒，这里取 0.30 秒：
## 留 50ms 间隙让每一步都完整播完（不会"播一半被下一脚踩掉"），
## 同时全速 240px/s 横穿一屏（640px）约踩 9 步，节奏跟得上跑动。
const WALK_SFX_INTERVAL := 0.30
## 坠地音效；落地时根据冲击速度调整音量。
const LAND_SFX: AudioStream = preload("res://Audio/sfx/sfx_land.wav")
## 翻转音效；重力反转、角色翻面时播放。
const FLIP_SFX: AudioStream = preload("res://Audio/sfx/sfx_flip.wav")
## 死亡音效。
const DIE_SFX: AudioStream = preload("res://Audio/sfx/sfx_die.wav")
## 通关音效。
const WIN_SFX: AudioStream = preload("res://Audio/sfx/sfx_win.wav")
## 2.0 倍音量对应的自由落体高度（像素）：288px 的落地速度约为 1018。
const LAND_SFX_LOUD_HEIGHT := 288.0
## 低于这个冲击速度不播放，避免贴地抖动误触。
const LAND_SFX_MIN_SPEED := 50.0
## 音量倍率下限，避免低速落地换算成分贝时出错。
const LAND_SFX_MIN_SCALE := 0.05
## 坠地音效的整体音量偏移（dB），负值表示整体调小。
const LAND_SFX_VOLUME_OFFSET_DB := -6.0
## 坠地音效的播放延迟（秒）：跳跃音本身 0.22 秒，留足空白再出落地声，
## 否则两个音会糊在一起听不清。0.18 秒让跳跃音先走完大半。
const LAND_SFX_DELAY_SEC := 0.18
## 死亡 / 通关音的固定音量（dB），比常规音效轻一点，不抢画面。
const DIE_SFX_VOLUME_DB := -3.0
const WIN_SFX_VOLUME_DB := -3.0
## 翻转音音量。
const FLIP_SFX_VOLUME_DB := -2.0

@onready var _jump_sfx: AudioStreamPlayer = $JumpSfx
@onready var _land_sfx: AudioStreamPlayer = $LandSfx
@onready var _flip_sfx: AudioStreamPlayer = $FlipSfx
@onready var _die_sfx: AudioStreamPlayer = $DieSfx
@onready var _win_sfx: AudioStreamPlayer = $WinSfx
## 三个行走播放器轮转，保证每一步都能完整播完不被下一个踩掉。
@onready var _walk_sfx: Array[AudioStreamPlayer] = [
	$WalkSfx1 as AudioStreamPlayer,
	$WalkSfx2 as AudioStreamPlayer,
	$WalkSfx3 as AudioStreamPlayer,
]

# 是否处于行走状态；由 player.gd 的 walking_changed 信号驱动。
var _walking: bool = false

# 行走音效计时；<= 0 时播放下一个。
var _walk_timer: float = 0.0

# 下一次使用哪个行走音效播放器（三只轮转）。
var _walk_next: int = 0

# 上一次播放的行走音效下标；-1 表示还没播放过。
var _last_walk_sfx: int = -1

# 死亡或通关后置位：用来取消延迟中的落地音，避免和死亡/通关音叠在一起。
var _dead_or_won: bool = false

# 距上一次真正踩出脚步声的时间（秒），用于"停-走"抖动时避免重复密集播放。
var _since_last_step: float = 999.0

# 起跳次数计数：落地音延迟期间若又起跳，就用它判断这次落地已被新的跳跃覆盖。
var _jump_count: int = 0


func _ready() -> void:
	var player: Node = get_parent()
	player.connect("jumped", _on_jumped)
	player.connect("landed", _on_landed)
	player.connect("walking_changed", _on_walking_changed)
	player.connect("flipped", _on_flipped)
	player.connect("died", _on_died)
	player.connect("won", _on_won)
	player.connect("respawned", _on_respawned)


func _physics_process(delta: float) -> void:
	_since_last_step += delta
	if not _walking:
		return
	_walk_timer -= delta
	if _walk_timer <= 0.0:
		_play_walk()
		_walk_timer = WALK_SFX_INTERVAL


## 真正起跳时播放跳跃音效。
func _on_jumped() -> void:
	_jump_count += 1
	_jump_sfx.stream = JUMP_SFX
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
	# 落地点留空白再出声音：跳跃音 0.22 秒，等它走完大半，避免两音叠在一起
	var jump_snapshot: int = _jump_count
	await get_tree().create_timer(LAND_SFX_DELAY_SEC).timeout
	# 延迟期间可能已经死亡、通关，不该再补一声落地
	if not is_inside_tree() or _dead_or_won:
		return
	# 延迟期间又起跳了 → 这次落地已经被新的跳跃覆盖，不再补落地音
	if _jump_count != jump_snapshot:
		return
	_land_sfx.stream = LAND_SFX
	_land_sfx.volume_db = (
		linear_to_db(clampf(scale, LAND_SFX_MIN_SCALE, 2.0))
		+ LAND_SFX_VOLUME_OFFSET_DB
	)
	_land_sfx.play()


## 重力翻转时播放下落二音，与跳跃的上升音方向相反，靠耳朵即可区分。
func _on_flipped() -> void:
	_flip_sfx.stream = FLIP_SFX
	_flip_sfx.volume_db = FLIP_SFX_VOLUME_DB
	_flip_sfx.play()


## 死亡时播放玉片碎裂音。
func _on_died() -> void:
	_dead_or_won = true
	_walking = false
	_walk_timer = 0.0
	for player in _walk_sfx:
		player.stop()
	_jump_sfx.stop()
	_die_sfx.stream = DIE_SFX
	_die_sfx.volume_db = DIE_SFX_VOLUME_DB
	_die_sfx.play()


## 通关时播放五声音阶琶音。
func _on_won() -> void:
	_dead_or_won = true
	_walking = false
	_walk_timer = 0.0
	for player in _walk_sfx:
		player.stop()
	_win_sfx.stream = WIN_SFX
	_win_sfx.volume_db = WIN_SFX_VOLUME_DB
	_win_sfx.play()


## 重生完成：解除死亡/通关抑制，让落地音恢复正常。
func _on_respawned() -> void:
	_dead_or_won = false


## 行走状态变化：开始播放第一步，停止时不硬切，
## 让正在播的那一步自然播完（避免脚步声"播一半断掉"）。
## 反复左右移动时会频繁"停-走"切换；若每次切换都立刻踩一脚，
## 就会出现密集重复的脚步音。所以用一个最小间隔锁：
## 距上一次落脚不足 WALK_SFX_INTERVAL 时，只复位计时器、不立刻播。
func _on_walking_changed(walking: bool) -> void:
	if walking == _walking:
		return
	_walking = walking
	_walk_timer = WALK_SFX_INTERVAL
	if not walking:
		return
	# 刚踩过一脚的话，等这一拍走完再出下一脚，避免来回抖动导致重复播放
	if _since_last_step < WALK_SFX_INTERVAL:
		return
	_play_walk()


## 播放一个不与上次重复的行走音效；三个播放器轮转，让每步都能完整播完。
func _play_walk() -> void:
	_since_last_step = 0.0
	_last_walk_sfx = _pick_index(WALK_SFX.size(), _last_walk_sfx)
	var player: AudioStreamPlayer = _walk_sfx[_walk_next]
	_walk_next = (_walk_next + 1) % _walk_sfx.size()
	# 轮到的播放器如果还在播，就顺延到下一个空闲的，避免把它从头打断重放
	for i in _walk_sfx.size():
		var idx: int = (_walk_next + i) % _walk_sfx.size()
		if not _walk_sfx[idx].playing:
			player = _walk_sfx[idx]
			_walk_next = (idx + 1) % _walk_sfx.size()
			break
	player.stream = WALK_SFX[_last_walk_sfx]
	player.play()


## 均匀随机选一个下标；若与上次相同，从其余下标中重选。
func _pick_index(count: int, last: int) -> int:
	var index: int = randi_range(0, count - 1)
	if index == last:
		index = (index + randi_range(1, count - 1)) % count
	return index
