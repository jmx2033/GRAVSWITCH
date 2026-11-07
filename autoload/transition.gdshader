shader_type canvas_item;

// 黑幕扫到的位置：1.0 = 整屏透明（看不见遮罩），0.0 = 整屏全黑。
uniform float cutoff : hint_range(0.0, 1.0);
// 边缘柔化宽度。0 = 纯硬边像素块；0.1 = 只在扫过的那几块上渐隐，块本身仍然是整块切换。
uniform float feather : hint_range(0.0, 1.0) = 0.1;
// 一个像素块的边长（以游戏内像素计）。8 在 640×360 下就是 80×45 块。
uniform float block_px = 8.0;
// 每一行的随机错位量（单位：块）。0 = 齐平的直线，3 = 错开 1~3 格，阶梯最明显。
uniform float jitter = 3.0;

float cell_rand(vec2 c) {
	return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// 视口尺寸 ÷ 块边长 = 网格数；至少 1×1，避免极小窗口下除以 0。
	vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 grid = max(floor(screen_px / block_px), vec2(1.0));
	vec2 cell = floor(UV * grid);

	// 用块的左边缘（块内是常量）而不是 UV.x，所以一整块同时切换，块内不会出现软边。
	float bx = float(cell.x) / grid.x;
	// 逐行向左错开 → 边缘呈阶梯状；只往左偏，保证 cutoff=1.0 时不会残留黑块。
	bx = max(bx - cell_rand(vec2(0.0, cell.y)) * jitter / grid.x, 0.0);

	vec4 col = vec4(0.0, 0.0, 0.0, 1.0);
	col.a = smoothstep(cutoff - feather, cutoff, bx * (1.0 - feather));
	COLOR = col;
}
