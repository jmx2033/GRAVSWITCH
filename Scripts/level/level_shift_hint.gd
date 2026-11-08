extends Node2D

## 第 5 关的「改重力」按键示意图。
##
## ## 为什么做成运行时创建，不摆在场景里
##
## 之前把它写进 `level_4.tscn` 的节点里，结果**Godot 编辑器一保存就把属性覆盖了**
## —— 编辑器不认识的节点属性它会重算，位置和尺寸都被改掉。
## 改成运行时用代码搭，编辑器就碰不到了。
##
## ## 显示内容
##
## 空中：方向 + 空格 = 改变重力方向
##
## 位置在出生点正上方，玩家一出生就在视野里。

const HINT_FONT := preload("res://Data/word/press-start-2p-8px-square.ttf")

## 提示框左上角（像素）。第 5 关 y=2..6 是空白区，出生点在 (48, 272)。
const BOX_POS := Vector2(40, 96)
const BOX_SIZE := Vector2(260, 52)
const FONT_SIZE := 14


func _ready() -> void:
	_build_hint()


## 搭提示框：半透明底板 + 文字 + 指向出生点的箭头。
func _build_hint() -> void:
	var root := Node2D.new()
	root.name = "ShiftHint"
	root.z_index = 50
	root.position = BOX_POS
	add_child(root)

	var panel := ColorRect.new()
	panel.name = "Panel"
	panel.size = BOX_SIZE
	panel.color = Color(0.06, 0.05, 0.1, 0.78)
	root.add_child(panel)

	var label := Label.new()
	label.name = "Text"
	label.position = Vector2(8, 4)
	label.size = Vector2(BOX_SIZE.x - 16, BOX_SIZE.y - 8)
	label.add_theme_color_override("font_color", Color(0.85, 0.78, 1, 1))
	label.add_theme_font_override("font", HINT_FONT)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.text = "空中：方向 + 空格\n= 改变重力方向"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(label)

	# 箭头指向下方的出生点（出生点 x=48，提示框 x=40，箭头对到 x=8 附近）
	var arrow := Label.new()
	arrow.name = "Arrow"
	arrow.position = Vector2(8 - 20, BOX_SIZE.y - 2)
	arrow.size = Vector2(40, 20)
	arrow.add_theme_color_override("font_color", Color(0.85, 0.78, 1, 1))
	arrow.add_theme_font_size_override("font_size", 16)
	arrow.text = "▼"
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(arrow)
