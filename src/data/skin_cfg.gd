class_name SkinCfg
## 玩家兵种皮肤存档(皮肤契约层;UI 团队调用 save_skin,Player 层读取应用)
## 存档:user://skin_cfg.cfg,ConfigFile,根键 class_<class_id>,值皮肤 id 字符串(如 "arctic")
## 无配置/非法值一律回退 "standard";皮肤 id 是否真实存在由 SoldierModel.build_soldier
## 内部防御回退(soldier_model.gd SKINS 表 .get(skin, standard)),本层只做合法性兜底。

const PATH := "user://skin_cfg.cfg"

const VALID_CLASSES := ["assault", "engineer", "support", "recon"]


## 读档:class_<class_id> 有非空值则返回,否则 "standard";class_id 非法回退 "standard"
static func get_skin(class_id: String) -> String:
	if class_id not in VALID_CLASSES:
		return "standard"
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return "standard"
	var skin: String = str(cf.get_value("", "class_%s" % class_id, "standard"))
	if skin == "":
		return "standard"
	return skin


## 写档:仅接受合法 class_id + 非空皮肤 id(皮肤 id 不设白名单,防 Visual 团队新增皮肤时被拒)
static func save_skin(class_id: String, skin_id: String) -> void:
	if class_id not in VALID_CLASSES or skin_id == "":
		return
	var cf := ConfigFile.new()
	cf.load(PATH)
	cf.set_value("", "class_%s" % class_id, skin_id)
	cf.save(PATH)


## 该兵种是否已配置皮肤(区别于默认 standard)
static func has_skin(class_id: String) -> bool:
	if class_id not in VALID_CLASSES:
		return false
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return false
	var v = cf.get_value("", "class_%s" % class_id, null)
	return v != null and str(v) != ""
