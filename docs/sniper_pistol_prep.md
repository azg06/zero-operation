# 狙击枪 / 手枪批次建模准备(重点:狙击镜内放大)

> 状态:准备稿。LMG 8 把已完成并验证(ADS 0 遮挡,换弹 16/16)。
> 本文档是开工前的契约盘点,建模时照此执行,缺一项开镜/换弹就废。

## 一、狙击枪批次(8 把):awm / m24 / svd / m40 / m82a1 / l115 / sv98 / m2010

### 1.1 镜内放大(PIP)系统的完整契约链 —— 为什么狙击枪是特殊批次

`optic_scope.gd` 的 PIP 渲染不依赖动画,依赖**一串命名节点 + meta**:

| 契约 | 作用 | 缺失后果 |
|---|---|---|
| `StockOptic` 组 | 原厂镜整体,装备光学镜时整组隐藏 | 红点镜与狙击镜同屏穿模 |
| `ScopeEye`(**StockOptic 的子节点**) | PIP 相机挂点,meta `scope_eye` | `scope_sight()` 返回 false,**开镜无放大画面** |
| `scope_eye_radius` meta | 镜内圆窗半径(原厂镜 0.028) | PIP 圆窗尺寸错 |
| `ScopeTubeBody` | 镜筒实体(非 ADS 挡视线) | meta `scope_tube` |
| `ScopeLensBlack` | 非 ADS 黑玻璃(实心,挡视线) | ADS 切换失效 |
| `ScopeLensClear` | ADS 高透玻璃(初始隐藏,运行时切显隐) | 同上 |
| `RetCross` 分划 | 开镜十字(初始隐藏,材质 ret_dark) | 镜内无分划 |

关键认识:**镜筒不需要真通透** —— ADS 时 2D 镜罩接管屏幕、ScopeEye 处的独立相机渲染镜内放大画面,镜筒只是外壳。这大幅简化建模(不用开布尔挖空)。

### 1.2 Blender 侧建模要求

1. `StockOptic`:镜筒(后粗前细实体)+ 前后支架 + 物镜圈 + 顶部调节钮,join 为单对象,
   命名 `StockOptic`。参考尺寸(awm):镜筒 r 0.024→0.030 / 长 0.22,镜轴 y=0.09 上下按枪定。
2. `ScopeEye`:**独立对象,parent 到 StockOptic**,位置在目镜后端(约 z=+0.06 相对镜体)。
   Godot 的 PIP 相机每帧取它的世界变换。
3. `ScopeLensBlack` / `ScopeLensClear`:两个薄圆盘(r=目镜半径 0.028,厚 0.012),
   同位置 z 微偏 ±0.5mm,Black 在前 Clear 在后。材质 `scope_black` / `lens_clear`。
4. `RetCross`:十字分划(两根细扁条 0.032×0.0008×0.0006 + 中心点),材质 `ret_dark`
   (unshaded 纯黑,明亮天空前也可见)。parent 到 ScopeEye。
5. 层级:GLB 必须保留 StockOptic → ScopeEye → (Lens/Ret) 的父子链
   —— Godot 侧 `_hoist_to_root("StockOptic")` 提升整组,ScopeEye 跟着进场景树,
   `scope_sight()` 的 `is_inside_tree()` 才为 true。
6. 每把枪的镜轴高度不同(awm 0.09 / svd 0.095 / m82a1 0.105 左右),以各自 sight_y
   与枪身顶部反推;**ScopeEye 的 z 必须在目镜后缘**,PIP 视线才与镜轴重合。

### 1.3 Godot 侧待办(建模完成后)

`_build_from_glb` 扩展狙击镜绑定(名字 → meta 全部自动):

```
scope_eye → ScopeEye 节点 + scope_eye_radius=0.028
scope_tube → StockOptic(或其镜筒子件)
scope_lens_black / scope_lens_clear / scope_reticle → 同名节点
```

建议做成"名字→meta"通用映射表,一次覆盖现有 + 未来所有特殊件。

### 1.4 狙击枪本体建模要点(8 把)

- 通用:枪机(bolt)独立 —— 空仓换弹是 `bolt_cycle`(Gun.bolt_t 驱动完整拉栓循环),
  **bolt 必须是沿 Z 可滑动的枪机总成**(旧程序化版是 bolt_a/bolt_b 两段),
  建议整体 join 为一个 "bolt" 对象。
- m24/m40/sks 无弹匣更换(mag style "none"),建模无弹匣件;awm/l115/sv98/m2010 有弹匣。
- m82a1:大口径,弹匣井在握把前方、提把顶轨、双侧大制退器 —— 结构最特殊,单独花时间。
- svd:长行程导气活塞外露 + 骨架托 —— 与西方狙完全不同的轮廓。
- 两脚架(m24/m40 可收折)、贴腮板、托底板可调段,能做多少做多少,优先保镜座精度。

## 二、手枪批次(8 把):m1911 / g17 / p226 / deagle / m93r + 左轮 python / sw686 / sw500

### 2.1 半自动(5 把)契约
- `slide`(套筒):**独立可动件**,空仓换弹是 `slide` 风格(套筒后拉释放)。
  手枪 ADS 时套筒在视线下方,slide 滑动行程 20~25mm。
- `mag`:握把内弹匣,换弹向下抽出 —— 弹匣底板要明显(换弹时它是最显眼的运动件)。
- 无枪托/导轨;optic 锚点 y≈0.068~0.082(微型红点,镜座需建模)。
- 建模重点:套筒与下机匣的**分模线**必须清晰(套筒是独立件,缝隙就是它的存在感);
  握把纹理(防滑棱)、扳机护圈、击锤(m1911/deagle 外露锤)。

### 2.2 左轮(3 把)契约 —— 有专用换弹系统(_SIG_SKIP,不走通用流程)
- `crane`(弹巢摆臂):甩巢动作绕它旋转。
- `cylinder`(弹巢):6/5 膛,运行时逐膛旋转 —— **独立对象**。
- `hammer`(击锤):击发后回落动画。
- `chamber_shells`:**每膛一个弹壳节点**,命名 `ChamberShell0..N`,parent 到 cylinder,
  Godot 侧收集成数组按膛位显隐(装几发显示几个)。
- 建模重点:弹巢正面 6 个膛口要真实开孔(布尔)、排壳杆、照门/V 型缺口照门。

## 三、执行顺序建议
1. 先写狙击镜 Godot 绑定扩展(名字→meta 映射表,半小时)
2. 建 1 把 awm 标杆 → 开镜验证 PIP → 批量其余 7 把
3. 手枪 5 把半自动(结构相近)→ 左轮 3 把(结构特殊,最后)
4. 每批过 ADS + reload_sim 回归
