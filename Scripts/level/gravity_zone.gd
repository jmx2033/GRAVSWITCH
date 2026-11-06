@tool
extends Area2D
class_name GravityZone

## 重力区：只管碰撞范围与玩家进出判定；画面交给 GravityZoneVisuals 子节点。
## 渲染数值与画法都在 Scripts/level/gravity_zone_visuals.gd，
## 各项参数为什么这么定见 docs/13_重力区视觉实现参考.md。

## 只处理这个组里的物体，避免和场景里其他物体误触发。
const PLAYER_GROUP := "player"
## direction 枚举对应的方向向量，顺序必须和 @export_enum 一致。
const DIRS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
## 视觉层脚本（用 preload 而非 class_name，避免跨文件解析顺序问题）。
const VISUALS_SCRIPT := preload("res://Scripts/level/gravity_zone_visuals.gd")

## 石粒沿重力方向的漂移速度，单位像素/秒。
const STONE_SPEED := 10.0
## 每格生成几颗石粒、单个区上限。
const STONES_PER_TILE := 3
const MAX_STONES := 24
## 石粒边长范围（像素）；上限 4px，更大在 640×360 下像马赛克而非尘埃。
const STONE_SIZE_MIN := 2.0
const STONE_SIZE_MAX := 4.0

## 重力拉力方向：0 上、1 右、2 下、3 左。
@export_enum("重力向上", "重力向右", "重力向下", "重力向左") var direction: int = 0:
	set(value):
		direction = clampi(value, 0, DIRS.size() - 1)
		if Engine.is_editor_hint():
			_sync_visuals()
## 区域尺寸（格）；节点原点是左上角，向右下扩展。
@export var size_in_tiles: Vector2i = Vector2i(6, 8):
	set(value):
		size_in_tiles = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		if Engine.is_editor_hint():
			_rebuild()

## 区域的像素尺寸，由 size_in_tiles × Config.TILE_SIZE 算出。
var _zone_size: Vector2 = Vector2.ZERO
## 每颗石粒：{pos: Vector2, size: float}；_process() 每帧推进位置。
var _stones: Array[Dictionary] = []
## 动画累计时间，交给视觉层驱动辉光呼吸/游走。
var _time: float = 0.0

## 碰撞形状节点；_rebuild() 会按区域尺寸重新生成形状。
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
## 视觉层节点，由 _ready 创建（不放进场景文件，避免两个脚本互相引用）。
var _visuals: Node2D = null


## 初始化：建视觉层、重建碰撞盒，并监听玩家进出。
func _ready() -> void:
	_setup_visuals()
	_rebuild()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## 创建视觉层子节点并同步一次数据。
func _setup_visuals() -> void:
	if is_instance_valid(_visuals):
		return
	_visuals = get_node_or_null("Visuals")
	if _visuals == null:
		_visuals = VISUALS_SCRIPT.new()
		_visuals.name = "Visuals"
		add_child(_visuals)
	_sync_visuals()


## 把尺寸、方向、编辑器状态与石粒数据灌给视觉层。
func _sync_visuals() -> void:
	if _visuals == null:
		return
	_visuals.set_zone(_zone_size, _pull(), Engine.is_editor_hint())
	_visuals.set_stones(_stones)


## 按 size_in_tiles 算像素尺寸，重建居中碰撞矩形并重置石粒。
## @tool 下 setter 可能早于 @onready 触发，此时 _collision_shape 为 null，
## 所以自己取一次节点，取不到就跳过（_ready 会再补一次）。
func _rebuild() -> void:
	var tiles := Vector2i(maxi(size_in_tiles.x, 1), maxi(size_in_tiles.y, 1))
	_zone_size = Vector2(tiles.x * Config.TILE_SIZE, tiles.y * Config.TILE_SIZE)

	var shape_node: CollisionShape2D = _collision_shape
	if shape_node == null and is_inside_tree():
		shape_node = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null:
		var shape := RectangleShape2D.new()
		shape.size = _zone_size
		shape_node.shape = shape
		shape_node.position = _zone_size * 0.5

	# 编辑器里不撒石粒（每次重绘重新随机会闪）。
	if not Engine.is_editor_hint():
		_spawn_stones(tiles)
	_sync_visuals()


## 在场内随机撒石粒；数量随面积增长，不超过 MAX_STONES。
func _spawn_stones(tiles: Vector2i) -> void:
	_stones.clear()
	var count := mini(tiles.x * tiles.y * STONES_PER_TILE, MAX_STONES)
	for _i in count:
		var size := randf_range(STONE_SIZE_MIN, STONE_SIZE_MAX)
		_stones.append({
			"pos": Vector2(
				randf_range(0.0, maxf(_zone_size.x - size, 0.0)),
				randf_range(0.0, maxf(_zone_size.y - size, 0.0))
			),
			"size": size,
		})


## 每帧推进石粒位置与动画时钟，再让视觉层重绘。编辑器里不动。
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	_update_stones(delta)
	if _visuals != null:
		_visuals.advance_time(delta)


## 石粒沿重力方向漂移，越界后从另一侧绕回。
func _update_stones(delta: float) -> void:
	var pull := _pull()
	for i in _stones.size():
		var stone := _stones[i]
		var size: float = stone["size"]
		var limit := _zone_size - Vector2(size, size)
		var p: Vector2 = stone["pos"] + pull * STONE_SPEED * delta
		# 按这颗石粒自己的尺寸算边界，大小不一也不会露出半颗。
		if p.x < 0.0:
			p.x = limit.x
		elif p.x > limit.x:
			p.x = 0.0
		if p.y < 0.0:
			p.y = limit.y
		elif p.y > limit.y:
			p.y = 0.0
		stone["pos"] = p


## 把 direction 枚举换成对应的单位向量（重力拉力方向）。
func _pull() -> Vector2:
	return DIRS[clampi(direction, 0, DIRS.size() - 1)]


## 玩家进入时通知玩家，并带上本区的重力拉力方向。
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(PLAYER_GROUP):
		body.call("enter_gravity_zone", self, _pull())


## 玩家离开时通知玩家；是否真的恢复重力由玩家判断。
func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group(PLAYER_GROUP):
		body.call("exit_gravity_zone", self)
