extends Node2D

## 落地尘土：玩家落地时在脚下溅起几粒小方块，摔得越重溅得越多。
##
## 纯代码绘制（不用粒子系统）。挂在 Player 下，跟着游戏冻结。
## 方向取自玩家的 up_direction，所以重力翻转后尘土会朝新的"上方"飞，
## 不会出现"人翻到天花板、土还往下掉"的穿帮。

## 尘土颜色：亮紫灰。原来是 #6B5560（暗紫灰），和地面砖块颜色几乎一样，
## 落地时根本看不出来；改成亮一档之后就明显了。
const DUST_COLOR := Color("C9BDD4")
## 单粒尺寸范围（像素）。太小会和背景像素混在一起。
const DUST_SIZE_MIN := 3.0
const DUST_SIZE_MAX := 6.0
## 存活时间（秒）。
const LIFE := 0.42
## 单次最多溅几粒。
const MAX_DUST := 10
## 冲击速度达到这个值就溅满 MAX_DUST 粒。
const FULL_SPEED := 900.0
## 沿重力反方向（"往上飞"）的基础初速。
const POP_SPEED := 95.0
## 左右散开的随机范围。要够大，尘土才能迅速飞出角色轮廓、不被人物挡住。
const SPREAD := 80.0
## 每秒减速量，让尘土喷出去后停住，而不是飘很远。
const DAMPING := 180.0
## 起始透明度。
const DUST_ALPHA := 0.92
## 出生点沿重力方向的偏移：角色高 28px（半高 14），贴着脚底出生才不会被身体遮住。
const SPAWN_OFFSET := 14.0

## 粒子：{pos: Vector2（全局坐标）, vel: Vector2, size: float, age: float}
var _dust: Array[Dictionary] = []
## 玩家节点（父节点）。
var _player: Node = null


func _ready() -> void:
	_player = get_parent() as Node
	if _player != null and _player.has_signal("landed"):
		_player.connect("landed", _on_landed)
	# 重生会瞬移，死亡点的尘土留在原地会显得很怪
	if _player != null and _player.has_signal("respawned"):
		_player.connect("respawned", _on_respawned)


## 重生：清空未散尽的尘土。
func _on_respawned() -> void:
	_dust.clear()
	queue_redraw()


## 落地：按冲击速度决定溅几粒。
func _on_landed(impact_speed: float) -> void:
	if _player == null:
		return
	# "上方" = 重力反方向；尘土朝这边飞
	var up: Vector2 = _player.get("up_direction")
	if up == Vector2.ZERO:
		up = Vector2.UP

	var ratio: float = clampf(impact_speed / FULL_SPEED, 0.0, 1.0)
	var count: int = clampi(int(round(lerpf(2.0, float(MAX_DUST), ratio))), 2, MAX_DUST)
	# 与 up 垂直的方向，用来左右散开
	var side := Vector2(up.y, -up.x)
	# 出生点：贴着脚底（沿重力方向偏半个身位），否则尘土生在身体里会被遮住
	var origin: Vector2 = _player.global_position - up * SPAWN_OFFSET

	for _i in count:
		_dust.append({
			"pos": origin,
			"vel": up * POP_SPEED * randf_range(0.6, 1.3) + side * randf_range(-SPREAD, SPREAD),
			"size": randf_range(DUST_SIZE_MIN, DUST_SIZE_MAX),
			"age": 0.0,
		})


func _process(delta: float) -> void:
	if _dust.is_empty():
		return

	var alive: Array[Dictionary] = []
	for d in _dust:
		d["age"] = float(d["age"]) + delta
		if float(d["age"]) >= LIFE:
			continue
		d["pos"] = d["pos"] + d["vel"] * delta
		var v: Vector2 = d["vel"]
		d["vel"] = v.move_toward(Vector2.ZERO, DAMPING * delta)
		alive.append(d)
	_dust = alive
	queue_redraw()


## 画尘土。位置存的是全局坐标，转成相对自身的局部坐标。
func _draw() -> void:
	for d in _dust:
		var t: float = float(d["age"]) / LIFE
		var c := DUST_COLOR
		c.a = DUST_ALPHA * (1.0 - t)
		if c.a <= 0.01:
			continue
		var size: float = float(d["size"])
		var local: Vector2 = to_local(d["pos"])
		draw_rect(Rect2(local - Vector2(size, size) * 0.5, Vector2(size, size)), c)
