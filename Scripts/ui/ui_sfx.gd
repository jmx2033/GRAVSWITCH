extends Node

## UI 音效挂载器：给一棵 Control 子树里的所有按钮挂上「悬停 / 按下」音效。
##
## 用法：把它加成目标面板的子节点，然后：
##     ui_sfx.attach_to(some_panel)
## 也可以直接把面板作为父节点、调 attach_to(get_parent())。
##
## 音色沿用整套音效的玉音风格（见 docs/14），频率高于游戏内音效、音量压低，
## 因为 UI 触发的次数远多于跳跃落地，做响了会烦。

const HOVER_SFX: AudioStream = preload("res://Audio/sfx/sfx_ui_hover.wav")
const PRESS_SFX: AudioStream = preload("res://Audio/sfx/sfx_ui_press.wav")

## 悬停音压得很低：它一秒钟可能触发好几次。
const HOVER_VOLUME_DB := -12.0
## 按下音稍响一点，但仍比游戏内音效轻。
const PRESS_VOLUME_DB := -7.0

# 两个播放器分别负责悬停与按下，互不打断。
var _hover_player: AudioStreamPlayer = null
var _press_player: AudioStreamPlayer = null


func _ready() -> void:
	# UI 在暂停期间也要能响（暂停菜单、通关页的按钮都在这套流程里）
	process_mode = Node.PROCESS_MODE_ALWAYS

	_hover_player = _make_player(HOVER_SFX, HOVER_VOLUME_DB)
	_press_player = _make_player(PRESS_SFX, PRESS_VOLUME_DB)


## 递归给 root 下所有 Button 挂上悬停/按下音效。
## 重复调用同一个按钮不会重复连接（先断开再连）。
func attach_to(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is Button:
			_hook(child)
		# 按钮内部可能还有子节点（比如图标），一并往下走
		attach_to(child)


## 建一个专用播放器；UI 音效要能被连续触发，所以给它多点复音。
func _make_player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.max_polyphony = 4
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


## 给单个按钮接上信号。
## 同时接 mouse_entered 和 focus_entered：鼠标移入与键盘切换焦点都要有反馈，
## 否则纯键盘玩的人听不到任何提示。
func _hook(btn: Button) -> void:
	# 先断开，避免同一按钮被挂多次（attach_to 可能被调用两遍）
	if btn.mouse_entered.is_connected(_on_hover):
		btn.mouse_entered.disconnect(_on_hover)
	if btn.focus_entered.is_connected(_on_hover):
		btn.focus_entered.disconnect(_on_hover)
	if btn.pressed.is_connected(_on_press):
		btn.pressed.disconnect(_on_press)
	btn.mouse_entered.connect(_on_hover)
	btn.focus_entered.connect(_on_hover)
	btn.pressed.connect(_on_press)


## 鼠标移入按钮或键盘把焦点移上来。
func _on_hover() -> void:
	if _hover_player != null:
		_hover_player.play()


## 按钮被按下。
func _on_press() -> void:
	if _press_player != null:
		_press_player.play()