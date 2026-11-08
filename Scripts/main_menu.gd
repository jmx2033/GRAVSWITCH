extends Control

## 主菜单：开始 / 挑战关（通关后解锁）/ 设置 / 退出。
## 设置使用共享的 settings_panel 场景，主菜单与暂停菜单复用同一份。

## 点开始后要加载的场景。
@export var game_scene: PackedScene = preload("res://Scenes/main.tscn")

## 挑战关选关面板场景，点挑战关按钮时弹出。
const CHALLENGE_SELECT_SCENE := preload("res://Scenes/challenge_select.tscn")

## 共享设置面板场景，_ready 里实例化一份。
const SETTINGS_PANEL_SCENE := preload("res://Scenes/settings_panel.tscn")

## UI 音效挂载器（按钮悬停/按下）；同一份逻辑也给暂停菜单等其它面板复用。
const UI_SFX_SCRIPT := preload("res://Scripts/ui/ui_sfx.gd")

## 主菜单重力场效果（背景石粒 + 方向键切换重力）。
const MENU_GRAVITY_FX := preload("res://Scripts/ui/menu_gravity_fx.gd")

@onready var _btn_play: Button = $ButtonPlay
@onready var _btn_challenge: Button = $ButtonChallenge
@onready var _btn_settings: Button = $ButtonSettings
@onready var _btn_quit: Button = $ButtonQuit

# 运行时实例化的设置面板；默认隐藏。
var _panel: Control = null
# 运行时实例化的挑战关选关面板；默认隐藏。
var _challenge_panel: Control = null
# UI 音效挂载器。
var _ui_sfx: Node = null
# 重力场效果（背景石粒）。
var _gravity_fx: Node2D = null


func _ready() -> void:
	_btn_play.pressed.connect(_on_play_pressed)
	_btn_challenge.pressed.connect(_on_challenge_pressed)
	_btn_settings.pressed.connect(_on_settings_pressed)
	_btn_quit.pressed.connect(_on_quit_pressed)

	_panel = SETTINGS_PANEL_SCENE.instantiate()
	add_child(_panel)
	_panel.closed.connect(_on_panel_closed)
	_panel.visible = false

	_challenge_panel = CHALLENGE_SELECT_SCENE.instantiate()
	add_child(_challenge_panel)
	_challenge_panel.closed.connect(_on_challenge_closed)
	_challenge_panel.visible = false

	# 挑战关入口只在"通关过一次"之后出现；未解锁时它完全不占位。
	var unlocked := Progress.is_challenge_unlocked()
	_btn_challenge.visible = unlocked

	# 按钮悬停/按下音效。等隐藏状态定下来再挂，避免给不可见的按钮也接一遍。
	_ui_sfx = UI_SFX_SCRIPT.new()
	add_child(_ui_sfx)
	_ui_sfx.attach_to(self)

	# 重力场效果：背景石粒 + 方向键让整体"倒"向一侧。
	# 必须在其它 UI 都就位后再挂，这样它才能收集到所有需要跟着倒的元素。
	_gravity_fx = MENU_GRAVITY_FX.new()
	add_child(_gravity_fx)
	# 石粒要画在所有 UI 之下，但节点是在 UI 之后 add 的，所以显式压低层级。
	_gravity_fx.z_index = -50
	# 等一帧再收集：确保所有子节点都已就位
	await get_tree().process_frame
	_gravity_fx.call("_collect_ui")

	_btn_play.grab_focus()


## 进入游戏。
func _on_play_pressed() -> void:
	if game_scene == null:
		push_error("main_menu.gd：game_scene 未设置")
		return
	# 黑幕盖满之后才真的进关，玩家不会看到菜单被瞬间替换。
	Transition.transition(
		func() -> void: get_tree().change_scene_to_packed(game_scene),
		true
	)


## 打开挑战关选关面板。
func _on_challenge_pressed() -> void:
	_challenge_panel.open()


## 选关面板点返回：隐藏面板并把焦点还给挑战关按钮。
func _on_challenge_closed() -> void:
	_challenge_panel.visible = false
	_btn_challenge.grab_focus()


## 打开设置面板。
func _on_settings_pressed() -> void:
	_panel.open()


## 设置面板点返回：隐藏面板并把焦点还给开始按钮。
func _on_panel_closed() -> void:
	_panel.visible = false
	_btn_play.grab_focus()


## 退出游戏。
func _on_quit_pressed() -> void:
	get_tree().quit()
