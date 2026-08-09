# StarCatch 卫星资料库

这里是 StarCatch 的逐星文字资料源，可以直接作为 Obsidian Vault 打开。

当前状态：

- 3,832 颗保留卫星，每颗都有独立 Markdown 文件。
- 12,411 个高重复通信星座节点不复制项目历史，而是以 `Families/` 下的 8 份项目档案为背景，再叠加当前节点独有的 COSPAR、NORAD、轨道摘要与发射标记，清单见 `EXCLUDED_CONSTELLATIONS.md`。
- 轨道位置、速度、距离和过境时间仍由 `StarCatch/Resources/catalog.json` 计算，不需要在笔记中维护。

## 修改一颗卫星

1. 打开 `INDEX.md`，使用 Obsidian 搜索卫星名称或 NORAD 编号。
2. 点击链接进入 `Profiles` 下的对应文件。
3. 修改 `摘要`、`正文`、`时间线`、`事实`或`来源`。
4. 保存，然后直接从 Xcode 构建。

构建会自动完成：

```text
3,832 份 Markdown
        ↓ 校验覆盖、格式和 NORAD 唯一性
satellite_profiles.json
        ↓
APP 一次解码并按 NORAD 建立索引
```

不需要手动执行同步，也不需要给新文件设置 Target Membership。

## 修改一个大型星座

Starlink、OneWeb、千帆、国网、Project Kuiper、Iridium、Globalstar 和 Orbcomm
采用项目级背景档案。打开 `Families/` 中对应的 Markdown 修改一次，主天空里属于
该星座的任意节点都会继承项目背景；运行时仍生成以当前卫星为标题的独立“深入档案”：

```text
Families/
├── starlink.md
├── oneweb.md
├── qianfan.md
├── hulianwang.md
├── kuiper.md
├── iridium.md
├── globalstar.md
└── orbcomm.md
```

共享只发生在历史与项目说明层。每个节点的摘要、标题、NORAD、COSPAR、发射标记、
位置、距离和速度都保持独立。

## 文件位置

文件按 NORAD 每一万号分卷：

```text
Profiles/
├── N00000-N09999/
├── N10000-N19999/
├── N20000-N29999/
├── N30000-N39999/
├── N40000-N49999/
├── N50000-N59999/
├── N60000-N69999/
└── N100000-N109999/
```

文件名同时包含 NORAD 和目录名称，例如：

```text
Profiles/N20000-N29999/NORAD-20580-HST.md
```

## 可以修改的字段

- `eyebrow`：深入档案顶部的短英文标签。
- `organization`：公开可核实的运营方或合作机构。
- `program`：任务、计划或卫星系列名称。
- `摘要`：主天空信息面板首先显示的一句话，建议 40～90 个汉字。
- `正文`：可以添加任意数量的 `### 小标题` 和段落。
- `时间线`：每行采用 `时间 | 事件`。
- `事实`：每行采用 `字段 | 内容`。
- `来源`：每行一个来源，优先使用运营机构或公共航天机构资料。

不要修改 `norad`。它是 Markdown 与真实轨道对象之间的唯一关联键。五个 `##` 二级标题也应保留原名。

`review_status: generated` 表示目前是从本地目录生成的基础档案；人工核实后可以改成 `reviewed`，这个字段用于编辑管理，不改变 APP 功能。

## 查找命令

如果不想通过索引查找：

```sh
python3 Scripts/satellite_knowledge.py locate "GOES 17"
python3 Scripts/satellite_knowledge.py locate 43226
```

命令会直接返回对应文件路径。对于已排除星座，会明确显示排除原因。

## 目录更新后的维护

只有在重新下载并生成 `catalog.json` 后，才需要运行：

```sh
python3 Scripts/satellite_knowledge.py sync
```

它会为新增对象建档、更新 `catalog.json` 中的逐星首层摘要，并重建
`review_status: generated` 的自动档案。已经改为 `reviewed`、`migrated` 或其他人工状态的
内容不会被覆盖。自动文案只使用可核实的任务名称与本地 OMM 轨道事实，不猜测未知载荷或运营方。
随后可以手动检查：

```sh
python3 Scripts/satellite_knowledge.py validate
```

通常无需执行 `compile`；Xcode 每次构建都会自动运行。
