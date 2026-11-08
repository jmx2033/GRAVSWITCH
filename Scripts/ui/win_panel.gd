extends Control

## 通关结算页：全部四关走完后显示，提供「再玩一次 / 回主菜单 / 退出游戏」。
##
## 由 game.gd 在最后一关通关时显示并暂停游戏树。
## 视觉沿用暂停菜单那套（全屏压暗 + 毛玻璃面板 + ui_button 按钮）；
## 美术后续会提供专门的展示图，届时把 Art/ui/win_art.png 填进 %ArtSlot 即可，
## 没有图时那个 TextureRect 是隐藏的，不会留空白。

## 点「再玩一次」：请求从头再来。
signal retry_pressed

## 点「回主菜单」：请求切回主菜单。
signal menu_pressed

@onready var _art: TextureRect = %ArtSlot
@onready var _btn_retry: Button = %ButtonRetry
@onready var _btn_menu: Button = %ButtonMenu
@onready var _btn_quit: Button = %ButtonQuit

## 美术交付的通关展示图；文件不存在时留空。
const WIN_ART_PATH := "res://Art/ui/win_art.png"

## UI 音效挂载器（按钮悬停/按下）。
const UI_SFX_SCRIPT := preload("res://Scripts/ui/ui_sfx.gd")

# UI 音效挂载器。
var _ui_sfx: Node = null


func _ready() -> void:
	_btn_retry.pressed.connect(_on_retry_pressed)
	_btn_menu.pressed.connect(_on_menu_pressed)
	_btn_quit.pressed.connect(_on_quit_pressed)
	_load_art()

	# 按钮悬停/按下音效（挂载器自己是 ALWAYS，通关页暂停时也能响）
	_ui_sfx = UI_SFX_SCRIPT.new()
	add_child(_ui_sfx)
	_ui_sfx.attach_to(self)


## 打开结算页并把焦点交给「再玩一次」。
func open() -> void:
	visible = true
	_btn_retry.grab_focus()


## 载入美术的通关展示图；没有就隐藏那个槽位，并把按钮整体上移，避免中间空一块。
func _load_art() -> void:
	var has_art := ResourceLoader.exists(WIN_ART_PATH)
	if has_art:
		_art.texture = load(WIN_ART_PATH)
		_art.visible = true
		# 有图：按钮留在原位置，图占标题下方的空间
		_btn_retry.position.y = 156.0
		_btn_menu.position.y = 200.0
		_btn_quit.position.y = 244.0
	else:
		_art.texture = null
		_art.visible = false
		# 无图：三个按钮上移到紧跟标题，面板高度也收紧
		_btn_retry.position.y = 68.0
		_btn_menu.position.y = 112.0
		_btn_quit.position.y = 156.0
		var frost := _btn_retry.get_parent() as Control
		if frost != null:
			frost.size.y = 200.0


## 再玩一次。
func _on_retry_pressed() -> void:
	retry_pressed.emit()


## 回主菜单。
func _on_menu_pressed() -> void:
	menu_pressed.emit()


## 退出游戏。
func _on_quit_pressed() -> void:
	get_tree().quit()