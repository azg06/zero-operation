# 第一人称玩家身体视角规范 v1.0

> 适用范围：《零度行动》玩家第一人称视角（相机 / 身体 / 头部对齐 / 姿态）。
> 定稿依据：2026-09-11 实测修正 + Blender 逐帧几何量化。本文档与代码同步维护，
> 修改任一条参数前先读「§7 禁止项」，任何一条被打破都会直接导致用户可见的断面/穿模。

---

## 1. 设计目标

参考主流大型军事 FPS（Battlefield / Call of Duty / Escape from Tarkov）的第一人称表现：

- 相机**严格位于玩家角色双眼之间**，高度等于真实站姿眼高。
- 相机在头部正前方 —— **不在胸腔内、不在身体后方**。
- 身体从镜头位置**自然向下连续延伸**，低头能看到真实的胸、腹、腰、腿、靴。
- 身体与相机**共享同一套人体骨骼与空间坐标系**，不允许两套独立变换。
- 各姿态（站/走/跑/冲刺/蹲/趴/跳/换弹/攀爬）保持合理空间关系。
- 镜头有轻微真实的人体运动感，但不过度晃动。

**核心原则：能看见身体 ≠ 相机留在体内。** 相机必须物理地位于身体外部，靠"抬高眼位 +
拉开净空"实现，而不是把相机塞进胸腔再把胸口裁掉。

---

## 2. 铁律（Hard Rules）

| # | 规则 | 违反后果 |
|---|---|---|
| R1 | 站立眼高 **1.70 m**，与 GLB 模型真实眼位一致 | 相机贴进胸腔，`near` 把胸口整片裁掉 ⇒ 低头看不到胸 |
| R2 | 站立/走/跑/蹲 的 `back_off` **必须为 0** | 身体整体落到相机背后 ⇒ 低头连腿都看不到 |
| R3 | **严禁把 Chest 骨缩到 1 cm** 来"躲镜头" | 胸口彻底消失，用户已明确否决 |
| R4 | 相机位置只由 `pos + (0, eye_height, 0)` 决定，不允许额外水平偏移（趴姿除外） | 破坏"相机在双眼之间" |
| R5 | 躯干让位只能走 **抖动溶解**，不允许硬切 / 改网格 / 改骨骼 | 出现胸腔横截面、从断面看进体内 |

---

## 3. 坐标系与人体比例

Godot 坐标系，Y 向上，单位米，**原点在角色脚底**。身体朝向 `body.rotation.y = yaw`，
`rotation.x` 恒为 0（身体不随视线俯仰，只有 `AimPitch` 骨带手臂与枪）。

| 部位 | 高度 (m) | 来源 |
|---|---|---|
| 地面 / 靴底 | 0.00 | — |
| 靴顶 | 0.10 | 士兵 GLB |
| 膝 | 0.48 | 士兵 GLB |
| 胯 / 髋 | 0.95 | 士兵 GLB（`HIP`） |
| 腰 | 1.10 | 士兵 GLB |
| **胸顶（下压后）** | **1.445** | 1.595 − `FP_CHEST_DROP` |
| 肩 | 1.45 | 士兵 GLB |
| **站立眼位（相机）** | **1.70** | `player.gd::eye_height` |
| 头顶 | ~1.80 | 士兵 GLB |

### 3.1 相机与身体的对齐关系

```gdscript
# player.gd
var cam_base := Vector3(pos.x, pos.y + eye_height, pos.z)   # 相机 = 角色原点 + 眼高
cam.global_position = cam_base + cam.global_transform.basis * motion_pos

body.position = pos                                          # 身体 = 同一角色原点
body.rotation.y = yaw
body.rotation.x = 0
```

两者共用同一个 `pos` ⇒ **同一空间坐标系、同一 GLB 骨架**，不存在"相机骨骼"与
"身体骨骼"两套系统。相机水平偏移 0（站立系），因此永远位于身体轴的正上方。

### 3.2 各姿态眼高

| 姿态 | `eye_height` 目标 | 阻尼 | 说明 |
|---|---|---|---|
| 站立 / 走 / 跑 / 冲刺 | 1.70 | 12 | 基准 |
| 蹲伏 / 蹲走 | 1.12 | 12 | |
| 滑铲 | 0.72 | 22（进）/ 12（出） | 快速压入、利落回正 |
| 趴下 | 0.45 | 12 | 配合 `back_off 0.6` 让铺平的头回到眼位下方 |

---

## 4. 全身连续性 — 三机制

这三条是"看不到断面 / 不穿模"的全部来源，缺一条就会复现历史 bug。

### M1 · 眼位对齐真实眼高

士兵 GLB 的背心顶面 1.595 m、冲刺前倾最高 ~1.62 m。若眼高沿用旧的 **1.62**，
相机与胸口几乎等高 ⇒ 相机等于贴在胸腔里，主相机 `near = 0.08` 会把胸口整片裁掉。

→ 眼高改为 **1.70**（模型真实眼位，头骨 1.64–1.80），净空约 8 cm。

### M2 · 胸腔下压 `FP_CHEST_DROP = 0.15`

`player.gd` 每帧把 `Chest` 骨的 pose position 下移 0.15 m（写绝对值，不累积；
GLB 动画的 location 轨道相对 rest 为零位移，因此等价于"整段下移"）。

- 眼—胸间距从 ~10 cm 提升到 **~25 cm**（真人 ≈30 cm）。
- Blender 逐帧量化：全兵种 × 全动画 × 全俯角，**最小视深 ≥ 0.143 m > near 0.08**
  ⇒ 相机平面不再切开胸口。

### M3 · 低头到底时躯干抖动溶解 `fp_yield`

几何上无解：眼离胸顶仅 25 cm，胸口只要可见就必然把脚挡死。
（视线越过胸顶前缘落到地面的距离 = 1.65 × 胸前面 / 眼到胸顶高；"要露脚"需
f/h ≤ 0.126，"低头 35° 还看得到胸"需 f/h ≥ 0.31 —— 两者不可兼得。）

→ 俯角超过 60° 起，`soldier_palette.gdshader::fp_yield` 对躯干段
（模型空间高度 **0.92 – 1.55 m**）做**屏幕有序抖动溶解**：

```glsl
if (fp_yield > 0.002 && v_fp_h > 0.92 && v_fp_h < 1.55) {
    float thr = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
    if (thr < fp_yield) discard;
}
```

驱动值：`fp_yield = smoothstep(1.05, 1.36, abs(pitch))`，即 **60° 起渐入、78° 全开**。

约束：
- 只删"视图"，**网格 / 骨骼 / 影子一律不动**（地面影子始终是完整人形）。
- 整段一起溶解 ⇒ 不产生"被横切一刀、从断面看进胸腔"的硬边。
- 60° 以内胸口完全正常，不影响正常低头看胸。
- 该 uniform 默认 0，NPC 不受影响；玩家身体使用**独立材质副本**（`fp_mat`），
  否则写 uniform 会让所有 NPC 一起让位。

---

## 5. 姿态 → 动画映射

```gdscript
if _prone_amt > 0.5:                      # 趴
    h_speed > 0.4  → ProneCrawl   speed_scale = clamp(h/1.3, 0.6, 1.4)
    else           → Prone
elif crouched or slide_t > 0:             # 蹲 / 滑铲
    h_speed > 0.6  → CrouchWalk   speed_scale = clamp(h/2.8, 0.6, 1.3)
    else           → Crouch
elif h_speed > 4.4 → Run              speed_scale = clamp(h/5.8, 0.7, 1.5)
elif h_speed > 0.6 → Walk             speed_scale = clamp(h/4.2, 0.5, 1.5)
else               → Idle
```

切换用 `panim.play(want, 0.25)` 淡入，`_prone_amt` 以阻尼 8 插值避免瞬切。

`AimPitch` 骨跟随视线俯仰：`clampf(pitch, -0.6, 0.6)` —— 只带手臂与枪，
身体朝向不受影响。

| 需求中的姿态 | 覆盖情况 |
|---|---|
| 站立 | ✅ Idle |
| 奔跑 | ✅ Run |
| 冲刺 | ✅ Sprint |
| 蹲伏 | ✅ Crouch / CrouchWalk |
| 趴下 | ✅ Prone / ProneCrawl |
| 换弹 | ✅ 手臂层（`fp_arms` + `weapon_reload_controller`），身体保持当前姿态 |
| 跳跃 | ⚠️ 镜头层有 `jump` / `landing` 冲量；**身体骨骼无专属腾空姿态**，沿用 Run/Walk |
| 攀爬 / 翻越 | ❌ 项目内**不存在** vault / climb 系统 |

---

## 6. 镜头运动层（FirstPersonMotionSystem）

`src/player/fp_motion.gd`，单层控制器，每帧只 update 一次。11 套状态预设：

`idle / walk / run / sprint / crouch / crouch_walk / aim / aim_walk / aim_sprint / jump / landing`

合成链：

```
速度 + 加速度 + 鼠标增量 + 玩家状态 + 武器重量
  → 状态参数插值
  → 呼吸层 / Bob 层 / Sway 层 / Inertia 层 / 落地-跳跃冲量层
  → Spring / Damping
  → Camera 偏移 + Weapon 偏移 + 手部 IK 偏移
```

设计约束（避免"过度晃动"）：

- Bob 不用 `sin(t) * amp` 作为唯一晃动源，而是**步距积分相位 + 多谐波叠加**。
- Camera 与 Weapon 使用**不同频率 / 幅度 / 相位**，武器额外经过低刚度弹簧，天然滞后。
- 转向 Sway 使用**带饱和的非线性鼠标速度**，慢速自动趋近 0。
- 急停 / 换向通过"加速度目标 + 欠阻尼弹簧"产生前冲→回弹的惯性。
- 全系统零每帧对象分配，弹簧预创建。

镜头最终姿态在 `player.gd` 合成：位置 = 眼位 + `basis × motion_pos`；
旋转 = 基础 yaw/pitch + 后坐 + 换弹 + 检视 + 压制抖动 + `motion_rot`。

---

## 7. 禁止项 → 技术对策

| 禁止项 | 对策 |
|---|---|
| 胸腔横截面 / 身体模型断面 | M3 抖动溶解（非硬切） |
| 悬浮的身体部件 | 单一连续 GLB 骨架，`body.position = pos` |
| 摄像机位于胸口后方 | R2：站立 `back_off = 0` |
| 身体模型穿过摄像机 | M2：`FP_CHEST_DROP 0.15` ⇒ 最小视深 ≥ 0.143 m > near 0.08 |
| 从胸腔内部向外观察 | M1：眼高 1.70 对齐模型真实眼位 |
| 胸口被切断 / 看不到胸口 | M1 + M2 + M3 三机制共同保证 |
| 头 / 脖挡住视线 | 头、颈、双臂骨骼 pose scale → 0.01（收进躯干），影子由 `ShadowHead` 代理补 |
| 第一人称出现四条手臂 | 身体骨骼双臂隐藏，手臂只由 `fp_arms.glb` 分段刚性渲染 |

---

## 8. 验收方法

### 8.1 自动化 QA

```sh
Godot_v4.7.1-stable_win64_console.exe --path <项目根> \
  --test-play conquest city --test-pbody
```

输出到 `E:/工作目录2/models_probe/`：

| 文件 | 内容 |
|---|---|
| `pbody_chest_soft.png` | 轻低头帧（pitch −0.30） |
| `pbody_full_<level\|soft\|mid\|deep\|vdeep\|full>.png` | 6 档俯角全景 |
| `pbody_bodyonly_<档>.png` | **仅身体剪影**（`cull_mask = 1<<1` + 关视角模型） |
| `pbody_st_<姿态>_<half\|deep\|full>.png` | 7 姿态 × 3 俯角 |
| `pbody_stnv_*` / `pbody_stb_*` | 全景无视角模型 / 品红剪影（洞检测用） |

同时打印 `[PBODY-DIAG]`：眼高、骨骼世界位、网格 `layers` / `visible` / `cast_shadow`。

### 8.2 判定标准

1. **剪影帧内不得出现"洞"或横切边** —— 出现即说明被 `near` 裁切。
2. 全姿态 × 全俯角，地面影子必须保持完整人形轮廓。
3. 低头到底帧必须能分辨大腿、膝、靴。
4. 站立帧看不到任何胸腔内部结构。

> 剪影帧用**无光照纯品红 `material_override`** 渲染，不受阴影 / 环境光干扰；
> 判"身体在不在画面里"时以剪影为准，全景帧用于排除"被武器挡住"的干扰项。

### 8.3 Blender 侧几何量化

`tools/blender/` 下脚本对 GLB 逐帧采样，输出眼—胸净空与最小视深，
新参数必须先过这一关再改游戏代码。

---

## 9. 已知缺口（待补）

1. **跳跃腾空姿态**：镜头层已有 `jump` / `landing` 冲量，但身体骨骼在腾空时仍播
   Run/Walk 动画，缺少收腿 + 落地缓冲的腾空姿态。
2. **攀爬 / 翻越**：项目内完全没有 vault / mantle / climb 系统，需求中的"攀爬"
   目前无对应实现。
3. **腰射枪位偏低**：腰射时枪械偏低，双手贴近画面底边，需调整 FOV 或重做枪位。

---

## 10. 附录 — 交给 AI Agent 的工程级 Prompt

```text
任务：在 Godot 4 项目中实现 / 校验标准第一人称玩家身体视角。

先做：读完 src/player/player.gd 的相机与 body 同步段、src/models/soldier_model.gd 的
build_player_body / FP_CHEST_DROP、src/shaders/soldier_palette.gdshader 的 fp_yield、
src/player/fp_motion.gd，再动手。不要在不了解现有实现的情况下重写系统。

硬约束（任一条不满足即视为失败）：
- FIRST-PERSON CAMERA = EYE LEVEL。站立眼高必须等于角色模型真实站姿眼位，
  禁止沿用"胸口高度"当眼高。
- CAMERA POSITION = BETWEEN THE EYES。相机只能由 角色原点 + (0, eye_height, 0) 得到，
  水平偏移为 0（趴姿除外）。
- FULL BODY CONTINUITY。身体与相机必须共享同一套骨骼与同一空间坐标原点。
- NO TORSO CROSS-SECTION / NO CUTAWAY BODY。不允许出现胸腔横截面或被相机裁掉的断面。
- NO CAMERA INSIDE CHEST。相机必须物理位于身体外部。
- NO BODY CLIPPING。相机近平面不得切开任何身体部件。
- REALISTIC HUMAN PROPORTIONS。头/颈/肩/胸/腰/腿的比例关系符合真实人体。
- VISIBLE LOWER BODY。低头时能依次看到胸、腹、腰、腿、靴。

实现要求：
1. 相机位置 = 角色原点 + 眼高；身体位置 = 同一角色原点，两者不得有水平偏移。
2. 眼位必须对齐模型真实眼位（若模型胸口顶面与眼位距离 < 15cm，必须抬高眼位或
   在骨骼层拉开眼胸净空）。
3. 若近平面仍会裁切胸口，通过骨骼 pose position 整体下压胸段来增加净空，
   禁止把 Chest 骨缩放掉。
4. 低头到底时若胸口几何上必然遮挡双脚，使用片元 discard 的屏幕有序抖动溶解
   让躯干让位；禁止硬切、禁止改网格、禁止改骨骼、禁止影响阴影。
5. 让位 uniform 只能作用于玩家身体的独立材质副本，不得影响 NPC。
6. 姿态需覆盖 站立/走/跑/冲刺/蹲/蹲走/滑步/趴/匍匐，按水平速度与姿态状态切换，
   使用 0.2–0.3s 淡入，速度驱动 speed_scale。
7. 镜头运动分 呼吸/Bob/Sway/惯性/落地冲量 五层，Camera 与 Weapon 使用不同
   频率与相位，Sway 使用带饱和的非线性鼠标速度；禁止单一 sin 晃动源。

禁止出现：
- 相机在胸口后方 / 相机在胸腔内 / 身体穿过相机
- 胸腔横截面、身体模型断面、悬浮的身体部件
- 低头时胸口整片消失，或看到胸腔内壁
- 第一人称出现四条手臂或两个头

验收：
运行 --test-play <模式> <地图> --test-pbody，检查 models_probe/ 下
剪影帧内无洞、无横切边；全姿态地面影子为完整人形；低头到底帧可分辨大腿/膝/靴。
先给出核验结果与差距清单，再实施修改。
```
