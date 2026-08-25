# StarCatch 启动与星历账本设计 QA

- source visual truth: `Documentation/DesignReferences/starcatch-ephemeris-ledger-reference.png`
- implementation screenshots: `/tmp/starcatch-boot-ready.png`, `/tmp/starcatch-archive-final.png`
- device / viewport: iPhone 17 Pro Simulator, iOS 26.3.1, 402 × 874 pt
- source pixels: 1536 × 1024（同一设计板上的两个纵向状态）
- implementation pixels: 1206 × 2622 each（3×，对应 402 × 874 pt）
- normalization: 按各自纵向内容区域比较构图与层级；设计板不是同一设备比例，因此不对外围留白做逐像素判断
- state: 简体中文；启动准备全部完成；HST 深度档案默认“此刻”页，24 小时预测完成

## Full-view comparison evidence

- 启动页与参考图均以固定 `STARCATCH`、三行模块账本和静止星场为唯一主体。正式实现使用真实的目录、轨道解算和观测模型状态，没有圆环、移动准星、扫光或循环。
- 档案页保持参考图的身份主视觉、三段下划线导航、24 小时时间带、三项关键指标和单次过境曲线。实现额外保留统一 App 顶部导航及“此刻的天空”实时读数，属于产品导航与事实连续性的有意差异。

## Focused region comparison evidence

- 品牌与模块区：检查了字距、字形锐度、状态列右对齐、分隔线和中文基线；完成态没有模糊光晕或移动信号点。
- 24 小时过境区：检查了标题、范围图例、窗口片段、00H–24H 刻度、升起/最高点/落下顺序、方位和卡片边界；所有图形由真实预测值生成。
- 字体：中文信息使用系统字体，编号、时间、AZ/EL 和单位使用等宽角色；未出现承担语义的中英双标题。
- 颜色：暖灰、暖白和身份色沿用既有 Palette；功能信息保持可读，装饰线继续低对比。
- 图像质量：生成图仅作为参考；运行时全部为 SwiftUI、Canvas 和 SF Symbols，没有低清位图、占位图或伪造轨道图片。
- 文案：使用“地平线上方过境”，未承诺肉眼可见；近静止及无过境状态不会显示装饰性椭圆。

## Comparison history

### Iteration 1

- [P2] 中文“未来 24 小时 · 地平线上方过境”被通用章节标题强制换成两行，破坏参考图的水平时间账本层级。
- Fix: 将标题收敛为“未来 24 小时”，把“地平线上方过境”改为右侧带短线的范围图例。
- Post-fix evidence: `/tmp/starcatch-archive-final.png` 中标题与图例位于同一基线，时间带完整上移，未再出现非预期换行。

### Iteration 2

- 未发现可执行的 P0/P1/P2 差异。参考图中的静态示例数字已由真实 HST 本机预测替换，属于必要的数据真实性差异。

## Findings

- 无剩余 P0/P1/P2。
- P3: 真机最大动态字体下，右侧“地平线上方过境”图例可能需要退化为较短文案；当前默认字号和 iPhone 17 Pro 未截断。

## Implementation checklist

- [x] 一次性锐利字形注册
- [x] 三个真实准备节点
- [x] 稳定等待与单次交接
- [x] “此刻 / 任务 / 数据”下划线导航
- [x] 可选择的未来 24 小时过境窗口
- [x] GEO / 无过境明确状态
- [x] 删除所有用户可见的“轨道指纹”和静态椭圆补位
- [x] 中英文 String Catalog 文案

final result: passed
