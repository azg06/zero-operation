class_name Flag extends Node3D
## 占领旗帜(对应 map.js 的 Flag 类)

var id := "A"
var pos := Vector3.ZERO                 # 世界坐标(含地形高度)
var owner_team: Variant = null          # "us" | "ru" | null(改名:避开 Node.owner 冲突)
var progress := 0.0                     # -100 .. 100
var radius := 13.0
var sector := 0                         # 突破模式区域号
var locked := false
var contested := false
var veh_slot = null                     # 旗帜绑定载具

var _cloth_mat: ShaderMaterial
var _ring_mat: StandardMaterial3D
var _t := 0.0
var _pole: Node3D = null              # 旗杆
var _cloth: MeshInstance3D = null     # 旗面
var _ring: MeshInstance3D = null      # 占领圈
var _sign: Label3D = null             # 字母标牌(A/B/C)


static func make_cloth_material(color: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 albedo : source_color = vec4(0.53, 0.53, 0.53, 1.0);
uniform float wave_t = 0.0;
varying float v_w;
void vertex() {
	float w = (VERTEX.x + 1.6) / 3.2;
	v_w = w;
	VERTEX.z += sin(wave_t * 3.2 + VERTEX.x * 2.2) * 0.28 * w
		+ sin(wave_t * 5.1 + VERTEX.y * 3.0 + VERTEX.x) * 0.08 * w
		+ sin(wave_t * 7.3 + VERTEX.x * 4.1 + VERTEX.y * 2.4) * 0.05 * w;
	VERTEX.x += sin(wave_t * 4.4 + VERTEX.y * 2.6) * 0.06 * w;
}
void fragment() {
	float shade = 0.82 + v_w * 0.26;
	float fold = sin(v_w * 14.0 + wave_t * 6.0) * 0.5 + 0.5;
	ALBEDO = albedo.rgb * shade * (0.92 + fold * 0.14);
	ROUGHNESS = 0.9;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("albedo", color)
	return mat


static func make_ring_mesh(inner: float, outer: float, segs := 48) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var a0 := i / float(segs) * TAU
		var a1 := (i + 1) / float(segs) * TAU
		var v00 := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var v01 := Vector3(cos(a1) * inner, 0, sin(a1) * inner)
		var v10 := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var v11 := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		var n := Vector3.UP
		st.set_normal(n); st.add_vertex(v00)
		st.set_normal(n); st.add_vertex(v10)
		st.set_normal(n); st.add_vertex(v01)
		st.set_normal(n); st.add_vertex(v01)
		st.set_normal(n); st.add_vertex(v10)
		st.set_normal(n); st.add_vertex(v11)
	return st.commit()


func _init(flag_id: String, x: float, z: float) -> void:
	id = flag_id
	pos = Vector3(x, 0, z)
	position = Vector3(x, 0, z)
	_t = randf() * 10.0

	# 旗杆
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.09
	pole_mesh.bottom_radius = 0.12
	pole_mesh.height = 11.0
	pole_mesh.radial_segments = 8
	pole.mesh = pole_mesh
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color.html("#9a9a9a")
	pole_mat.roughness = 0.4
	pole_mat.metallic = 0.8
	pole.material_override = pole_mat
	pole.position.y = 5.5
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(pole)
	_pole = pole

	# 旗面(顶点着色器波动)
	var cloth := MeshInstance3D.new()
	var cloth_mesh := PlaneMesh.new()
	cloth_mesh.size = Vector2(3.2, 1.9)
	cloth_mesh.subdivide_width = 10
	cloth_mesh.subdivide_depth = 6
	cloth.mesh = cloth_mesh
	_cloth_mat = make_cloth_material(Color.html("#888888"))
	cloth.material_override = _cloth_mat
	cloth.position = Vector3(1.7, 9.6, 0)
	add_child(cloth)
	_cloth = cloth

	# 占领圈
	var ring := MeshInstance3D.new()
	ring.mesh = make_ring_mesh(radius - 0.5, radius)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.6, 0.6, 0.6, 0.55)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = _ring_mat
	ring.position.y = 0.06
	add_child(ring)
	_ring = ring

	# 字母标牌
	var sign_lbl := Label3D.new()
	sign_lbl.text = id
	sign_lbl.font_size = 84
	sign_lbl.pixel_size = 2.2 / 128.0
	sign_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_lbl.modulate = Color.WHITE
	sign_lbl.outline_size = 12
	sign_lbl.outline_modulate = Color(0.04, 0.05, 0.07, 0.85)
	sign_lbl.position.y = 12.3
	sign_lbl.no_depth_test = true
	add_child(sign_lbl)
	_sign = sign_lbl


## 战役模式:隐藏全部视觉(旗杆/旗面/占领圈/字母标牌),仅保留逻辑注册(bot 寻路/占点判定)
func hide_visuals() -> void:
	if _pole != null:
		_pole.visible = false
	if _cloth != null:
		_cloth.visible = false
	if _ring != null:
		_ring.visible = false
	if _sign != null:
		_sign.visible = false


func flag_color() -> Color:
	return Color.html("#00ff88") if owner_team == "us" else (Color.html("#ff5500") if owner_team == "ru" else Color.html("#999999"))


func update_flag(dt: float) -> void:
	_t += dt
	_cloth_mat.set_shader_parameter("wave_t", _t)
	var col := flag_color()
	_cloth_mat.set_shader_parameter("albedo", col)
	_ring_mat.albedo_color = Color(col, 0.45 + sin(_t * 4) * 0.15)
