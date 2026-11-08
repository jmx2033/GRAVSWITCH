extends RefCounted

## 按钮之间的矩形排斥：让塌落的按钮像积木一样互相推开、不重叠、也不抖动。
##
## ## 为什么不用 Godot 的 RigidBody2D
##
## 试过刚体方案（按钮配一个 freeze=false 的 RigidBody2D 代理）：
## 引擎确实会把重叠的刚体分开，但**推开后刚体会继续漂**，
## 下帧又被拉回目标位置——两者拉扯，按钮就一直抖。
## 而且静态刚体（freeze=true）根本不会互推。
##
## 所以改成**每帧直接算排斥**：位置完全由我们控制，稳、不抖。
##
## ## 怎么避免"交换位置"
##
## 分离时**必须沿最小重叠轴**，而且方向要由位置关系唯一确定：
## 用 `delta`（B 中心 - A 中心）的符号决定往哪边推。
## 如果只用"重叠最浅的轴"而不管符号，两个按钮中心几乎水平对齐时，
## 微小的 y 差会让整排翻转 —— 看起来就是"挤一下位置对调了"。
##
## 另一个要点：**分离量要对称**（各退一半），不能一个跑另一个不动，
## 否则会连锁把别的也挤走。

## 最小间隙：两个按钮之间至少留这么远的空隙。
const DEFAULT_GAP := 3.0
## 每次求解最多迭代几轮。多轮迭代能让挤成一堆的按钮逐层散开。
const MAX_ITERATIONS := 12
## 分离的最小步长：太小会让按钮"几乎贴着"却不分开，
## 太大又会一下推太远、看起来像弹射。
const MIN_PUSH := 0.5


## 求解：给每个元素算一个不会互相重叠的目标位置。
##
## items 里每一项是 {node: Control, to: Vector2}，to 用**全局坐标**。
## 返回 {node: Vector2}，每个节点的最终位置（全局坐标）。
func solve(items: Array, gap: float = DEFAULT_GAP) -> Dictionary:
	var result := {}
	if items.is_empty():
		return result

	# 1) 初始位置 = 目标位置
	var pos: Array[Vector2] = []
	for item in items:
		pos.append(item["to"])

	# 2) 反复排斥，直到没有重叠
	for _iter in MAX_ITERATIONS:
		var moved := false
		for i in items.size():
			for j in range(i + 1, items.size()):
				var a: Control = items[i]["node"]
				var b: Control = items[j]["node"]
				var ra := Rect2(pos[i] - a.size * 0.5, a.size).grow(gap * 0.5)
				var rb := Rect2(pos[j] - b.size * 0.5, b.size).grow(gap * 0.5)
				if not ra.intersects(rb):
					continue

				# 沿**最小重叠轴**分离；方向由中心连线的符号唯一确定。
				var delta := pos[j] - pos[i]
				var overlap_x: float = (ra.size.x + rb.size.x) * 0.5 - absf(delta.x)
				var overlap_y: float = (ra.size.y + rb.size.y) * 0.5 - absf(delta.y)
				var push := Vector2.ZERO
				if overlap_x < overlap_y:
					# 水平重叠更浅 -> 水平分
					# 方向：把 j 推向 delta.x 的方向；若 delta.x 几乎为 0，
					# 就用 j 在 i 的哪边来定（用 x 坐标比较，不用符号，避免翻转）
					var dir_x: float = 1.0
					if absf(delta.x) > 0.5:
						dir_x = signf(delta.x)
					else:
						dir_x = 1.0 if pos[j].x >= pos[i].x else -1.0
					push = Vector2(dir_x * maxf(overlap_x * 0.5, MIN_PUSH), 0.0)
				else:
					# 垂直分：同样用位置关系定方向，不看 delta.y 的符号
					# （delta.y 接近 0 时符号会因微小抖动翻转）
					var dir_y: float = 1.0
					if absf(delta.y) > 0.5:
						dir_y = signf(delta.y)
					else:
						dir_y = 1.0 if pos[j].y >= pos[i].y else -1.0
					push = Vector2(0.0, dir_y * maxf(overlap_y * 0.5, MIN_PUSH))
				pos[i] -= push
				pos[j] += push
				moved = true
		if not moved:
			break

	# 3) 写回
	for i in items.size():
		var node2: Control = items[i]["node"]
		result[node2] = pos[i]
	return result
