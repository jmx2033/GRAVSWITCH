extends Node2D

## 挑战关控制器：挑战关不走 game.gd 那套四关流程，所以自己监听玩家通关并显示结算页。
##
## 与 game.gd 的分工：game.gd 管四关顺序切换与重生，这里只管「通关了 → 弹结算页 → 重开或回主菜单」。
## 结算页是同一个 Scenes/win_panel.tscn，视觉与四关通关完全一致。

## 走到终点后弹出结算页；不接 main.tscn 的通关流程。
const WIN_PANEL_SCENE := preload("res://Scenes/win_panel.tscn")

## 结算页要盖在关卡之上。
const OVERLAY_Z_INDEX := 100

@onready var _spawn: Marker2D = $Spawn
@onready var _player: Node = $Player

# 运行时实例化的结算页；默认隐藏。
var _win_panel: Control = null


func _ready() -> void:
	_win_panel = WIN_PANEL_SCENE.instantiate()
	add_child(_win_panel)
	_win_panel.z_index = OVERLAY_Z_INDEX
	_win_panel.retry_pressed.connect(_on_win_retry)
	_win_panel.menu_pressed.connect(_on_win_menu)
	_win_panel.get_node("%Content").visible = false
	# 挑战关根节点是 Node2D，结算页挂在它下面拿不到视口矩形，
	# anchors 会退化成 0×0 而被摆到左上角。所以显式把它铺满屏幕。
	_fit_to_viewport()
	_win_panel.resized.connect(_fit_to_viewport)

	if not _player.has_signal("won"):
		push_error("challenge_level.gd：玩家节点缺少 won 信号")
		return
	_player.connect("won", _on_player_won)


## 让结算页铺满整个视口。
##
## 挑战关根节点是 Node2D，结算页挂它下面拿不到父容器的矩形，而 .tscn 里用的是
## anchors_preset=15（四边拉满），没有可参照的父矩形时尺寸会退化成 0×0，
## 面板就被摆到左上角。所以这里把 anchors 清掉、改成纯绝对尺寸。
## （必须先改 anchors：否则 Godot 会在 _ready 之后按 anchors 重算尺寸，覆盖掉设值。）
func _fit_to_viewport() -> void:
	if _win_panel == null:
		return
	var vp_size := get_viewport_rect().size
	_pin_to_rect(_win_panel, vp_size)
	var content: Control = _win_panel.get_node("%Content")
	_pin_to_rect(content, vp_size)


## 把一个 Control 钉成 (0,0)–size 的绝对矩形，不受 anchors 影响。
func _pin_to_rect(ctrl: Control, rect_size: Vector2) -> void:
	ctrl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ctrl.position = Vector2.ZERO
	ctrl.size = rect_size


## 通关音效响多久之后再弹结算页；与 game.gd 的 WIN_PANEL_DELAY 保持一致。
const WIN_PANEL_DELAY := 0.3


## 玩家通关：等通关音效先响一下，再冻结整棵树并显示结算页。
## 与四关通关的观感一致：先听到琶音，画面才压暗。
func _on_player_won() -> void:
	# 计时器参数 process_always 默认 true，暂停后也会照常走完。
	await get_tree().create_timer(WIN_PANEL_DELAY).timeout
	get_tree().paused = true
	_win_panel.get_node("%Content").visible = true
	_win_panel.open()


## 点「再玩一次」：挑战关只有这一关，所以重开本关。
## 重开用 respawn 而不是重新加载场景，避免结算页实例被销毁后信号断掉。
func _on_win_retry() -> void:
	get_tree().paused = false
	_win_panel.get_node("%Content").visible = false
	if not is_instance_valid(_player):
		return
	_player.call("respawn", _spawn.global_position)


## 点「回主菜单」：解除暂停并切回主菜单。
func _on_win_menu() -> void:
	get_tree().paused = false
	_win_panel.get_node("%Content").visible = false
	get_tree().change_scene_to_file("res://Scenes/mainmenu.tscn")