extends Control

## 暂停菜单：变暗遮罩 + 继续 / 回主菜单 / 设置。
## 根节点 process_mode = ALWAYS 且始终 visible（Godot 里不可见的 Control 不处理输入，
## 所以显示/隐藏靠内部的 Content 容器，而不是根本身）。
## 关卡 / 玩家 / 计时器是 INHERIT，会被 get_tree().paused 冻结，人物才能真正停下来。

## 点「继续」时发出，表示玩家选择恢复游戏。
signal resumed

## 点「回主菜单」时发出，表示玩家要离开关卡。
signal quit_to_menu

## 共享设置面板场景，_ready 里实例化一份。
const SETTINGS_PANEL_SCENE := preload("res://Scenes/settings_panel.tscn")

## UI 音效挂载器（按钮悬停/按下）。
const UI_SFX_SCRIPT := preload("res://Scripts/ui/ui_sfx.gd")

@onready var _content: Control = %Content
@onready var _btn_continue: Button = %ButtonContinue
@onready var _btn_menu: Button = %ButtonMenu
@onready var _btn_settings: Button = %ButtonSettings

# 运行时实例化的设置面板；默认隐藏。
var _settings: Control = null
# 是否处于暂停状态。
var _paused: bool = false
# UI 音效挂载器。
var _ui_sfx: Node = null


func _ready() -> void:
	_btn_continue.pressed.connect(_on_continue_pressed)
	_btn_menu.pressed.connect(_on_menu_pressed)
	_btn_settings.pressed.connect(_on_settings_pressed)

	_settings = SETTINGS_PANEL_SCENE.instantiate()
	add_child(_settings)
	_settings.closed.connect(_on_settings_closed)
	_settings.visible = false

	# 按钮悬停/按下音效（挂载器自己是 ALWAYS，暂停期间也能响）
	_ui_sfx = UI_SFX_SCRIPT.new()
	add_child(_ui_sfx)
	_ui_sfx.attach_to(self)

	# 根节点始终保持可见，否则收不到输入；内容由 _content 控制。
	visible = true
	_content.visible = false
	# 显式开启未处理输入，确保暂停键一定能收到（不依赖引擎默认推断）。
	set_process_unhandled_input(true)


## 监听 Esc/P 切换暂停；本节点是 ALWAYS 且始终 visible，暂停期间也能收到输入。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	_toggle_pause()


## 切换暂停状态：冻结整棵树并显示菜单，或解冻并隐藏。
func _toggle_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused
	if _paused:
		_show_menu()
	else:
		_hide_menu()


## 显示暂停菜单并聚焦「继续」。
func _show_menu() -> void:
	_close_settings()
	_content.visible = true
	_btn_continue.grab_focus()


## 隐藏暂停菜单。
func _hide_menu() -> void:
	_close_settings()
	_content.visible = false


## 点「继续」：解除暂停并隐藏菜单。
func _on_continue_pressed() -> void:
	if not _paused:
		return
	_paused = false
	get_tree().paused = false
	_hide_menu()
	resumed.emit()


## 点「回主菜单」：解除暂停，发信号让 game.gd 切场景。
func _on_menu_pressed() -> void:
	_paused = false
	get_tree().paused = false
	_hide_menu()
	quit_to_menu.emit()


## 点「设置」：弹出设置面板。
func _on_settings_pressed() -> void:
	_settings.open()


## 设置面板点返回：隐藏它并回到暂停菜单的「继续」。
func _on_settings_closed() -> void:
	_settings.visible = false
	_btn_continue.grab_focus()


## 确保设置面板收起。
func _close_settings() -> void:
	if _settings != null:
		_settings.visible = false
