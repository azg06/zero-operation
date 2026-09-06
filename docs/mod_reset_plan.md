# 改装件系统重置方案(准备稿)

> 状态:准备中,未动手。等 16 把枪 + 手模的实机验证反馈收齐后再开工。

## 一、现状盘点

- **数据层** `src/data/weapon_mods_data.gd`:8 个槽位(muzzle/barrel/stock/mag/grip/trigger/optic/laser),load_cfg 读档 + total_effects 聚合属性。数据层不依赖模型,重置不动它。
- **建模层** `weapon_models.gd build_mod_*(8 个函数)`:全部还是旧图元风格 —— 直角 box + 简单 cyl,和旧枪模一个年代的产品。
- **锚点层** `MOD_ANCHORS`(26 把枪):旧程序化模型时代手工定的坐标。
- **挂载** `_apply_mods` 按 MOD_ANCHORS[id][slot] 摆放,标准件(opt_std 等)不挂载。

## 二、问题清单(为什么必须重置)

1. **锚点与新 GLB 模型的偏差**
   - 新模型由 Blender 按旧尺寸重建,整体轮廓一致,但细节尺寸变了(如 M4 上机匣顶从 0.062→0.063、护木半径、消焰器延伸到 -0.80)。
   - 已知高危锚点:`grip`(前握把要贴新护木下缘,旧锚点按旧护木算,偏移 2~5mm 就悬空/穿模)、`laser`(贴导轨侧,侧轨现在转向了)、`stock`(贴机匣尾)。
   - `optic` 锚点 y=齿顶高度(0.086 等)与新导轨对齐 ✓,但镜座高度是旧镜的 —— 新镜建模改了就要跟着调。
2. **无导轨枪没有 optic 挂点**
   - MP5/PP-19/G3/AK 系/微型枪(ump/mp7/vector)没有皮卡汀尼轨, optic 锚点是悬空硬指定。
   - 实机方案:MP5 用 claw 侧镜座、AK/PP-19 用侧镜导轨、G3 用照门座延伸轨 —— 需要在枪模上加这些**镜座结构**(建模侧补), optic 才有落点。
3. **配件建模风格落后一整代**
   - 枪模已升级到"倒角 + 布尔 + 真齿距导轨",配件还是直角积木。红点/全息/垂直握把/枪口制退器的观感落差会很刺眼。
   - 计划:配件全部用 WeaponParts 零件库重写(bevel_box/chamfer_cyl/picatinny/knurl),复杂光学件(红点/全息/2 倍镜)考虑 Blender 建模导出。
4. **贴图**:配件目前共用金属_plate 贴图,复用 gun_* 六套贴图即可,无需新增;重点是 roughness/metallic 的区分(镜片 lens_clear、聚合物 poly、阳极铝 metal)。

## 三、重置方案(三步)

### 第 1 步:锚点校准工具(先做,一切的前提)
- 写 `tools/probe_mods_fit.gd`:对 16 把 GLB 枪 × 全部配件,自动检测:
  - 配件 AABB 与枪身静态件的穿透体积(穿模量化)
  - 配件与枪身的最小间隙(悬空量化)
  - muzzle/optic 与枪口点/视轴的一致性
- 输出每把枪每槽位的偏差报告 → 按数据改 MOD_ANCHORS,不靠肉眼。
- 验收标准:所有挂载间隙 ∈ [0, 2mm],无穿透。

### 第 2 步:枪模补镜座结构
- MP5 claw 镜座 / AK·PP-19 侧轨座 / G3 照门座轨 / UMP·MP7·Vector 顶轨延长或短轨。
- 在 build_*.py 建模脚本里加,重导出即可(不改锚点数据结构)。

### 第 3 步:配件建模升级
- 用 WeaponParts 重写 8 个 build_mod_*:
  - muzzle:鸟笼/三叉/斜切制退/消音(圆锥+多孔) —— birdcage_mesh 现成
  - grip:垂直/斜角(倒角盒 + 防滑棱,add_grip 现成)
  - optic:红点(镜筒 cyl_open + 内红点 sprite)、全息(方框窗)、2 倍镜(镜筒+分划) —— 镜片材质 lens/lens_clear 现成
  - laser:小盒 + 发射窗(red_glow/green_glow 现成)
  - stock/mag/trigger:倒角盒套件
- 每个配件过 probe_mods_fit 校准。

## 四、工期预估(相对)
- 第 1 步:1 个工具 + 16×8 次跑批,最轻。
- 第 2 步:6 把枪的建模补丁,中。
- 第 3 步:8 类配件重写,最重 —— 红点/全息的光学结构值得花时间。

## 五、明确不做
- 不动 weapon_mods_data.gd 数据结构(属性/经济系统稳定)。
- 不动 _MOD_ALIAS / _STD_IDS 兼容层。
