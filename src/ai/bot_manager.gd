class_name BotManager extends Node
## AI 管理器(对应 ai.js 的 BotManager)
## 职责:生成/销毁、小队编制、每局兵种武器分配、按玩家表现动态平衡

var bots: Array = []

# ---- 动态平衡 ----
var base_per_team := 11
var target_per_team := 11
var balance_cd := 0.0
var enemy_skill_mod := 0.0       # 敌队技能系数修正(胶带平衡:票差越大敌方越强)
var enemy_respawn_mod := 1.0     # 敌方重生延迟倍率

const CLASS_POOL := ["assault", "assault", "assault", "assault", "engineer", "engineer", "support", "support", "recon", "recon", "recon"]
const WEAPONS := {
	"assault": { "us": ["m4", "ak", "scar", "aug"], "ru": ["ak", "ak", "scar", "aug"] },
	"engineer": { "us": ["m249", "pkm", "rpd"], "ru": ["pkm", "rpd", "rpd"] },
	"support": { "us": ["mp5", "ump", "p90"], "ru": ["mp5", "ump", "p90"] },
	"recon": { "us": ["awm", "m24", "m24"], "ru": ["svd", "svd", "m24"] },
}


func reset(per_team := 11) -> void:
	if OS.has_feature("web"):
		per_team = 6  # Web 端 AI 减半,大幅降低 CPU 开销
	base_per_team = per_team
	target_per_team = per_team
	enemy_skill_mod = 0.0
	enemy_respawn_mod = 1.0
	Bot._noise_log = []  # 换图:清空战场噪音日志,防止 AI 听到上一张图的枪声
	for b in bots:
		b.queue_free()
	bots = []
	G.bots = bots
	for i in per_team:
		var b := Bot.new("us")
		bots.append(b)
		G.main.add_child(b)
	for i in per_team + 1:
		var b := Bot.new("ru")
		bots.append(b)
		G.main.add_child(b)
	# 每局兵种/武器分布:按 CLASS_POOL 打乱后分配,保证突击/工程/支援/侦察齐全
	_assign_loadouts()
	_assign_skills()
	# 小队编制:每 4 人一队,玩家加入第一友军小队
	G.squads = []
	var sq_id := 0
	for team in ["us", "ru"]:
		var mates := bots.filter(func(b): return b.team == team)
		var i := 0
		while i < mates.size():
			var sq := { "id": sq_id, "team": team, "members": mates.slice(i, i + 4) }
			sq_id += 1
			for m in sq["members"]:
				m.squad_id = sq["id"]
			G.squads.append(sq)
			i += 4
	for s in G.squads:
		if s["team"] == G.player.team:
			G.player_squad = s
			break
	# 指派载具驾驶员(突破模式进攻方更多,配合装甲推进)
	var us_d := 0
	var ru_d := 0
	var need_us := 4 if G.mode == "breakthrough" else 3
	var need_ru := 3
	for b in bots:
		if b.team == "us" and us_d < need_us:
			b.can_drive = true
			us_d += 1
		elif b.team == "ru" and ru_d < need_ru:
			b.can_drive = true
			ru_d += 1
	for b in bots:
		b.respawn_t = Utils.rand(0, 2)
		b.alive = false
		b.mesh.visible = false


## 每局兵种分布:池子洗牌保证各兵种齐全,武器随兵种+阵营随机
func _assign_loadouts() -> void:
	for team in ["us", "ru"]:
		var mates := bots.filter(func(b): return b.team == team)
		mates.shuffle()
		for i in mates.size():
			var cid: String = CLASS_POOL[i % CLASS_POOL.size()]
			var pool: Array = WEAPONS[cid][team]
			var wid: String = Utils.choice(pool)
			(mates[i] as Bot).apply_loadout(cid, wid)


## 技能系数:开局基线 ± 随机;胶带平衡由敌方修正项叠加
func _assign_skills() -> void:
	for b in bots:
		var base := 0.8 if b.team == "us" else 0.82
		b.skill = clampf(base + Utils.rand(-0.14, 0.14), 0.45, 1.1)


func update_bots(dt: float) -> void:
	_update_balance(dt)
	for b in bots:
		if not b.alive:
			if b.mesh.visible:
				b.update_bot(dt)  # 死亡动画
			b.respawn_t -= dt
			if b.respawn_t <= 0 and G.state == "playing":
				b.respawn_t = Utils.rand(4, 7) * (enemy_respawn_mod if b.team != (G.player.team if G.player != null else "us") else 1.0)
				G.game.spawn_actor(b)
			continue
		b.update_bot(dt)


## ==================== 动态平衡(12 秒一拍) ====================
func _update_balance(dt: float) -> void:
	balance_cd -= dt
	if balance_cd > 0:
		return
	balance_cd = 12.0
	if G.state != "playing" or G.player == null:
		return
	# 战役模式:敌人由战役控制器生成/补兵,票差胶带与 K/D 动态平衡均不适用
	if G.mode == "campaign":
		return
	# 突破模式票数天生不对称(攻 250/def ∞),票差胶带不适用,跳过
	if G.mode == "breakthrough":
		return
	# 票差胶带:我方大优 → 敌方变强/复活变快;我方大劣 → 敌方变弱
	var tdiff: float = G.tickets[G.player.team] - (G.tickets["ru"] if G.player.team == "us" else G.tickets["us"])
	if tdiff > 80:
		enemy_skill_mod = 0.15
		enemy_respawn_mod = 0.8
	elif tdiff > 30:
		enemy_skill_mod = 0.06
		enemy_respawn_mod = 0.92
	elif tdiff < -80:
		enemy_skill_mod = -0.12
		enemy_respawn_mod = 1.4
	elif tdiff < -30:
		enemy_skill_mod = -0.05
		enemy_respawn_mod = 1.2
	else:
		enemy_skill_mod = 0.0
		enemy_respawn_mod = 1.0
	# 玩家 K/D 窗口:表现越好敌方越多(上限 13/队),越差越少(下限 8/队)
	var kd := (float(G.stats.kills) + 1.0) / (float(G.stats.deaths) + 1.0)
	if kd > 2.2:
		target_per_team = base_per_team + 2
	elif kd > 1.4:
		target_per_team = base_per_team + 1
	elif kd < 0.25:
		target_per_team = base_per_team - 2
	elif kd < 0.45:
		target_per_team = base_per_team - 1
	else:
		target_per_team = base_per_team
	target_per_team = clampi(target_per_team, 8, 13)
	# 应用:每队数量对齐目标
	var p_team: String = G.player.team
	for team in ["us", "ru"]:
		var c := 0
		for b in bots:
			if b.team == team:
				c += 1
		if c < target_per_team:
			# 补员:生成新 bot 快速入场
			var cid: String = Utils.choice(CLASS_POOL)
			var nb := Bot.new(team)
			nb.apply_loadout(cid, Utils.choice(WEAPONS[cid][team]))
			nb.skill = clampf(0.8 + Utils.rand(-0.14, 0.14), 0.45, 1.1)
			bots.append(nb)
			G.bots = bots
			G.main.add_child(nb)
			nb.respawn_t = Utils.rand(1, 3)
			nb.alive = false
			nb.mesh.visible = false
		elif c > target_per_team:
			# 缩员:拉长已死 bot 的重生,自然减员
			var extra := c - target_per_team
			var cut := 0
			for b in bots:
				if cut >= extra:
					break
				if b.team == team and not b.alive:
					b.respawn_t = maxf(b.respawn_t, 9.0)
					cut += 1
	# 敌队技能基线随胶带调整(玩家队保持 0.8 基线,公平性)
	for b in bots:
		if b.team != p_team:
			b.skill = clampf(0.82 + enemy_skill_mod + Utils.rand(-0.1, 0.1), 0.45, 1.1)
