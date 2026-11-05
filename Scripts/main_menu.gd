extends Control

## 主菜单：开始 / 设置 / 退出。
## 设置面板里可以拖动音量滑块，直接改 Master 总线音量，并记住到本地配置。

## 点开始后要加载的场景。
@export var game_scene: PackedScene = preload("res://Scenes/main.tscn")

## 音量记忆文件（存在 user:// 下，不占仓库）。
const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "audio"
const KEY_VOLUME := "master_volume"

@onready var _btn_play: Button = $ButtonPlay
@onready var _btn_settings: Button = $ButtonSettings
@onready var _btn_quit: Button = $ButtonQuit
@onready var _panel: Control = $SettingsPanel
@onready var _slider: HSlider = $SettingsPanel/Frost/VolumeSlider
@onready var _label: Label = $SettingsPanel/Frost/VolumeLabel
@onready var _btn_back: Button = $SettingsPanel/ButtonBack


func _ready() -> void:
	_btn_play.pressed.connect(_on_play_pressed)
	_btn_settings.pressed.connect(_on_settings_pressed)
	_btn_quit.pressed.connect(_on_quit_pressed)
	_btn_back.pressed.connect(_on_back_pressed)

	_slider.value_changed.connect(_on_volume_changed)
	_panel.visible = false

	_load_volume()
	_btn_play.grab_focus()


## 进入游戏。
func _on_play_pressed() -> void:
	if game_scene == null:
		push_error("main_menu.gd：game_scene 未设置")
		return
	get_tree().change_scene_to_packed(game_scene)


## 打开设置面板。
func _on_settings_pressed() -> void:
	_panel.visible = true
	_btn_back.grab_focus()


## 从设置面板返回。
func _on_back_pressed() -> void:
	_panel.visible = false
	_btn_play.grab_focus()


## 退出游戏。
func _on_quit_pressed() -> void:
	get_tree().quit()


## 拖动音量滑块：立刻改 Master 总线音量，并存盘。
func _on_volume_changed(value: float) -> void:
	_apply_volume(value)
	_save_volume(value)
	_label.text = "Volume: %d%%" % int(round(value * 100.0))


## 把 0~1 的音量比例应用到 Master 总线。
## 0 时静音（-80dB 是 Godot 的静音阈值），其余按对数换算成 dB。
func _apply_volume(ratio: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if ratio <= 0.001:
		AudioServer.set_bus_mute(bus, true)
	else:
		AudioServer.set_bus_mute(bus, false)
		AudioServer.set_bus_volume_db(bus, linear_to_db(ratio))


## 读取上次保存的音量；没有配置文件时默认 100%。
func _load_volume() -> void:
	var cfg := ConfigFile.new()
	var ratio := 1.0
	if cfg.load(SETTINGS_PATH) == OK:
		ratio = float(cfg.get_value(SECTION, KEY_VOLUME, 1.0))
	_slider.set_value_no_signal(ratio)
	_apply_volume(ratio)
	_label.text = "Volume: %d%%" % int(round(ratio * 100.0))


## 把当前音量写回配置文件。
func _save_volume(ratio: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION, KEY_VOLUME, ratio)
	cfg.save(SETTINGS_PATH)
