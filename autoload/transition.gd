extends Node

## 转场遮罩：canvas_item shader 的 cutoff 驱动「像素块横扫」的黑幕。
## cutoff = 1.0 整屏透明（看不见遮罩），cutoff = 0.0 整屏全黑。
##
## 时序契约：黑幕全黑之后才动游戏状态。
##   FADE_OUT → HOLD → action() →（await_scene 时等新场景就位）→ FADE_IN
##
## 所有「重生 / 切场景 / 换关」都必须走 transition()，不要裸调 respawn()
## 或 change_scene_to_*：那等于「先瞬移、后盖黑」，跳变会露在全亮画面上。
##
## mouse_filter = 2 设在 effect（ColorRect）上，不写在这里——本脚本 extends Node，
## Node 没有 mouse_filter 属性。根节点的 process_mode = 3(ALWAYS) 也在 .tscn 里，
## 否则从暂停菜单退场时整棵树暂停、补间不走，会永久卡在全黑。

@export var effect: ColorRect

## 等新场景就位的最长时间（毫秒）。超时也照常退幕，避免加载失败时永久黑屏。
const SCENE_WAIT_TIMEOUT_MS := 3000

## 正在过渡中。重入请求直接丢弃，避免两条补间抢同一个 shader 参数。
var _busy: bool = false

## 当前补间；只在需要掐断时用，正常流程靠 await finished 串起来。
var _tween: Tween = null


func _ready() -> void:
	if effect == null:
		push_error("Transition：effect 未绑定，过渡不会生效")
		return
	# 遮罩是纯装饰，必须完全穿透鼠标，否则它是全局输入黑洞，所有 UI 都点不了。
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_cutoff(1.0)


## 一次完整过渡。action 可以留空（只闪一下黑）。
##
## await_scene = true 时，会在 action 之后等 current_scene 真的换掉再退幕。
## change_scene_to_* 是延迟到帧末执行的，不退幕就会露出半加载的新场景。
func transition(action: Callable = Callable(), await_scene := false) -> void:
	if _busy:
		push_warning("Transition：上一次过渡还没结束，本次调用被忽略")
		return
	if effect == null or effect.material == null:
		# 遮罩坏了也不能吞掉 action，否则玩家会卡死在原地。
		if action.is_valid():
			action.call()
		return

	_busy = true
	await _play(action, await_scene)
	_busy = false


func _play(action: Callable, await_scene: bool) -> void:
	await _fade_to(0.0, Config.TRANSITION_FADE_OUT)
	await _wait(Config.TRANSITION_HOLD)

	# 全黑之后才动游戏状态——玩家看不到跳变的那一帧。
	if action.is_valid():
		action.call()

	if await_scene:
		await _wait_scene_ready()

	await _fade_to(1.0, Config.TRANSITION_FADE_IN)


## 补间 cutoff 到目标值。duration <= 0 视为零时长，直接赋值。
func _fade_to(target: float, duration: float) -> void:
	if duration <= 0.0:
		_set_cutoff(target)
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(effect.material, "shader_parameter/cutoff", target, duration)
	await _tween.finished


## 停顿。SceneTreeTimer 默认 process_always = true，暂停中也会走完。
func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout


## 等 get_tree().current_scene 换成新场景。
##
## 不能用固定时间：新场景要加载贴图、重建图块，耗时不固定。
## 也不能只判 current_scene != null：切换过程中它可能先变 null 再变成新场景，
## 只判非空会在半路就退幕。所以记下旧引用，等「换成了一个别的、且非空的场景」。
func _wait_scene_ready() -> void:
	var previous: Node = get_tree().current_scene
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < SCENE_WAIT_TIMEOUT_MS:
		await get_tree().process_frame
		var current: Node = get_tree().current_scene
		if current != null and current != previous:
			return
	push_warning("Transition：等新场景超时 %d ms，直接退幕" % SCENE_WAIT_TIMEOUT_MS)


## effect.material 的静态类型是 Material，set_shader_parameter 在 ShaderMaterial 上。
func _set_cutoff(value: float) -> void:
	if effect == null:
		return
	var mat := effect.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("cutoff", value)
