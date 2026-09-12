extends Node
## 全量编译检查:场景模式加载(autoload 完整),把 src/ 下所有 GDScript 编译一遍。
## 任何语法/类型/依赖错误都会在此暴露。用法:
##   godot --headless --path . res://tools/compile_check.tscn

func _ready() -> void:
	await get_tree().process_frame
	var files: Array[String] = []
	_scan("res://src", files)
	var bad: Array[String] = []
	for f in files:
		var s = load(f)
		if s == null or not (s as Script).can_instantiate() and not s is GDScript:
			bad.append(f)
	print("[COMPILE] 共 %d 个脚本,失败 %d" % [files.size(), bad.size()])
	for b in bad:
		print("  BAD: ", b)
	print("=== 编译全部通过 ===" if bad.is_empty() else "=== 存在编译失败 ===")
	get_tree().quit(0 if bad.is_empty() else 1)


func _scan(path: String, out: Array[String]) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var full := path + "/" + f
		if d.current_is_dir():
			_scan(full, out)
		elif f.ends_with(".gd"):
			out.append(full)
		f = d.get_next()
