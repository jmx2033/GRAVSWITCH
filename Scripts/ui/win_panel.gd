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


## 载入美术的通关展示图；没有就隐藏那个槽位。
##
## 11/7 美术交付了一张 320×300 的**面板底图**（`win_panel_bg.png`），
## 已经铺在 Frost 上。所以这里**不再压缩面板高度**——压成 200 会把底图挤变形。
## 按钮改为在标题下方居中排布，底部留白由底图自己的装饰填充。
func _load_art() -> void:
	var has_art := ResourceLoader.exists(WIN_ART_PATH)
	if has_art:
		_art.texture = load(WIN_ART_PATH)
		_art.visible = true
		# 有展示图：图放标题下方，按钮依次往下
		_art.position.y = 98.0
		_btn_retry.position.y = 186.0
		_btn_menu.position.y = 230.0
		_btn_quit.position.y = 274.0
	else:
		_art.texture = null
		_art.visible = false
		# 无展示图：按钮在标题下方居中排布（间隔 44 = 36 高 + 8 间隙）
		_btn_retry.position.y = 112.0
		_btn_menu.position.y = 156.0
		_btn_quit.position.y = 200.0


## 再玩一次。
func _on_retry_pressed() -> void:
	retry_pressed.emit()


## 回主菜单。
func _on_menu_pressed() -> void:
	menu_pressed.emit()


## 退出游戏。
func _on_quit_pressed() -> void:
	get_tree().quit()