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

void fragment() {
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
