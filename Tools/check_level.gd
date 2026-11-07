extends Node

## 关卡校验工具：检查挑战关是否犯「终点嵌墙」「出生点悬空」这类低级错误。
##
## 用法（命令行）：
##   godot --headless --path <项目> res://Tools/check_level.tscn
##
## 检查项：
## 1. 终点格不能是实心砖（否则玩家进不去）
## 2. 终点不能被砖完全包围
## 3. 出生点下方必须有砖（否则一出生就掉进虚空）
## 4. 出生点不能在砖里
## 5. 报告重力区覆盖范围与重叠情况

const LEVELS := [
	"res://Scenes/challenge_1.tscn",
	"res://Scenes/level_4.tscn",
	"res://Scenes/level_5.tscn",
	"res://Scenes/challenge_2.tscn",
]

## 重力区方向枚举，与 gravity_zone.gd 一致。
const DIR_NAMES := ["向上", "向右", "向下", "向左"]


func _ready() -> void:
	var failed := 0
	for path in LEVELS:
		failed += _check(path)
	print("")
	if failed == 0:
		print("=== 全部通过 ===")
	else:
		print("=== 发现 %d 处问题 ===" % failed)
	get_tree().quit(1 if failed > 0 else 0)


## 检查单个关卡，返回问题数量。
func _check(path: String) -> int:
	print("=== %s ===" % path.get_file())
	var packed: PackedScene = load(path)
	if packed == null:
		print("  [错误] 无法加载")
		return 1
	var level: Node = packed.instantiate()
	var problems := 0

	var terrain: TileMapLayer = level.get_node_or_null("Terrain")
	if terrain == null:
		print("  [错误] 没有 Terrain 节点")
		level.free()
		return 1

	var solid := {}
	for cell in terrain.get_used_cells():
		solid[cell] = true
	print("  地形: %d 格" % solid.size())

	# --- 终点 ---
	var goal: Node2D = level.get_node_or_null("LevelGoal")
	if goal == null:
		print("  [错误] 没有 LevelGoal")
		problems += 1
	else:
		var gc := _to_cell(goal.position)
		if solid.has(gc):
			print("  [X] 终点 %s 嵌在砖里" % str(gc))
			problems += 1
		else:
			print("  [OK] 终点 %s 是空地" % str(gc))
		var free_around := 0
		for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
			if not solid.has(gc + d):
				free_around += 1
		if free_around == 0:
			print("  [X] 终点被砖完全包围，进不去")
			problems += 1

	# --- 出生点 ---
	var spawn: Node2D = level.get_node_or_null("Spawn")
	if spawn == null:
		print("  [错误] 没有 Spawn")
		problems += 1
	else:
		var sc := _to_cell(spawn.position)
		if solid.has(sc):
			print("  [X] 出生点 %s 本身在砖里" % str(sc))
			problems += 1
		if not solid.has(sc + Vector2i(0, 1)):
			print("  [X] 出生点 %s 下方没有砖（会掉下去）" % str(sc))
			problems += 1
		else:
			print("  [OK] 出生点 %s 下方有砖" % str(sc))

	# --- 重力区 ---
	var zones: Node = level.get_node_or_null("Zones")
	if zones != null:
		var covered := {}
		var zone_count := 0
		for z in zones.get_children():
			if not (z is Area2D):
				continue
			zone_count += 1
			var zp: Vector2 = z.position
			var sz: Vector2i = z.get("size_in_tiles")
			var dir: int = z.get("direction")
			var base := _to_cell(zp)
			for dx in range(sz.x):
				for dy in range(sz.y):
					var c := base + Vector2i(dx, dy)
					if not covered.has(c):
						covered[c] = []
					covered[c].append(dir)
		print("  重力区: %d 个，覆盖 %d 格" % [zone_count, covered.size()])

		if spawn != null:
			var sc2 := _to_cell(spawn.position)
			if covered.has(sc2):
				print("  [i] 出生点在重力区内（方向: %s）—— 确认是有意的" % _dir_text(covered[sc2]))

		var overlaps := 0
		for c in covered:
			if covered[c].size() > 1:
				overlaps += 1
		if overlaps > 0:
			print("  [!] %d 格被多个重力区重叠覆盖（策略性失重则为预期）" % overlaps)

	level.free()
	return problems


## 像素坐标转格坐标（向下取整）。
func _to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / 32.0)), int(floor(p.y / 32.0)))


## 把方向索引列表转成可读文字。
func _dir_text(dirs: Array) -> String:
	var parts: Array[String] = []
	for d in dirs:
		var i := int(d)
		parts.append(DIR_NAMES[i] if i >= 0 and i < DIR_NAMES.size() else "?")
	return "/".join(parts)
