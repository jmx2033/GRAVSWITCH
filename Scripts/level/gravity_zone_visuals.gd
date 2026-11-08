extends Node2D

## 重力区视觉层：只负责把 gravity_zone.gd 给的数据画出来（纯 _draw()，无 shader/粒子）。
## 不参与碰撞与重力逻辑；也不写 class_name，避免与 gravity_zone.gd 的解析顺序冲突。
## 各项数值为什么这么定，见 docs/13_重力区视觉实现参考.md。

## 场体填充透明度。
const FIELD_ALPHA := 0.45
## 远端（重力反侧）与力源端（重力指向侧）颜色。
## 远端直接用背景色 P01 #100D14（叶一谦 11/7 反馈"深色一端太深，跟背景一个颜色就行"）。
const FIELD_FAR_COLOR := Color("#100D14")
const FIELD_NEAR_COLOR := Color("#B295F0")
## 渐变曲线：必须是 1.0（线性），非线性会在暗端出折线台阶。
const GRADIENT_CURVE := 1.0
## 渐变分段目标像素与段数上限。
const GRADIENT_SEG_TARGET_PX := 2.0
const GRADIENT_SEG_MAX := 200

## 出口辉光：颜色、透明度、厚度比例（占场短边）、呼吸与游走速度/强度、切段长度。
## 厚度取半个场（负责人要求"范围大一点，大概半个重力场就行"）。
const GLOW_COLOR := Color("D9CBFF")
const GLOW_ALPHA := 0.30
const GLOW_WIDTH_RATIO := 0.5
## 呼吸灯（叶一谦 11/7 要求浅色端能看出呼吸）：
## 速度按"人眼舒服的呼吸周期 4 秒左右"反推，2π/1.5 ≈ 4.2s；
## 幅度 1.0 时 alpha_scale 在 0.5~1.5 之间摆（相对 3 倍差），平均亮度仍由 GLOW_ALPHA 决定，
## 所以"呼吸明显"和"整体不刺眼"两件事不冲突。
const GLOW_PULSE_SPEED := 1.5
const GLOW_PULSE_AMOUNT := 1.0
const GLOW_FLOW_SPEED := 0.9
const GLOW_FLOW_WAVES := 1.5
const GLOW_FLOW_DEPTH := 0.55
const GLOW_SEG_PX := 4.0

## 石粒拖尾：段数、总长（像素）、首段透明度、拖尾与石粒粗细之比。
const TRAIL_SEGMENTS := 4
const TRAIL_LENGTH := 14.0
const TRAIL_ALPHA := 0.42
const TRAIL_THICK_RATIO := 0.62
## 石粒颜色与透明度。
const STONE_COLOR := Color("#fff2e0")
const STONE_ALPHA := 0.55

## 朝下加重力区的视觉区分（11/7 加）。
##
## 朝下的区是 2g「加重」（见 player.gd 的 _zone_gravity），但玩家原本看不出来。
## 这里给它一档更强的表现：辉光更亮、呼吸更急、场体亮端更亮——
## 用「更强的紫」表示「更强的拉力」。
##
## 约束：只能用紫色内部的变化。AGENTS.md 规定石粒不许加速、橙色只给危险，
## 所以不能靠石粒动得更快或换颜色来表达。
const DOWN_GLOW_BOOST := 1.35
const DOWN_PULSE_BOOST := 1.45
const DOWN_FIELD_BOOST := 1.18


## 重力指向侧高亮边：颜色与厚度（像素）。等于 0 表示不画这条加粗边。
const EDGE_HIGHLIGHT_COLOR := Color("D9C7FF")
const EDGE_HIGHLIGHT_WIDTH := 0.0
## 四周边框透明度、四角方块边长与透明度。
const FRAME_ALPHA := 0.10
const CORNER_SIZE := 4.0
const CORNER_ALPHA := 0.0

## 出口辉光的强度倍率。1.0 是关卡里的标准强度。
##
## 主菜单要用同一个视觉层画「重力场」，但那里的辉光只是背景之上的点缀，
## 压到 0.55 左右才不抢戏。主菜单那侧通过继承本类并设这个值来调。
var _glow_scale: float = 1.0

## 以下四项由 gravity_zone.gd 灌入/推进。
var _zone_size: Vector2 = Vector2.ZERO
var _pull_dir: Vector2 = Vector2.UP
var _editor_hint: bool = false
## 石粒：{pos: Vector2, size: float}。
var _stones: Array[Dictionary] = []
## 晶核：{pos: Vector2, radius: float, phase: float}。
## 动画时钟，驱动辉光呼吸与游走。
var _time: float = 0.0


## 设置区域尺寸、重力方向与编辑器状态。
func set_zone(zone_size: Vector2, pull_dir: Vector2, editor_hint: bool) -> void:
	_zone_size = zone_size
	_pull_dir = pull_dir
	_editor_hint = editor_hint
	queue_redraw()





## 灌入石粒数据（与 gravity_zone.gd 共用同一批字典，位置由它推进）。
func set_stones(stones: Array[Dictionary]) -> void:
	_stones = stones
	queue_redraw()


## 设置出口辉光的强度倍率（1.0 = 关卡里的标准强度）。
func set_glow_scale(scale: float) -> void:
	_glow_scale = maxf(scale, 0.0)
	queue_redraw()


## 推进动画时钟、推进晶核并重绘。
func advance_time(delta: float) -> void:
	_time += delta
	queue_redraw()


## 晶核沿重力方向缓慢漂移，并在场的范围内来回游走。

## 画整个重力区。
func _draw() -> void:
	if _zone_size == Vector2.ZERO:
		return

	_draw_field_gradient()
	_draw_exit_glow()

	if _editor_hint:
		draw_rect(Rect2(Vector2.ZERO, _zone_size), EDGE_HIGHLIGHT_COLOR, false, 2.0)
		_draw_corners()
		_draw_pull_edge()
		_draw_editor_arrow()
		return

	# 运行时只留一圈极淡的描边，四角与力源端加粗边都不画了：
	# 方向感由场体渐变 + 出口辉光承担，再加粗边会显得突兀（负责人反馈）。
	var frame_color := EDGE_HIGHLIGHT_COLOR
	frame_color.a = FRAME_ALPHA
	draw_rect(Rect2(Vector2.ZERO, _zone_size), frame_color, false, 1.0)
	_draw_stones()


## 场体沿重力方向的明度渐变：力源端亮、远端暗。
## 用顶点色让 GPU 插值（逐像素 draw_rect 会看出条带）。
func _draw_field_gradient() -> void:
	var horizontal := _pull_dir.x != 0.0
	var span := _zone_size.x if horizontal else _zone_size.y
	var segs := clampi(int(span / GRADIENT_SEG_TARGET_PX), 8, GRADIENT_SEG_MAX)
	var pull_toward_low := _pull_dir.x < 0.0 or _pull_dir.y < 0.0
	# 朝下区（2g 加重）：场体整体更亮一档，和 1g 的区区分开
	var field_alpha := FIELD_ALPHA * (DOWN_FIELD_BOOST if _is_down_zone() else 1.0)
	var far := FIELD_FAR_COLOR
	far.a = clampf(field_alpha, 0.0, 1.0)
	var near := FIELD_NEAR_COLOR
	near.a = clampf(field_alpha, 0.0, 1.0)

	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var c0 := far.lerp(near, pow(t0, GRADIENT_CURVE))
		var c1 := far.lerp(near, pow(t1, GRADIENT_CURVE))

		var a := span * t0
		var b := span * t1
		var lo := (span - b) if pull_toward_low else a
		var hi := (span - a) if pull_toward_low else b
		var dark := c0 if pull_toward_low else c1
		var bright := c1 if pull_toward_low else c0

		if horizontal:
			draw_polygon(
				PackedVector2Array([
					Vector2(lo, 0.0), Vector2(hi, 0.0),
					Vector2(hi, _zone_size.y), Vector2(lo, _zone_size.y),
				]),
				PackedColorArray([bright, bright, dark, dark])
			)
		else:
			draw_polygon(
				PackedVector2Array([
					Vector2(0.0, lo), Vector2(_zone_size.x, lo),
					Vector2(_zone_size.x, hi), Vector2(0.0, hi),
				]),
				PackedColorArray([bright, bright, dark, dark])
			)


## 重力指向侧的出口辉光：贴边亮、往场内渐隐，带呼吸与游走。
## 厚度取场短边的一半，铺满整个区的纵深，边界因此是柔和过渡而不是硬线。
func _draw_exit_glow() -> void:
	var short_side := minf(_zone_size.x, _zone_size.y)
	var thickness := short_side * GLOW_WIDTH_RATIO
	if thickness <= 0.0:
		return

	# 朝下区（2g 加重）：辉光更亮、呼吸更急，与 1g 的区区分开
	var glow_boost := DOWN_GLOW_BOOST if _is_down_zone() else 1.0
	var pulse_boost := DOWN_PULSE_BOOST if _is_down_zone() else 1.0

	var breath := sin(_time * GLOW_PULSE_SPEED * pulse_boost) * 0.5 + 0.5
	var alpha_scale := 1.0 - GLOW_PULSE_AMOUNT * 0.5 + GLOW_PULSE_AMOUNT * breath

	var along := _zone_size.x if _pull_dir.y != 0.0 else _zone_size.y
	var seg_count := maxi(int(along / GLOW_SEG_PX), 4)
	var seg_len := along / float(seg_count)
	var phase := _time * GLOW_FLOW_SPEED

	# 每段的两个端点各自算一次 alpha，相邻段共享端点值，色阶因此连续无台阶。
	for seg in seg_count:
		var s0 := float(seg) / float(seg_count)
		var s1 := float(seg + 1) / float(seg_count)
		# 光纹随相位平移，所以看着是"在流"而不是"在闪"。
		var wave0 := sin(s0 * TAU * GLOW_FLOW_WAVES + phase) * 0.5 + 0.5
		var wave1 := sin(s1 * TAU * GLOW_FLOW_WAVES + phase) * 0.5 + 0.5
		var a0 := GLOW_ALPHA * _glow_scale * glow_boost * alpha_scale * (1.0 - GLOW_FLOW_DEPTH + GLOW_FLOW_DEPTH * wave0)
		var a1 := GLOW_ALPHA * _glow_scale * glow_boost * alpha_scale * (1.0 - GLOW_FLOW_DEPTH + GLOW_FLOW_DEPTH * wave1)
		if a0 <= 0.004 and a1 <= 0.004:
			continue
		var c0 := GLOW_COLOR
		c0.a = clampf(maxf(a0, 0.0), 0.0, 1.0)
		var c1 := GLOW_COLOR
		c1.a = clampf(maxf(a1, 0.0), 0.0, 1.0)
		draw_polygon(_glow_quad(thickness, seg_len * float(seg), seg_len), _glow_colors(c0, c1))


## 当前是否是「朝下」的加重力区（2g）。判断依据和 player.gd 的 _zone_gravity 一致。
func _is_down_zone() -> bool:
	return _pull_dir.y > 0.0


## 辉光顶点色：沿边界方向用两头各自的 alpha（段内插值连续），
## 贴边不透明、场内全透明。
func _glow_colors(edge_start: Color, edge_end: Color) -> PackedColorArray:
	var clear_start := edge_start
	clear_start.a = 0.0
	var clear_end := edge_end
	clear_end.a = 0.0
	return PackedColorArray([edge_start, edge_end, clear_end, clear_start])


## 贴边到场内的一条辉光四边形。
func _glow_quad(depth: float, along: float, along_len: float) -> PackedVector2Array:
	var z := _zone_size
	if _pull_dir.x > 0.0:
		var x0 := z.x - depth
		return PackedVector2Array([
			Vector2(z.x, along), Vector2(z.x, along + along_len),
			Vector2(x0, along + along_len), Vector2(x0, along),
		])
	if _pull_dir.x < 0.0:
		return PackedVector2Array([
			Vector2(0.0, along), Vector2(0.0, along + along_len),
			Vector2(depth, along + along_len), Vector2(depth, along),
		])
	if _pull_dir.y > 0.0:
		var y0 := z.y - depth
		return PackedVector2Array([
			Vector2(along, z.y), Vector2(along + along_len, z.y),
			Vector2(along + along_len, y0), Vector2(along, y0),
		])
	return PackedVector2Array([
		Vector2(along, 0.0), Vector2(along + along_len, 0.0),
		Vector2(along + along_len, depth), Vector2(along, depth),
	])



## 石粒与拖尾（拖尾朝重力反方向、渐隐）。
func _draw_stones() -> void:
	var stone_color := STONE_COLOR
	stone_color.a = STONE_ALPHA
	var tail_dir := -_pull_dir
	var seg_len := TRAIL_LENGTH / float(TRAIL_SEGMENTS)

	for stone in _stones:
		var pos: Vector2 = stone["pos"]
		var size: float = stone["size"]
		for seg in TRAIL_SEGMENTS:
			var t := float(seg + 1) / float(TRAIL_SEGMENTS)
			var seg_color := STONE_COLOR
			seg_color.a = TRAIL_ALPHA * (1.0 - t)
			if seg_color.a <= 0.01:
				continue
			var tail_pos := pos + tail_dir * (seg_len * float(seg + 1))
			var thick := maxf(size * TRAIL_THICK_RATIO * (1.0 - t * 0.55), 1.0)
			draw_rect(Rect2(tail_pos.round(), Vector2(thick, thick)), seg_color)

		draw_rect(Rect2(pos.round(), Vector2(size, size)), stone_color)


## 四角淡色方块，只作边界暗示。
func _draw_corners() -> void:
	var corner := Vector2(CORNER_SIZE, CORNER_SIZE)
	var c := EDGE_HIGHLIGHT_COLOR
	c.a = CORNER_ALPHA
	draw_rect(Rect2(Vector2.ZERO, corner), c)
	draw_rect(Rect2(Vector2(_zone_size.x - CORNER_SIZE, 0.0), corner), c)
	draw_rect(Rect2(Vector2(0.0, _zone_size.y - CORNER_SIZE), corner), c)
	draw_rect(Rect2(_zone_size - corner, corner), c)


## 重力指向侧的高亮边；每层从不同 depth 起步，避免 alpha 叠成白条。
func _draw_pull_edge() -> void:
	var max_w := minf(EDGE_HIGHLIGHT_WIDTH, minf(_zone_size.x, _zone_size.y) * 0.5)
	var layers := 3
	for i in layers:
		var t := float(i) / float(maxi(layers - 1, 1))
		var width := maxf(max_w * (1.0 - t * 0.55), 1.0)
		var c := EDGE_HIGHLIGHT_COLOR
		c.a = lerpf(0.55, 0.16, t)
		draw_rect(_edge_rect(width, float(i)), c)


## 贴着重力指向侧、往场内缩进 depth、厚 width 的矩形。
func _edge_rect(width: float, depth: float) -> Rect2:
	if _pull_dir.x > 0.0:
		return Rect2(Vector2(_zone_size.x - depth - width, 0.0), Vector2(width, _zone_size.y))
	if _pull_dir.x < 0.0:
		return Rect2(Vector2(depth, 0.0), Vector2(width, _zone_size.y))
	if _pull_dir.y > 0.0:
		return Rect2(Vector2(0.0, _zone_size.y - depth - width), Vector2(_zone_size.x, width))
	return Rect2(Vector2(0.0, depth), Vector2(_zone_size.x, width))


## 编辑器专用：场中央的方向箭头。
func _draw_editor_arrow() -> void:
	var c := _zone_size * 0.5
	var tail := c - _pull_dir * 20.0
	var head := c + _pull_dir * 20.0
	draw_line(tail, head, EDGE_HIGHLIGHT_COLOR, 3.0)
	var perp := _pull_dir.rotated(PI * 0.5)
	draw_line(head, head - _pull_dir * 10.0 + perp * 8.0, EDGE_HIGHLIGHT_COLOR, 3.0)
	draw_line(head, head - _pull_dir * 10.0 - perp * 8.0, EDGE_HIGHLIGHT_COLOR, 3.0)
