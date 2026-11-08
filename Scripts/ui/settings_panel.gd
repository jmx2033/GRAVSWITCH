extends Control

## 共享设置面板：音量滑块 + 键位表，供主菜单与暂停菜单复用。
## 根节点设 process_mode = ALWAYS，主菜单和暂停时都能交互。
## 音量改完直接存盘，两处入口共用同一个配置文件。

## 点「返回」时发出，由宿主决定收起面板或回到上级焦点。
signal closed

## 音量记忆文件（存在 user:// 下，不占仓库）。
const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "audio"
const KEY_VOLUME := "master_volume"

@onready var _slider: HSlider = %VolumeSlider
@onready var _label: Label = %VolumeLabel
@onready var _btn_back: Button = %ButtonBack


func _ready() -> void:
	_slider.value_changed.connect(_on_volume_changed)
	_btn_back.pressed.connect(_on_back_pressed)
	_load_volume()


## 打开面板：显示并把焦点交给返回按钮。
func open() -> void:
	visible = true
	_btn_back.grab_focus()


## 点返回：通知宿主收起本面板。
func _on_back_pressed() -> void:
	closed.emit()


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
