extends Node2D

## 主菜单围绕屏幕四边顺时针流动的「呼吸灯」。
##
## ## 这是什么
##
## 一圈贴着屏幕四边的光带，亮部**顺时针**沿边框流动（俯视看：上边右→右，
## 右边上→下，下边右→左，左边下→上），同时亮度缓慢起伏（呼吸）。
## 它**不随方向键改变**——方向键改的是「重力场」的辉光
## （见 menu_gravity_field.gd），这条灯是固定的装饰性效果。
##
## ## 为什么不用重力区那套辉光
##
## 重力区辉光是「贴着重力指向侧」的一条带，方向随重力变。
## 这条灯是**围着四周框**走一圈、方向固定，所以单独画。
##
## ## 参数
##
## - 光带宽度 60px（负责人指定）
## - 顺时针流动：沿「上→右→下→左」的顺序绕一圈
## - 呼吸：整体亮度起伏；亮部自身也在移动，两者叠加

## 光带宽度（像素，垂直于边框方向）。
## 负责人要求「覆盖三分之一屏幕」，所以按视口高度的 1/3 算（640×360 -> 120px）。
const BAND_WIDTH_RATIO := 1.0 / 3.0
const BAND_WIDTH := 120.0
## 亮部数量：整圈有几个亮块。
const LIGHT_COUNT := 4
## 亮部占整圈周长的比例。
const LIGHT_LENGTH_RATIO := 0.3
## 流动速度（整圈周长/秒）。正值 = 顺时针。
const FLOW_SPEED := 0.13
## 呼吸速度（每秒）。
const BREATH_SPEED := 1.0
## 呼吸幅度：亮度在 (1-幅度) ~ (1+幅度) 之间摆。
const BREATH_AMOUNT := 0.45
## 亮部颜色与峰值透明度（偏紫，和重力场的紫调一致）。
const LIGHT_COLOR := Color("#B08CFF")
const LIGHT_ALPHA := 0.34

## 动画时钟。
var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return

	var breath := sin(_time * BREATH_SPEED) * 0.5 + 0.5
	var alpha_scale := 1.0 - BREATH_AMOUNT * 0.5 + BREATH_AMOUNT * breath

	# 整圈周长：上边 + 右边 + 下边 + 左边
	var w := view.x
	var h := view.y
	var perimeter := 2.0 * (w + h)

	# 顺时针：沿「上边右→右、 右边 上→下、 下边 右→左、 左边 下→上」走。
	# 用一个 0..1 的参数 s 表示沿周长的位置，顺时针递增。
	var phase := fposmod(_time * FLOW_SPEED, 1.0)
	var light_len := LIGHT_LENGTH_RATIO

	for i in LIGHT_COUNT:
		var center := fposmod(phase + float(i) / float(LIGHT_COUNT), 1.0)
		# 亮部可能跨过周长起点，拆成两段画
		_draw_arc_segment(view, perimeter, center - light_len * 0.5,
			center + light_len * 0.5, alpha_scale)
		if center - light_len * 0.5 < 0.0:
			_draw_arc_segment(view, perimeter, center - light_len * 0.5 + 1.0,
				center + light_len * 0.5 + 1.0, alpha_scale)
		elif center + light_len * 0.5 > 1.0:
			_draw_arc_segment(view, perimeter, center - light_len * 0.5 - 1.0,
				center + light_len * 0.5 - 1.0, alpha_scale)


## 画一段亮部（沿周长的参数范围 s0..s1，0..1 对应整圈）。
##
## 每段亮部沿「边框线 → 内侧」做渐变：贴边最亮，往里渐隐。
func _draw_arc_segment(view: Vector2, perimeter: float, s0: float, s1: float,
		alpha_scale: float) -> void:
	if s1 <= 0.0 or s0 >= 1.0 or s1 <= s0:
		return
	var segs := maxi(int((s1 - s0) * perimeter / 5.0), 2)
	var seg_len := (s1 - s0) / float(segs)

	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		# 段内亮度：两头 0（暗）、中间 1（亮）
		var b0 := sin(t0 * PI)
		var b1 := sin(t1 * PI)
		var a0 := LIGHT_ALPHA * alpha_scale * b0
		var a1 := LIGHT_ALPHA * alpha_scale * b1
		if a0 <= 0.004 and a1 <= 0.004:
			continue
		var c0 := LIGHT_COLOR
		c0.a = clampf(a0, 0.0, 1.0)
		var c1 := LIGHT_COLOR
		c1.a = clampf(a1, 0.0, 1.0)
		_draw_band_quad(view, perimeter, s0 + seg_len * float(i),
			s0 + seg_len * float(i + 1), c0, c1)


## 沿周长取一段，画成「贴边亮、内侧渐隐」的四边形。
func _draw_band_quad(view: Vector2, perimeter: float, s0: float, s1: float,
		edge0: Color, edge1: Color) -> void:
	var w := view.x
	var h := view.y
	var band := _band_width(view)
	var p0 := _perimeter_point(view, perimeter, s0)
	var p1 := _perimeter_point(view, perimeter, s1)
	# 内侧方向：指向屏幕中心
	var n0 := _inward_normal(view, p0)
	var n1 := _inward_normal(view, p1)
	var clear0 := edge0
	clear0.a = 0.0
	var clear1 := edge1
	clear1.a = 0.0
	draw_polygon(
		PackedVector2Array([
			p0, p1, p1 + n1 * band, p0 + n0 * band,
		]),
		PackedColorArray([edge0, edge1, clear1, clear0])
	)


## 光带宽度：按视口高度的 1/3（负责人要求覆盖三分之一屏幕）。
func _band_width(view: Vector2) -> float:
	return maxf(view.y * BAND_WIDTH_RATIO, BAND_WIDTH * 0.5)


## 周长参数 s（0..1）对应的边框上的点。
##
## 顺时针顺序：上边（左→右）→ 右边（上→下）→ 下边（右→左）→ 左边（下→上）。
func _perimeter_point(view: Vector2, perimeter: float, s: float) -> Vector2:
	var w := view.x
	var h := view.y
	var d := s * perimeter
	if d < w:
		return Vector2(d, 0.0)
	d -= w
	if d < h:
		return Vector2(w, d)
	d -= h
	if d < w:
		return Vector2(w - d, h)
	d -= w
	return Vector2(0.0, h - d)


## 边框上某点指向屏幕内部的单位方向。
func _inward_normal(view: Vector2, p: Vector2) -> Vector2:
	var c := view * 0.5
	var d := c - p
	if d.length() < 0.001:
		return Vector2.DOWN
	return d.normalized()
