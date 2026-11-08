extends Control

## 挑战关选关面板：一排挑战关按钮，点任意一个进入对应关卡。
## 样式与 settings_panel 一致（半透明遮罩 + 毛玻璃面板 + ui_button 样式）。

## 点返回时发出，由主菜单收起本面板。
signal closed

## 挑战关的场景列表；按顺序对应面板里的按钮。
## 加新挑战关时在这里追加，同时改下面的 CHALLENGE_NAMES。
const CHALLENGE_SCENES: Array[PackedScene] = [
	preload("res://Scenes/challenge_0.tscn"),
	preload("res://Scenes/challenge_1.tscn"),
	preload("res://Scenes/challenge_2.tscn"),
	preload("res://Scenes/challenge_3.tscn"),
]

## 挑战关名称，和 CHALLENGE_SCENES 一一对应。
const CHALLENGE_NAMES := ["挑战 1", "挑战 2 ", "挑战 3 ", "挑战 4"]

@onready var _list: VBoxContainer = %ButtonList
@onready var _btn_back: Button = %ButtonBack


func _ready() -> void:
	_btn_back.pressed.connect(_on_back_pressed)
	_copy_button_style(_btn_back)
	_build_buttons()


## 打开面板：显示并聚焦第一个按钮（没有按钮就聚焦返回）。
func open() -> void:
	visible = true
	if _list.get_child_count() > 0:
		_list.get_child(0).grab_focus()
	else:
		_btn_back.grab_focus()


## 按 CHALLENGE_SCENES 生成按钮列表。
## 用代码生成而不是在 .tscn 里摆死，是为了以后加关只改上面两个常量。
func _build_buttons() -> void:
	for i in CHALLENGE_SCENES.size():
		var btn := Button.new()
		btn.text = CHALLENGE_NAMES[i] if i < CHALLENGE_NAMES.size() else "CHALLENGE %d" % (i + 1)
		btn.custom_minimum_size = Vector2(240.0, 36.0)
		# 像素字体比原字体宽不少，字号压到 16 才放得下最长的一行
		btn.add_theme_font_size_override("font_size", 16)
		_copy_button_style(btn)
		btn.pressed.connect(_on_challenge_button_pressed.bind(i))
		_list.add_child(btn)


## 把按钮样式刷成和主菜单一致的 ui_button 风格（含深色文字，保证在浅色按钮底上看得清）。
## 主菜单的样式是 SubResource，这里没有引用，所以用代码构造同款 StyleBoxTexture。
func _copy_button_style(btn: Button) -> void:
	# 文字用深色：按钮底是浅米色的 ui_button，浅色字会看不清
	var ink := Color(0.102, 0.102, 0.102, 1.0)
	for key in ["font_color", "font_focus_color", "font_pressed_color",
			"font_hover_color", "font_hover_pressed_color"]:
		btn.add_theme_color_override(key, ink)
	btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.35, 0.35, 1.0))

	var tex: Texture2D = load("res://Art/ui/ui_button.png")
	if tex == null:
		return
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.content_margin_left = 12.0
		sb.content_margin_top = 4.0
		sb.content_margin_right = 12.0
		sb.content_margin_bottom = 4.0
		sb.texture_margin_left = 6.0
		sb.texture_margin_top = 6.0
		sb.texture_margin_right = 6.0
		sb.texture_margin_bottom = 6.0
		if state == "hover":
			sb.modulate_color = Color(1.25, 1.25, 1.25, 1.0)
		elif state == "focus":
			sb.modulate_color = Color(1.15, 1.15, 1.15, 1.0)
			sb.draw_center = false
		btn.add_theme_stylebox_override(state, sb)


## 点了某个挑战关：切到对应场景。
func _on_challenge_button_pressed(index: int) -> void:
	if index < 0 or index >= CHALLENGE_SCENES.size():
		return
	var scene := CHALLENGE_SCENES[index]
	if scene == null:
		push_error("challenge_select.gd：第 %d 个挑战关未设置" % index)
		return
	Transition.transition(
		func() -> void: get_tree().change_scene_to_packed(scene),
		true
	)


## 点返回：通知主菜单收起面板。
func _on_back_pressed() -> void:
	closed.emit()
