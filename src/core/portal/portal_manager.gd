class_name PortalManager extends Node
## 门户模式(Portal)管理器:团队死斗(TDM)/大逃杀(BR)的注册与事件总线
## ------------------------------------------------------------------
## 职责:
## - 模式注册:start_mode(mode, map_id) 按模式加载 GameMode_* 脚本并实例化
## - 事件驱动:转发模式控制器的 score/eliminated/mvp/round_ended 信号,
##   UI 统一监听 G.portal.*(为未来多人同步预留,禁止轮询其他模块内部状态)
## - 对局生命周期:round_started → 模式控制器运行 → round_ended 收尾
## - 玩家本局统计(player_stats:击杀/死亡/助攻,由 player_eliminated 信号累计)
## 基类契约(GameMode_Portal 由 TDM Agent 交付,src/core/portal/game_mode_portal.gd):
##   score_changed(us_score, ru_score) / player_eliminated(victim, killer, head) /
##   mvp_changed(mvp: Dictionary) / round_ended(result: Dictionary)
##   on_player_killed(killer, victim, head) / on_damage(attacker, victim, amount)
## 结束对局两条路径(二选一,先到先得):
##   A) 模式自身判定结束 → emit round_ended(result)(展示层由模式负责,本节点
##      仅转发 + 清理 + G.state="end",不重复弹结算屏)
##   B) 外部强制结束 → G.portal.end_match(result):先调 active.end() 交模式结算
##      (模式如自行 emit round_ended 则由路径 A 接管);模式未收尾时本节点补齐
##      结算屏展示(G.hud.show_end,同 game.gd end_match 流程)

signal round_started(mode: String, map_id: String, player_count: int)
signal round_ended(result: Dictionary)      # result 含 mode/winner_team/scores/top_players/mvp/player_stats
signal portal_hint(text: String)            # 模式提示文案(main.gd 已接 G.hud.hint)
## 模式控制器信号转发(UI 统一监听 G.portal,无需直接挂 active)
signal score_changed(us_score: int, ru_score: int)
signal player_eliminated(victim, killer, head: bool)
signal mvp_changed(mvp: Dictionary)

## 模式 → 模式控制器脚本路径(文件由 TDM/BR Agent 并行创建,缺失时防御跳过)
const MODE_SCRIPTS := {
	"tdm": "res://src/core/portal/game_mode_tdm.gd",
	"br": "res://src/core/portal/game_mode_br.gd",
}

var current_mode := ""                        # 进行中模式("tdm"/"br")
var current_map_id := ""                      # 本局地图 id(round_started 回传)
var active = null                             # GameMode_Portal 实例(模式控制器)
var player_stats := {}                        # 本局玩家 { 名字: {kills, deaths, assists} }
var _abort_pending := false                   # 主动放弃标记(end_match 传 aborted → 注入结算 result)

# ---- BR/TDM 只读镜像字段(hud.gd _update_portal_hud 每帧轮询 G.portal;由模式控制器每帧回写) ----
# 补充说明:由 BR/TDM Agent 按 UI 契约补入(模式控制器在 tick 中镜像,缺省值对另一模式无影响)
var br_alive := 0
var br_total := 100
var zone_center := Vector3.ZERO
var zone_radius := 0.0
var br_alive_teams := 0            # BR 存活队伍数(hud.gd 优先读,缺失回退个人存活数)
var br_total_teams := 0            # BR 总队伍数
var tdm_target := 0                # TDM 目标击杀数
var tdm_time_left := -1.0          # TDM 剩余时间(秒,-1=未启动)


## 启动门户对局:实例化对应 GameMode_* 接管(mode 脚本缺失时警告并跳过,不崩溃)
func start_mode(mode: String, map_id: String) -> void:
	if active != null:
		# 防御:上一局未收尾(如模式控制器中断) → 先结束再开新局
		end_match({})
	if not MODE_SCRIPTS.has(mode):
		push_warning("[PORTAL] 未知门户模式 \"%s\"(可用: %s),已跳过开局" % [mode, MODE_SCRIPTS.keys()])
		return
	var path: String = MODE_SCRIPTS[mode]
	if not ResourceLoader.exists(path):
		push_warning("[PORTAL] 模式脚本未就绪(并行开发中): %s,已跳过开局" % path)
		return
	var scr = load(path)
	if scr == null or not scr.can_instantiate():
		push_warning("[PORTAL] 模式脚本解析失败: %s,已跳过开局" % path)
		return
	var gm: Variant = scr.new()
	gm.name = "GameMode_" + mode.to_upper()
	add_child(gm)
	active = gm
	current_mode = mode
	current_map_id = map_id
	player_stats = {}
	# 转发模式控制器信号(UI 监听本节点)
	gm.score_changed.connect(func(us, ru): score_changed.emit(us, ru))
	gm.player_eliminated.connect(_on_eliminated)
	gm.mvp_changed.connect(func(m): mvp_changed.emit(m))
	gm.round_ended.connect(_on_round_ended)
	# round_started 转发(参照 round_ended):模式在 start() 内自行 emit 时经本节点统一广播;
	# 未自行广播的模式由下方兜底补齐(标志位防双发)
	var gm_broadcasted := false
	gm.round_started.connect(func(m, mi, pc):
		gm_broadcasted = true
		round_started.emit(m, mi, pc))
	gm.start(map_id)
	if not gm_broadcasted:
		round_started.emit(mode, map_id, _player_count())


## 外部强制结束:交模式自身结算(路径 A 优先);模式未收尾时本节点补齐收尾+展示
func end_match(result: Dictionary) -> void:
	if active == null and current_mode == "":
		return  # 无进行中/待清理对局,幂等跳过
	# 主动放弃标记:main 退出对局时传 {"aborted": true};模式自行组装 result 时
	# (如 TDM end() 重建 result)由 _finish_round 统一注入,防误判战败
	_abort_pending = bool(result.get("aborted", false))
	var gm: Variant = active
	if gm != null:
		gm.end()  # 模式自身结算(通常会 emit round_ended → 路径 A 接管收尾与展示)
		if active == gm:
			_finish_round(result, true)  # 模式未自行 emit → 本节点收尾 + 接结算屏
	else:
		_finish_round(result, false)


## 模式自身判定结束(路径 A):仅转发 + 清理,展示层已由模式完成
func _on_round_ended(result: Dictionary) -> void:
	if active == null:
		return  # 防御:重复 emit / 收尾期间的再入
	_finish_round(result, false)


func _finish_round(result: Dictionary, display: bool) -> void:
	var r: Dictionary = result
	if r.is_empty():
		# 兜底 result:模式未提供时补齐骨架(winner_team 默认 draw)
		r = {
			"mode": current_mode, "map_id": current_map_id,
			"winner_team": "draw", "scores": {},
			"top_players": [], "mvp": "", "player_stats": player_stats,
		}
	# 主动放弃标记注入(模式自组装 result 会丢失 aborted 键,见 end_match)
	if _abort_pending:
		r["aborted"] = true
		_abort_pending = false
	var gm: Variant = active
	active = null
	current_mode = ""
	current_map_id = ""
	round_ended.emit(r)
	if gm != null:
		gm.queue_free()
	G.state = "end"
	if display:
		# 结算流程(参考 game.gd end_match):锁释放 + 隐藏 HUD → 结算屏
		if G.input_sys != null:
			G.input_sys.unlock()
		if G.hud != null:
			G.hud.hide_screen("hud")
			G.hud.hide_screen("death")
			G.hud.hide_screen("deploy")
			var winner: String = str(r.get("winner_team", "draw"))
			var my_team: String = G.player.team if G.player != null else "us"
			var my_win: bool = winner != "draw" and winner == my_team
			G.hud.show_end(my_win)
			if my_win:
				AudioSys.win()
			else:
				AudioSys.lose()


## 模式提示入口(模式控制器调用 G.portal.hint("..."),main.gd 已接到 G.hud.hint)
func hint(text: String) -> void:
	portal_hint.emit(text)


## 玩家本局统计累计(由模式控制器的 player_eliminated 信号驱动)
func _on_eliminated(victim, killer, head: bool) -> void:
	var kk: String = _actor_name(killer)
	var vk: String = _actor_name(victim)
	if kk != "" and kk != "战场":
		var ke: Dictionary = player_stats.get(kk, { "kills": 0, "deaths": 0, "assists": 0 })
		ke["kills"] = int(ke.get("kills", 0)) + 1
		player_stats[kk] = ke
	if vk != "" and vk != "战场":
		var ve: Dictionary = player_stats.get(vk, { "kills": 0, "deaths": 0, "assists": 0 })
		ve["deaths"] = int(ve.get("deaths", 0)) + 1
		player_stats[vk] = ve
	player_eliminated.emit(victim, killer, head)


## actor → 展示名(统一实现 Bot.display_name:玩家"你"/bot 优先 bot_name/name;其余返回空)
func _actor_name(a) -> String:
	return Bot.display_name(a)


## 本局玩家总数(在场 AI + 玩家),供 round_started 广播
func _player_count() -> int:
	if G.bots != null:
		return G.bots.size() + 1
	return 0
