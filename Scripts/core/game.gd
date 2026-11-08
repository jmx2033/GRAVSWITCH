extends Node

## 主场景控制器：按顺序加载关卡，统一处理死亡重生、R 重载和暂停。
##
## 关卡只负责地形与出生点；存活流程集中在这里，换关或加状态机时不用改玩家脚本。

## 按顺序排列的关卡；通关后自动进入下一关，最后一关通关后停留在当前关。
@export var levels: Array[PackedScene] = []

## 暂停菜单场景。
const PAUSE_MENU_SCENE := preload("res://Scenes/pause_menu.tscn")

## 通关结算页场景；全部四关走完后显示。
const WIN_PANEL_SCENE := preload("res://Scenes/win_panel.tscn")

## 覆盖层（暂停菜单、通关页）的绘制层级；要盖过关卡与玩家，给一个足够高的值。
const OVERLAY_Z_INDEX := 100

## 负责 Config.RESPAWN_DELAY 秒后的重生；超时后把玩家送回出生点。
@onready var _respawn_timer: Timer = $RespawnTimer

# 当前关卡实例，切关时先卸载它。
var _current_level: Node = null
# 当前关卡在 levels 中的下标；-1 表示当前关卡不在序列里。
var _level_index: int = -1
# 当前关卡的玩家，通过 player 组查找；关卡重新加载后会重新获取。
var _player: Node = null
# 当前关卡的出生点，来自关卡里的 Spawn 节点。
var _spawn_position: Vector2 = Vector2.ZERO
# 暂停菜单实例；它自己是 ALWAYS 模式，暂停期间仍能交互。
var _pause_menu: Control = null
# 通关结算页实例；同样是 ALWAYS，显示时整棵树被暂停但按钮仍可点。
var _win_panel: Control = null


## 初始化重生计时器并加载起始关卡。
func _ready() -> void:
	# 本节点保持默认 INHERIT：暂停时关卡、玩家、重生计时器都跟着树一起冻结。
	# 暂停键由 pause_menu（ALWAYS）自己监听，见 pause_menu.gd。
	# 场景里的 wait_time 只是默认值，实际时长以 Config 为准，方便统一调整。
	_respawn_timer.wait_time = Config.RESPAWN_DELAY
	_respawn_timer.timeout.connect(_on_respawn_timer_timeout)

	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	add_child(_pause_menu)
	_pause_menu.resumed.connect(_on_pause_resumed)
	_pause_menu.quit_to_menu.connect(_on_pause_quit)
	# 注意：不要把它 visible 设成 false —— Godot 里不可见的 Control 不处理输入，
	# 暂停键就再也收不到了。它的显示由内部 Content 容器控制。
	# 绘制层级：z_index 拉高，并在每次加载关卡后把它挪到子节点末尾，
	# 否则后加的关卡会盖在菜单上面（关卡和菜单的 z_index 都是 0，按子节点顺序绘制）。
	_pause_menu.z_index = OVERLAY_Z_INDEX

	_win_panel = WIN_PANEL_SCENE.instantiate()
	add_child(_win_panel)
	_win_panel.retry_pressed.connect(_on_win_retry)
	_win_panel.menu_pressed.connect(_on_win_menu)
	_win_panel.z_index = OVERLAY_Z_INDEX
	_win_panel.get_node("%Content").visible = false

	if levels.is_empty():
		push_error("game.gd：levels 未配置")
		return
	_load_level(levels[0])


## 处理 R 重开；放在 _unhandled_input 里，不抢 UI 的输入。
## 暂停期间本节点被冻结，所以要重开先按 Esc 恢复。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("restart"):
		return
	get_viewport().set_input_as_handled()
	if _level_index < 0:
		return
	var scene: PackedScene = levels[_level_index]
	Transition.transition(func() -> void: change_level(scene))


## 暂停菜单点「继续」：pause_menu 已自行解除暂停，这里只做确认。
func _on_pause_resumed() -> void:
	# pause_menu 内部已经 get_tree().paused = false，这里留作扩展点。
	pass


## 暂停菜单点「回主菜单」：切回主菜单场景（pause_menu 已自行解除暂停）。
## 黑幕盖满之后才真的切，避免退回菜单时看到上一帧的关卡画面。
func _on_pause_quit() -> void:
	Transition.transition(
		func() -> void: get_tree().change_scene_to_file("res://Scenes/mainmenu.tscn"),
		true
	)


## 切换到指定关卡场景；传 null 时什么也不做。
func change_level(level_scene: PackedScene) -> void:
	if level_scene == null:
		return
	if is_instance_valid(_current_level):
		remove_child(_current_level)
		_current_level.queue_free()
	_respawn_timer.stop()
	_load_level(level_scene)


## 加载关卡：重置全局重力，缓存出生点，并连接玩家的 died / won 信号。
func _load_level(level_scene: PackedScene) -> void:
	# 重载场景时 autoload 不会重置；先恢复基础向下重力，避免残留上一局的合力。
	Config.gravity_acceleration = Vector2.DOWN * Config.GRAVITY
	_respawn_timer.stop()

	var level: Node = level_scene.instantiate()
	add_child(level)
	_current_level = level
	_level_index = levels.find(level_scene)
	# 关卡是后加的子节点，会盖在暂停菜单/通关页上面；把它们挪到末尾保持在最上层。
	# 顺序：先暂停菜单、再通关页，保证通关页在暂停菜单之上（两者不会同时显示）。
	if _pause_menu != null and is_instance_valid(_pause_menu):
		move_child(_pause_menu, get_child_count() - 1)
	if _win_panel != null and is_instance_valid(_win_panel):
		move_child(_win_panel, get_child_count() - 1)

	var spawn: Node2D = level.get_node_or_null("Spawn") as Node2D
	if spawn != null:
		_spawn_position = spawn.global_position
	else:
		push_warning("game.gd：关卡缺少 Spawn，重生点使用 (0, 0)")

	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_error("game.gd：关卡里找不到 player 组的节点")
		return
	# 缺信号时只报错并跳过连接，避免 connect 在运行时抛错。
	if not _player.has_signal("died"):
		push_error("game.gd：玩家节点缺少 died 信号")
		return
	_player.connect("died", _on_player_died)
	if not _player.has_signal("won"):
		push_error("game.gd：玩家节点缺少 won 信号")
		return
	_player.connect("won", _on_player_won)

	# 从第 5 关（下标 4）起授权「空中改重力」。
	# 前四关不授权，玩家只能靠重力区改变方向——那些关的谜题全建立在这个前提上。
	# 第 5 关是教学关（用虚空坑引出机制）。
	# 授权集中写在这里而不是每关一个参数，是因为「哪一关开能力」是游戏流程的决定，
	# 不该散落到各个关卡场景里。
	const FIRST_SHIFT_LEVEL := 4
	var can_shift: bool = _level_index >= FIRST_SHIFT_LEVEL
	if can_shift and _player.has_method("enable_gravity_shift"):
		_player.call("enable_gravity_shift")


## 玩家死亡后发起过渡；重生实际发生在黑幕全黑的那一刻（die() 已幂等，不用防重复）。
func _on_player_died() -> void:
	Transition.transition(_respawn_player)


## 把玩家送回缓存的出生点。由 Transition 在黑幕全黑时调用。
func _respawn_player() -> void:
	if not is_instance_valid(_player):
		return
	_player.call("respawn", _spawn_position)


## 计时结束，把玩家送回缓存的出生点。
## 【11/7】重生时机已交由过渡接管，这个 Timer 不再启动；保留是为了不删场景里的节点。
func _on_respawn_timer_timeout() -> void:
	_respawn_player()


## 通关音效响多久之后再弹结算页，让「通关」那一声先落下去。
## 音效本身 0.8 秒，先给 0.3 秒让琶音的前半段出来，画面再压暗，
## 否则结算页一出就把整个画面盖住、音效被视觉抢走。
const WIN_PANEL_DELAY := 0.3


## 玩家通关后停掉重生计时；有下一关就切过去，否则显示通关结算页。
func _on_player_won() -> void:
	_respawn_timer.stop()
	if _level_index < 0:
		return
	var next_index: int = _level_index + 1
	if next_index >= levels.size():
		# 最后一关通关 = 整个游戏通关一次，写下解锁标记供主菜单使用。
		Progress.mark_game_cleared()
		_show_win_panel_delayed()
		return
	Transition.transition(func() -> void: change_level(levels[next_index]))


## 等 WIN_PANEL_DELAY 秒再显示结算页。
##
## 用 create_timer 的 process_always 参数（默认 true）保证这段等待不受暂停影响；
## 计时期间玩家已经 is_won，本来就不响应输入，所以不会有操作被吞。
func _show_win_panel_delayed() -> void:
	await get_tree().create_timer(WIN_PANEL_DELAY).timeout
	_show_win_panel()


## 显示通关结算页：冻结整棵树（玩家已经 is_won，本来就不响应输入，
## 冻结是为了让石粒、辉光这些也在最后一帧停住，画面更收束）。
func _show_win_panel() -> void:
	if _win_panel == null:
		return
	get_tree().paused = true
	_win_panel.get_node("%Content").visible = true
	_win_panel.open()


## 通关页点「再玩一次」：解除暂停并回到第一关。
func _on_win_retry() -> void:
	get_tree().paused = false
	_win_panel.get_node("%Content").visible = false
	if levels.is_empty():
		return
	Transition.transition(func() -> void: change_level(levels[0]))


## 通关页点「回主菜单」：解除暂停并切回主菜单。
func _on_win_menu() -> void:
	get_tree().paused = false
	_win_panel.get_node("%Content").visible = false
	Transition.transition(
		func() -> void: get_tree().change_scene_to_file("res://Scenes/mainmenu.tscn"),
		true
	)
