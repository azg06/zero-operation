class_name GameMode_Portal extends Node
## 游戏模式基类(门户模式架构契约)
## 说明:此文件由 BR Agent 在 PortalManager 就绪前创建的最小骨架,现按
## PortalManager(game_mode_portal.gd 的消费方)与 UI Agent(src/ui/hud.gd)契约对齐。
## 架构 Agent 可就地扩展,但不得破坏下列成员(GameMode_BR 依赖它们)。
## 信号契约(PortalManager.start_mode 连接):
##   score_changed(us_score, ru_score) / player_eliminated(victim, killer, head) /
##   mvp_changed(mvp: Dictionary) / round_ended(result: Dictionary)
## 方法契约(game.gd 接线):
##   on_player_killed(killer, victim, head) / on_damage(attacker, victim, amount)
## UI 只读字段(hud.gd _update_portal_hud 读取):
##   br_alive / br_total / zone_center(Vector3) / zone_radius(float)

# 信号为 PortalManager/UI 的接口契约,由子类(TDM/BR)emit;基类自身不 emit。
@warning_ignore("unused_signal")
signal score_changed(us_score: int, ru_score: int)
@warning_ignore("unused_signal")
signal player_eliminated(victim, killer, head: bool)
@warning_ignore("unused_signal")
signal mvp_changed(mvp: Dictionary)
@warning_ignore("unused_signal")
signal round_started(mode: String, map_id: String, player_count: int)
@warning_ignore("unused_signal")
signal round_ended(result: Dictionary)
@warning_ignore("unused_signal")
signal portal_hint(text: String)

var mode_name := "portal"
var round_time := 0.0
var time_limit := 0.0
var started := false

# ---- 门户 HUD 只读字段(UI Agent 读取) ----
var br_alive := 0
var br_total := 100
var zone_center := Vector3.ZERO
var zone_radius := 0.0


func start(_map_id: String = "") -> void:
	pass


func tick(_dt: float) -> void:
	pass


## 击杀注册(架构 Agent 接线到 game.gd on_kill → G.portal.active)
func on_player_killed(_killer, _victim, _head := false) -> void:
	pass


## 伤害登记(架构 Agent 接线到 game.gd _portal_damage,供助攻/统计)
func on_damage(_attacker, _victim, _amount: float) -> void:
	pass


func end() -> void:
	pass
