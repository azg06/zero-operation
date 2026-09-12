shader_type spatial;
render_mode cull_back;

// NPC 士兵调色 shader:网格顶点色 R 通道存部件 id(0.1~0.8),
// 按 id 从 8 色调色板取色 —— 一个士兵 GLB 通吃 4 兵种 x 3 皮肤 x 2 队伍。
// 部件表(与 build_soldier.py 约定一致):
//   0.1 uniform 军服 / 0.2 vest 背心 / 0.3 helmet 头盔 / 0.4 gear 装具深色
//   0.5 skin 皮肤 / 0.6 boot 靴 / 0.7 accent 队伍识别 / 0.8 gear2 装具帆布

uniform vec3 pal_uniform : source_color = vec3(0.29, 0.33, 0.28);
uniform vec3 pal_vest : source_color = vec3(0.23, 0.29, 0.35);
uniform vec3 pal_helmet : source_color = vec3(0.23, 0.27, 0.22);
uniform vec3 pal_gear : source_color = vec3(0.2, 0.22, 0.18);
uniform vec3 pal_skin : source_color = vec3(0.78, 0.63, 0.5);
uniform vec3 pal_boot : source_color = vec3(0.15, 0.13, 0.12);
uniform vec3 pal_accent : source_color = vec3(0.0, 1.0, 0.53);
uniform vec3 pal_gear2 : source_color = vec3(0.34, 0.35, 0.27);
uniform float roughness : hint_range(0.0, 1.0) = 0.92;

// ★第一人称身体专用:俯角看到底时躯干"让位"(默认关闭 ⇒ NPC 完全不受影响)。
// 眼位离胸顶只有 25cm,胸口一旦可见就必然把脚挡死(几何无解:视线越过胸顶前缘落到
// 地面的距离 = 1.65·胸前面/眼到胸顶高),所以低头到底时按模型高度把躯干逐段剔除,
// 露出大腿/靴子 —— BF/COD 同款处理。只删"视图",网格/骨骼/影子都不动。
uniform float fp_yield = 0.0;     // 0=正常  1=躯干段完全让位(整段抖动溶解,无硬切边)

varying float v_fp_h;

void vertex() {
	v_fp_h = VERTEX.y;            // 蒙皮后的模型空间高度(骨骼系 = 世界高度,身体只绕 Y 转)
}

void fragment() {
	// 躯干段(0.92~1.55m)按 fp_yield 做屏幕有序抖动溶解:整段一起淡出,
	// 不会留下"被横切一刀、从断面看进胸腔内部"的硬边。
	if (fp_yield > 0.002 && v_fp_h > 0.92 && v_fp_h < 1.55) {
		float thr = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
		if (thr < fp_yield) {
			discard;
		}
	}
	int idx = clamp(int(round(COLOR.r * 10.0)) - 1, 0, 7);
	vec3 cols[8] = vec3[8](
		pal_uniform, pal_vest, pal_helmet, pal_gear,
		pal_skin, pal_boot, pal_accent, pal_gear2
	);
	vec3 col = cols[idx];
	ALBEDO = col;
	ROUGHNESS = roughness;
	// 队伍识别条自发光(敌我辨识,接游戏内霓虹识别条惯例)
	if (idx == 6) {
		EMISSION = col * 0.55;
	}
}
