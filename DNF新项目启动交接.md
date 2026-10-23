# DNF 单机复刻：新项目启动交接

> 最新交付（2026-10-23）：已推进至 **R4/10 后段历史通关保存**；本次 45 项隔离存储、22 项章节现场、14 项莎兰与 20 项换装检查全部通过，共 101 项。schema6 保留严格旧档迁移，真实通关在旧事务失败期间按 R 也不会丢失本次会话凭据；重试先完成原事务，再单独保存新章标，无新增金币或物品。人偶师历史记录保持雕像通道开放，莎兰新增人偶师／雕像两分支。各套测试前后正式档字节一致，最终启动加载已有正式档且 0 次写入。当前进展、运行方法、已知边界及下一步集中在 `docs/当前进展.md`；最终证据见 `docs/r4_10_delivery_check.json`。道格里仅完成来源研究，尚未接入，本次先整理提交并推送。以下各阶段文字保留历史语境。

> 接手进展（2026-10-23）：用户已选择男鬼剑士，认可港口方向，并授权在合适进度推进内容。当前已有 R0 原图基准、R1/29 港口、R2/01 港口—石道—塔门厅往返路线、R3/05 普通巨剑换装／实体路线／首战委托／40 金币一次性奖励／龙人之眼掉落和行囊／本地存档，以及 R4/01 塔内深廊与鲁卡斯首领（118 项功能检查通过），R4/02 鬼斩／6秒跨区冷却（82项功能检查通过），R4/03 莎兰交谈／港口休息（35项检查通过），R4/04 萝莉安补给／HP 药剂／schema5（87项检查通过），R4/05 按住 C 实战格挡（81项检查通过），R4/06 深廊后续的人偶前廊／岩石人偶师近战与后撤（69项检查通过），R4/07 原施法动作与可跳避／格挡的宝石远程招式（57项检查通过），R4/08 1280px 雕像回廊／鬼剑士雕像苏醒与魔法格挡（82项检查通过），R4/09 V 上挑／有限短浮空追击（88项检查通过）；F4 在港口保持姿势对照。入口和实测见 `README.md` 与 `docs/r4_09_delivery_check.json`。用户最新要求持续迭代至剩余额度低于 50%，替代下文历史 10% 停止线；仍不自动使用重置额度或额外付费。下文保留启动交接时的历史状态与分析依据，旧的“等 R1 完整验收再扩内容”由本次用户授权调整。

版本：v1.0。整理日期：2026-10-23。用途：复制到一个干净的新目录，供负责人和新会话中的 AI 直接接手。

**当前目标：以 DNF 为基础制作离线单机游戏，保留可辨识的角色、职业动作、装备、敌人与地区；将零散房间重新组织成可以连续探索的大区域，采用 2D 角色与 3D 场景结合的表现。先做西海岸的小样，确认观感后扩展。**

本文件汇总现有决定、实测结论、客户端位置、工具状态、制作约定和下一轮任务。附录包含三个完整的只读分析脚本，复制这一份文档即可恢复分析入口，无须搬入旧 Demo。客户端原文件仍需保留在 Downloads 或另行指定的来源目录。

状态说明：**已确认**来自用户决定；**已验证**来自现有文件检查或有限抽样；**建议**是可调整的实施方案；**待验证**不能视为已完成。文件中的数量、版本和路径均记录于上述日期，不代表将来环境自动一致。

## 1. 新项目采用哪些决定

| 项目 | 当前决定及其含义 |
| --- | --- |
| 题材 | 优先复刻 DNF，保留人物、地区和原作辨识度；东方玄幻原创设定、换皮与重设风格延后 |
| 游戏形式 | 离线单机，暂不考虑联机、账号、匹配、服务器和多人同步 |
| 地图 | 原有小房间合并、延展为几个较大区域；具体数量、尺寸尚未确定 |
| 副本入口 | 放进城镇之间及周边的实际空间，通过道路、塔门、洞穴、码头等进入，减少以菜单选关为主的流程 |
| 开放感 | 路线连续、地标清楚、可以探索和往返；允许内部区块加载，不要求全大陆一次加载 |
| 视角与走位 | 横版、地面有纵深、固定方向镜头；开放感不意味着改为自由第三人称 |
| 角色与特效 | 玩家、敌人、NPC、武器和技能特效优先整理客户端原有 2D 素材与逐帧动画 |
| 场景 | 地面、近景建筑和地标逐步 3D 化；远海、天空、远山等可保留 2D；追求 HD-2D 式空间与光照层次 |
| 起始地区 | 西海岸；先做一小段有辨识度的街道与人物，随后连接战斗区域 |
| 客户端选择 | 95 包作为工作底包，70 包保留作旧版对照与候补；不自动照搬全部 95 年代内容与规则 |
| 制作方式 | 在 Mac 上完成日常开发与大部分素材整理；Windows 用于 Mac 难以胜任的 AI 生成和 Windows 包实测 |
| 设备升级 | 暂时使用现有设备，遇到实际瓶颈再决定 |
| 推进方式 | 从视觉与动作小样起步，经过试玩再增加任务、技能、敌人和装备，不立即铺开全世界 |

用户仍重视战斗与装备养成、角色和世界背景的丰富感，喜欢早期 DNF 的挑战与街机反馈，不喜欢后期无限数值膨胀。这些是体验偏好，具体技能、掉落和成长参数需要重新设计、试玩。

下列旧提案**不作为新项目的默认要求**：全 3D 人物、怪猎式长刃与时机反击、禁止跳跃与空连、旧版三个原创技能、三级两点技能树、六件装备、砾甲兽、宗门王朝背景、旧选关与四段低多边形街区。它们属于此前探索；新职业的跳跃、浮空、取消和技能派生按本轮选定的原作动作清单核对。

## 2. 旧项目保留什么，不迁移什么

旧目录是 `/Users/mac/project/game/新建游戏项目`。此前发布的 0.26 是简化 3D 原型；0.27 西海岸街区制作已暂停，未作为新方向完成版本交付。用户认为整体廉价感明显，因此不能用旧 Demo 的功能数量代替新方向的视觉验收。

上轮客户端工作完成的是：只读索引、少量图像解码、配置与动画抽样、部分依赖追踪及方案记录。**新的连通地图、原作角色完整动作、混合 3D 场景和对应单机闭环尚未实现。**

新项目默认不复制旧游戏代码、占位人物、旧场景、构建包、测试截图、历史检查点、`.godot/` 缓存和旧进度。若确有一个独立模块值得复用，先看清依赖，再单独决定。附录的分析脚本不依赖旧游戏代码，可以独立恢复。

旧目录与旧存档原地保留。本次交接不清理、搬动、覆盖或删除它们。旧存档位于 `/Users/mac/Library/Application Support/Godot/app_userdata/新建游戏项目/`，新游戏应使用独立应用名称与保存目录，不直接读取或改写旧档。

## 3. 负责人、设备与约束

| 项目 | 当前记录 |
| --- | --- |
| 团队与目的 | 个人或 1–2 人，先做个人作品；没有硬性截止日期，可以学习与反复打磨 |
| 用户职责 | 决定体验、视觉与范围，提供真实试玩反馈，决定额外费用 |
| AI 职责 | 资料与资产整理、设计提案、脚本与工具、Godot 实现、可编辑场景、检查和文档同步 |
| Mac | 用户提供：Mac mini M4、16 GB 内存、1 TB 存储；不得用当前会话主机读到的其他型号替代这条记录 |
| Windows | 用户最新更正：Ryzen 7 9800X3D、RTX 5090、64 GB 内存；存储此前记录为 2 TB，未在目标机器重新实测 |
| 主工作流 | Mac 本地项目、本地 Blender／图片工具和 Godot；不把频繁 SSH、跨机素材搬运作为常规制作前置 |
| 目标平台 | Windows 为主要游戏运行目标，Mac 可开发并辅助运行验证；两端分别记录实际测试结果 |
| 费用 | 曾说明每月 200 美元 Pro 订阅，未安排其他预算；不推断包含独立 API、3D 生成、付费素材或服务器费用 |
| 新增工具 | 现有工具足以开始；遇到具体缺口再提出用途、替代方式和费用 |
| 版本管理 | 建议新建 Git 仓库；提交、推送和发布按用户明确请求执行 |

不以旧的“每天约三小时”作为启动限制，也不再把购买新 Mac 作为前置。两台实际设备上的完整新样片性能尚未测量。

用户此前对持续开发设置过额度边界：**剩余额度到 10% 或出现实际重置就停止，不接着消耗重置后的额度或额外付费预算。** 今后如用户再次要求持续开发，应先读取当时的额度窗口并沿用此边界；历史时间戳不能当新基线。读取本交接文档本身不等于恢复旧的无限持续开发队列。

## 4. 两个客户端的位置与选择依据

| 来源 | 已解压目录 | 保留的压缩包 |
| --- | --- | --- |
| 当前工作底包：95 | `/Users/mac/Downloads/天堂95起源单机客户端` | `/Users/mac/Downloads/95起源单机客户端.rar` |
| 对照与归档：70 | `/Users/mac/Downloads/DNF复古70客户端` | `/Users/mac/Downloads/DNF复古70一体包客户端2.rar` |

这些名称是来源标签，不能据此认定是纯净的官方 70 或 95 对应补丁。70 包出现 timegate、powerstation 与 2013 等内容，95 包有起源及 2018 等内容；准确目标年代需要逐项筛选。

### 4.1 已验证的清单

| 指标 | 70 包 | 95 包 |
| --- | ---: | ---: |
| 解压文件数 | 2,582 | 8,735 |
| 解压总字节数 | 4,432,254,617 | 18,294,899,871 |
| ImagePacks2 的 NPK 数，扩展名不区分大小写 | 1,457 | 7,427 |
| 索引到的 IMG 条目 | 57,929 | 190,238 |
| 不重复 IMG 路径 | 57,929 | 165,557 |
| 存在多份的 IMG 路径 | 0 | 20,423 |
| 同一路径最多副本数 | 1 | 14 |
| 主 Script.pvf 字节数 | 178,234,449 | 328,647,833 |
| 主 PVF 目录读取 | 约第 50 项解析失败，树 CRC 不符 | 597,489 项，树 CRC 通过，条目数据边界均在文件内 |

95 主 `Script.pvf` SHA-256：

```text
dc0e1acbc98b03b160e9ddb0643efdc7752cdf9c8969937507720a4ca2705c7b
```

70 主 `Script.pvf` SHA-256：

```text
e17d3a64f7eccdb613c5cabb4e38c47b465f78ebc99f2b066fedffae25ce3ded
```

70 PVF 的整文件 CRC32 为 `81810514`，与压缩包元数据一致。因此未把解析失败简单归为解压损坏；具体非标准格式、加密或内容原因尚未解决。无需等它解析成功才能启动首条路线。

95 有两个异常 NPK：`sprite_interface2_event_chn_event_2018_180607_ready_to_gunblader.NPK` 仅两字节，`!!!1A_bvgftoig_!! (1).npk` 签名异常；不在本轮西海岸抽样依赖内。

### 4.2 为什么推荐 95，70 还有什么用

95 的目录、任务、地图、技能与动画配置可读取，适合作为有选择的工作底包。抽样中的港口远景、中景、船只、西海岸过场图和七名 NPC 首帧共 11 项，两包像素一致；萝莉安对话头像另有差异。不能由此推断整个客户端画面相同。

70 对当前启动的直接价值较小，仍可用于查找被覆盖的旧外观、音乐和旧版差异。建议保留压缩包归档；是否移走解压目录将来单独决定。不要因为这一判断自动删除任一来源。

95 有大量定制覆盖包。`!!!...`、`1A_起源补丁_可删除...` 等名称不能直接解释为加载优先级。**不得把所有包展开后按同名文件随意覆盖。** 已有抽样显式选择规范的 `sprite_*.NPK` 或 `sprite.NPK`；游戏实际补丁加载顺序未复现。

### 4.3 能复刻到哪一步

已有条件支持：选择性导出原图与音频、重组分层人物、参考原始动画与配置，在 Godot 重新实现一段可辨识的城镇、职业动作和单机流程。

尚需制作：完整动作语义、攻击判定与取消、怪物 AI、技能派生、任务触发、装备掉落与数值、区域连接、世界状态和存档。PVF 是数据与脚本资料，不能直接等同于完整引擎行为；读取成功也不等于玩法已经还原。

客户端图像不能直接提供完整 3D 建筑、背面、厚度、UV、骨架或动画。场景 3D 化需要依据原图重建，并补出新的连接地带。本次没有从客户端得到可直接复用的原作 3D 场景工程。

没有运行客户端 EXE、DLL、启动器或服务端；95 内的 `df_game_r` 是 Linux 32 位 ELF，不是 Godot 工程或已获得的游戏源码。现阶段无需运行它。素材保留来源和用途记录；对外分享时再逐项核对可使用范围与替换需求。

## 5. 已读内容与新项目容易踩的解析问题

### 5.1 验证覆盖面

- 84 次图像帧解码成功；保留 Alpha、原画布、裁剪偏移和 LINK 帧关系。这是抽样，不是全素材库验证。
- 37 个配置样本 CRC 通过，包含西海岸地图、城镇、六个副本、技能、任务、人物与 AI。
- 12 个二进制 ANI 解析并通过数据校验：男鬼剑士待机、普攻一／二、奔跑、崩山击，以及七名 NPC 动画。
- 两段 `(f)` 西海岸地图的表现依赖追踪分别涉及 35／21 个节点、24／13 项 IMG 引用，均能在 95 包定位；没有验证所有战斗房间、敌人和事件依赖。
- 音频索引：70 有 63 个 SoundPacks NPK、8,967 条；95 有 99 个、20,715 条。每包仅抽查三个 Ogg 头，未逐段听验或恢复地图声音事件映射。

这些结果证明可读性，不能证明历史版本准确、运行时行为准确或全量导入完成。IMG 2 是主要已测格式，旧格式及 IMG 4／5 未获得同等覆盖。

### 5.2 动画与文字

男鬼剑士 `sm_body0000.img` 的 210 个索引是图像帧索引，不是 210 个独立动作。已组合身体、裤子、鞋、上衣、头发，在 0、8、19、25、50、105 索引检视过外观。

| 已读 ANI | 帧数 | 本次读取的时长 |
| --- | ---: | --- |
| 待机 stay | 6 | 每帧 120 ms |
| 普攻 attack1 | 10 | 前九帧各 50 ms，末帧 150 ms |
| 普攻 attack2 | 11 | 前十帧各 50 ms，末帧 150 ms |
| 奔跑 dash | 8 | 每帧 100 ms |
| 崩山击 hopsmash | 7 | 120、240、60、180、60、60、180 ms |

ANI 为二进制结构，不能直接当普通 `b0d0` 配置 token 解析。图像路径可能省略 `sprite/`，并使用 `%04d` 外观占位；运行时须由角色外观选择解析，不应把所有路径永久替换成 `0000`。

绘制应以逻辑脚底为锚点，再应用 ANI 偏移及 IMG 裁剪偏移；同时保存图层顺序、混合方式和每帧时长，不能用图片中心或统一 FPS 替代。跳跃高度与地面纵深分开处理。

崩山击样本读到 10 条受击框与 3 条攻击框记录；普攻一的样本只有受击框。完整判定还可能依赖 `.act`、`.atk` 等数据及引擎规则，不能“没有 ANI 攻击框就没有攻击”，也不能把受击框直接变成伤害框。

95 抽样文字字典实际为 **Big5**；文件叫 `.kor.str` 不代表该包内容必须按韩文编码。现有 `PVF.tokens()` 默认编码不是这一包的文字答案，读取相关字符串应显式传入 `'big5'`。文本引用按 `n_string.lst` 的列表 ID 找到对应字典再解析 key，不能全局取第一个同名 key。

### 5.3 最小素材定位表

| 用途 | IMG 路径或定位方式 |
| --- | --- |
| 港口远景 | `sprite/map/hendonmyre/westfar00.img` |
| 港口中景 | `sprite/map/hendonmyre/westmid00.img` |
| 船只 | `sprite/map/hendonmyre/westnearship.img` |
| 西海岸过场图 | `sprite/map/cutscene/westcoast.img` |
| 莎兰／萝莉安／卡坤 | `sprite/map/npc/npc_sr.img`／`npc_lo.img`／`npc_kg.img`，后两项同目录 |
| 达芙妮／罗杰／奥菲利亚／艾丽丝 | 同目录 `npc_dp.img`／`npc_rg.img`／`npc_op.img`／`npc_ir.img` |
| 萝莉安头像样本 | `sprite/map/npc/npcface01.img`，帧 11 |
| 男鬼剑士身体 | `sprite/character/swordman/equipment/avatar/skin/sm_body0000.img` |
| 同套裤／鞋／上衣／头发 | 同 avatar 目录下 `pants/sm_pants0000a.img`、`shoes/sm_shoes0000a.img`、`coat/sm_coat0000a.img`、`hair/sm_hair0000a.img` |

西海岸与 NPC 优先查规范包 `sprite_map_hendonmyre.NPK`、`sprite_map_cutscene.NPK`、`sprite_map_npc.NPK`。角色规范包以 `sprite_character_swordman_equipment_avatar_<部位>.NPK` 定位；实际导入仍要逐条记录来源包，不能只保存 IMG 路径。

音乐候选：`westcoast_old.ogg`、`westcoast.ogg`、`westcoast_new.ogg`、`skycastle.ogg`、`skycastle_boss.ogg`。这些名称存在不等于已经选定目标版本或循环点。

### 5.4 地图、任务与技能入口

城镇 `town/westcoast.twn` 读到 11 项 area 定义，不等于已经恢复 11 张可玩地图。其逻辑地图引用如何选择 `(f)`／`(r)` 变体尚未验证。已读地图路径：

```text
map/hendonmyre/(f)westcoast.map
map/hendonmyre/(r)westcoast.map
map/hendonmyre/(f)westcoast_magic.map
map/hendonmyre/(r)westcoast_magic.map
map/hendonmyre/(f)gate_west.map
map/hendonmyre/(r)gate_west.map
map/hendonmyre/d_westcoast.map
map/hendonmyre/d_westcoast2.map
map/hendonmyre/sky_westcoast.map
map/hendonmyre/sky_westcoast2.map
map/hendonmyre/west2death.map
map/hendonmyre/west2fallen.map
map/hendonmyre/west2stranger.map
map/hendonmyre/west_ura.map
```

部分 `(f)` 变体引用 `map/town/05_hendonmyre/...` 的较新背景与地面素材，70 包中没有相应项。因此不能仅凭 `(f)` 文件名宣称已找到准确的早期布局。NPC 坐标也只能标为来源变体数据，尚未确认为指定 70 年代坐标。

| 副本 | PVF 路径 |
| --- | --- |
| 龙人之塔 | `dungeon/act2/draconiantower.dgn` |
| 人偶玄关 | `dungeon/act2/hallofdoll.dgn` |
| 石巨人塔 | `dungeon/act2/golemtower.dgn` |
| 黑暗玄廊 | `dungeon/act2/darkentrance.dgn` |
| 城主宫殿 | `dungeon/act2/palaceofload.dgn`，保留原路径拼写 |
| 悬空城 | `dungeon/act2/floatingcastle.dgn` |

这些 DGN 可提供房间组合、起点、Boss 房位置和房间 ID 等参考，未完成其全部依赖还原。

其他已读入口：

```text
character/swordman/swordman.chr
skill/swordman/hopsmash.skl
skill/swordman/tripleslash.skl
skill/swordman/upperslash.skl
n_quest/westcost/draconiantower/epic_16_draconiantower_skycastle_1.qst
n_quest/westcost/draconiantower/epic_16_draconiantower_skycastle_2.qst
monster/newmonsters/draconian/magneus/ai/action.ai
```

两项任务已读到“精靈的魔法陣(1/2)”相关文字、前置、NPC 与奖励数据，尚未做成游戏逻辑。具体 ANI 路径及 NPC 配置清单可由附录 `content_probe.py` 的样本列表恢复。

## 6. 视觉目标与资产管线

先保住西海岸的拱门、浅色石墙、港口、船体、魔法师建筑与人物比例，再谈泛光、景深和精细材质。用户对旧 Demo 的问题是整体廉价感；不再用通用坡屋顶小屋、玩具积木人物或大面积平涂低多边形替代原作辨识度后直接扩内容。

建议先建立原图构图与 2D 动作的基准，再以同一视角和尺度加入 3D 地面及一两件近景建筑，逐项比较：脚底、地面透视、前后遮挡、阴影、色彩、像素过滤与透明特效。HD-2D 不强制像素化或大量景深；以动作可读、风格协调为通过条件。

| 资产 | 编辑与导出方式 |
| --- | --- |
| 原图、角色、NPC、技能特效 | 选择性解码 PNG／图集，保留动画元数据；修补使用 Krita，批处理使用 Python |
| 建筑、地标、船体和地面 | Blender 保存 `.blend`，整理 UV、材质和贴图，导出 GLB/glTF，再在 Godot 检查 |
| 远景、头像与图标 | 原图优先；补画保留 `.kra` 或其他分层源；需要生成时再核对工具能力 |
| 边框、标记、路标、小地图符号 | 原有素材优先；新规则图形可用 Inkscape SVG，必要时导出 PNG |
| 音频 | 原始文件留来源，导入所需片段；批处理用 FFmpeg，精修有需求再补 Audacity |

每项进入游戏的资产至少记录：来源客户端标签、NPK 包名、IMG／PVF 路径、帧索引、选用理由、文件摘要、导出参数、修改源与生成文件。动画再记录画布、裁剪、脚底、帧时长、图层与混合方式。白名单之外的全量客户端文件不进入日常 Godot 资产目录。

地图另存“原城镇／副本／房间 ID → 新区域／位置”的对应表，明确道路、入口、任务和敌人位置。原作不存在的连接区域是改编内容，不能标作原版地图实证。

混合渲染的技术路径先用小样验证：可以比较 Sprite3D／平面材质与透明排序等实现，再固定一条；不提前搭万能的 2D／3D 双后端框架。战斗空间与表现分开：地面位置、朝向、跳跃高度、攻击范围和受击范围要能单独检查。

## 7. 已安装工具与控制方式

以下版本是本机命令实测，新的任务先确认路径仍有效。软件存在、帮助入口存在和完整自动化已经跑通是不同状态。

| 工具 | 版本／位置 | 本项目使用方式与状态 |
| --- | --- | --- |
| Godot | 4.7.2.stable.official.ed1daf0bf；`/Applications/Godot.app/Contents/MacOS/Godot` | 场景、输入、战斗、任务、技能、存档与桌面导出；新建工程需重新验证入口和目标包 |
| Blender | 5.2.2 LTS；`/Applications/Blender.app/Contents/MacOS/Blender` | 场景建模与 GLB 导出；已有 `blender_official` 工具入口，新会话先只读读取场景、验证连接 |
| Krita | 5.3.4.1；`/Applications/krita.app/Contents/MacOS/krita` | 位图与图层；已验证 `--version`、`--help`，发现导出、序列导出与文件图层入口；未完成实际导出／Python API／实时图层控制验证 |
| Inkscape | 1.4.4；`/Applications/Inkscape.app/Contents/MacOS/inkscape` | 直接编辑 SVG，再用 CLI 查询、动作与导出；`--version`、`--help` 已通过，实际导出待测 |
| Git／Git LFS | `/usr/bin/git`；`/opt/homebrew/bin/git-lfs` | 命令已找到，旧目录没有 `.git`；新仓库、LFS 类型和远端尚未配置 |
| FFmpeg | `/opt/homebrew/bin/ffmpeg` | 命令已找到，帧预览与转码按具体任务验证 |
| uv | `/opt/homebrew/bin/uv` | 管理用户 Python 与项目环境，不再重复安装第二个用户解释器版本 |

Krita、Inkscape 当前不在 PATH，可直接用上述完整路径。Krita 安装包内有 `kritapykrita.so` 和 Scripter（脚本调试工具），说明存在 Python 扩展入口，不能直接宣称已经具备任意图层的可靠远程控制。

本会话未发现专用 Krita／Inkscape MCP。开始工作无需先寻找 MCP：SVG 文本和图片批处理可直接写文件、经 CLI 导出并查看结果；需要交互编辑时再验证 UI 或软件自身脚本。Blender 和 Godot 的 MCP 也要按新文件、新工程重新检查，不能仅凭已有入口假定连接完成。

旧项目启用的 `addons/godot_ai` 版本为 4.3.0。若新工程需要该插件，只迁移完整插件目录并在新工程启用、Configure，核对连接；不把旧项目所有插件、autoload 和设置一起复制。常规文件编辑与 Godot CLI 可独立起步。

### 7.1 Python 环境

用户由 uv 管理的版本是 **Python 3.13.16**。`/Users/mac/.local/bin/python3.13`、`python3`、`python` 指向该用户运行时。系统 `/usr/bin/python3` 的 3.9.6 属于 macOS 环境，不为“只保留一个用户版本”而删除系统运行时。

此前分析实际使用应用附带、已有 NumPy／Pillow 的运行时：

```text
/Users/mac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3
```

它当时为 Python 3.12，属于应用依赖，不是另行安装给用户管理的新版本。若缓存路径变化，先定位现有应用依赖；也可使用 uv 的 3.13 建同版本项目虚拟环境并核对 NumPy／Pillow。不要声称后者的依赖已经测试，也不要为此再安装其他用户 Python 版本。

### 7.2 其他工具是否还需要

当前 Godot、Blender、Krita、Inkscape、Python 与 FFmpeg 足以启动。频繁处理像素帧和帧标签时再考虑 Aseprite；人工精修音频时再考虑 Audacity。生成模型、图像或纹理的具体服务、额度、质量和可编辑性需单独验证，不能从 Pro 或 MCP 名称推断已具备。

Godot 默认在导入时栅格化 SVG，复杂 SVG 效果以引擎中结果为准；SVG 文字需要时转路径，动态界面文字优先使用 Godot 字体控件。复杂图形可从 Inkscape 导出 PNG，同时保留 SVG 源。

## 8. 干净新目录的建议结构

用户尚未指定新路径和正式名称；本轮仅生成交接文档，不创建新项目、不操作旧目录。

```text
新项目/
  DNF新项目启动交接.md       本文件，可作为项目依据
  README.md                 实际运行方式、当前状态、下一步
  game/
    project.godot
    scenes/
    scripts/
    data/                   动作、人物、区域、任务、装备等配置
    assets/                 仅放挑选后的 PNG、GLB、音频和运行资产
  source_art/               .blend、.kra、SVG 等可编辑源，放在 Godot 根目录外
  tools/
    dnf_client_analysis/    从本文附录恢复的三个脚本
  docs/                     小样结论、来源清单、区域对应表和决策记录
  work/                     临时解码、预览与检查输出，通常不入库
  builds/                   导出包，通常不入库
```

客户端保留在工程外，作为只读来源。按选定地区与角色生成运行资产和清单，避免复制十几 GB 的完整客户端、多份补丁、缓存或大量重复帧。

若新建 Git，先设置 `.godot/`、临时输出、导出包、虚拟环境等忽略规则，再决定 `.blend`、`.kra` 等大文件是否使用 LFS。不要先把整个客户端提交后再补管理规则。源文件与必要元数据应可恢复，缓存可以重新生成。

## 9. 后续阶段与完成条件

下表是建议路线。阶段可以拆小步实现；任何尚未制作的交付不写为通过。

| 阶段 | 核心交付 | 完成条件 |
| --- | --- | --- |
| R0 素材与原作基准 | 一名原作角色、少量 NPC、一段西海岸原画面与若干原始动作 | 透明度、图层、脚底、帧时长正确；每项能追到来源包；明确哪些年代差异未定 |
| R1 混合场景视觉小样 | 相同构图下的 2D 角色＋3D 地面、建筑／地标 | 用户认可整体观感；比例、光照、投影、遮挡、像素清晰度和特效协调；保留可编辑源 |
| R2 连通地图样片 | 据点、连接区域、塔入口与一小段塔内空间 | 能实际走到、进入并返回；方向和地标清楚，主要进入流程不依赖选关菜单 |
| R3 单机可玩循环 | 一条任务、少量原作技能、敌人／Boss、掉落与成长、本地存档 | 新档能接取、探索、战斗、交付、成长并重启恢复；结算不重复，失败与刷新规则明确 |
| R4 按批扩展 | 更多有关联的街区、支路、人物、战斗与装备 | 制作方法可重复，新增内容有作用，任务、存档、画面与目标设备性能经过验证 |

**建议第一条路线：西海岸据点 → 周边连接区域 → 龙人之塔入口 → 一段塔内战斗与 Boss → 返回据点交付。** 这是地图改编提案，尚未锁定，不宣称原版存在完全相同的空间连接。

第一批建议使用已有可读素材的男鬼剑士，先验证待机、奔跑、基础攻击及一个技能，例如崩山击。第一职业、NPC 名单、技能总量和最终任务没有全部由用户确认。不要由样本文件数量自动扩成所有职业、整座城和六个完整副本。

首轮验收重点：先解决用户看到的廉价感，**R1 获得用户视觉认可后再扩内容**。没有报错、能移动、文件很多，都不等于视觉或玩法通过。

### 9.1 最低检查项

- 原作参照与新画面可在相近镜头、比例下对比，能辨认西海岸的地标和人物。
- 横向／纵深移动、左右朝向、脚底和遮挡一致；跳跃如被采用，视觉高度不改变地面站位。
- 动画按原始时长播放，服装和武器分层不抖动；透明边缘、刀光、阴影不过度模糊。
- `.blend`／分层图／SVG 与导出资产对应，修改一处后能重复导出。
- 后续战斗加入时，有效帧与范围能解释；不从几何相交或动画图像尺寸直接推导全部命中。
- 连通路线能往返，任务目标映射到新位置，敌人刷新和存档各有明确规则。
- Mac 与 Windows 运行结果分别记录；不能把 Mac 验证当作 Windows 包已通过。

建议新样片先以 1080p、60 FPS 为观察目标，最终像素尺度、相机与性能预算由实际样片决定；当前没有两台设备上新场景的性能结论。

## 10. 待定事项及协作约定

| 待定事项 | 何时处理 |
| --- | --- |
| 精确复刻哪个年代／补丁的画面、规则与人物状态 | R0 起逐项记录差异；地图连续化本身已经是改编，不必等到每个历史细节考证完才出样片 |
| 第一职业、首批动作和技能 | R0／R1 确定小清单，再扩完整战斗 |
| 场景正式材质、过滤、灯光、景深和投影方案 | R1 对照样片与用户视觉反馈 |
| 大区域尺寸、连接关系、支路与首个任务 | R2 的可走路线验证 |
| 死亡恢复、敌人重置、返程、近路和快速移动 | R2／R3 试玩后明确，不沿用旧选关隐含规则 |
| 原作数值、装备和技能保留多少，怎样避免膨胀 | R3 小循环验证，不先铺完整经济 |
| 最低设备与公开发布方式 | 有代表性样片后实测、再决定 |

常规实现和参数可在当前小目标内自行推进；新增费用、改变视角／美术路线、增加联网或扩大职业和地区范围要明确说明。每轮交付可运行结果、关键截图或短录屏、可编辑源、实际测试与主要未知，不用生成文件数量汇报进展。

修改规则时同步文档和验收。发现问题要区分：文件／格式读取失败、功能错误、视觉不协调和体验不理想；不能因数据 CRC 通过就声称游戏行为还原。

## 11. 新会话可直接使用的启动说明

把本文件复制到新目录，然后在新会话发送下面这段话。路径、应用版本与连接需要重查；不需要把所有旧资料再交给新会话。

```text
请完整阅读项目根目录的《DNF新项目启动交接.md》，以其中最新决定为准。

从干净的 Godot 工程开始，先做 R0／R1：原作 2D 角色动作与一小段西海岸的画面验证，再尝试同构图的 3D 地面和建筑，做出协调的 HD-2D 式观感。

先核对客户端路径、工具和 MCP 连接，必要时从文档附录恢复三个分析脚本。95 包作工作底包，70 包只作对照，选择性导入并保留来源与动画元数据。

不要自动迁移旧 Demo、旧存档、旧全 3D 人物或东方玄幻设定，也不要直接扩成完整大世界。先把角色比例、动作、地标、遮挡、光照与像素清晰度做好，交付可运行样片和可编辑源，得到我的视觉反馈后再推进内容。
```

## 12. 附录使用方法：恢复只读分析工具

下面三个脚本为此前实际使用的完整源代码，供新项目恢复到 `tools/dnf_client_analysis/`，文件名保持一致。它们只读客户端，在 `/tmp/dnf_client_analysis/` 写分析结果；不启动任何客户端程序、不修改来源或游戏存档。

它们是有限的独立分析器，不是完整转换器、补丁优先级模拟器或 DNF 引擎。先检查脚本顶部的来源／输出路径。两份解压来源都在时可按原样运行；如果只保留 95 来源，需要同时调整各脚本对两包比较的假设，不能直接删除目录后原样运行。

依赖：NumPy、Pillow；原图预览脚本还使用 Mac 字体 `/System/Library/Fonts/Hiragino Sans GB.ttc`。换系统需替换字体。原始完整索引可能较大，留在临时目录，不当作游戏资产整体复制。以下是恢复后可执行的顺序，**本次汇总不会自动重跑**：

```sh
mkdir -p /tmp/dnf_client_analysis
/Users/mac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/dnf_client_analysis/inspect_clients.py
/Users/mac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/dnf_client_analysis/probe_images.py
/Users/mac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/dnf_client_analysis/content_probe.py
```

必须先建立 `/tmp/dnf_client_analysis` 父目录。缓存运行时不存在时，先按第 7.1 节定位已有 Python 环境，不盲目安装另一版本。结果为索引、摘要、抽样 JSON 和预览图；本文的独立跨包像素比对和汇总审计不全部由这三步自动生成，若需更新数值必须另作统计核验。

源代码 SHA-256，恢复时可核对：

| 文件 | SHA-256 |
| --- | --- |
| inspect_clients.py | `bdee103106fa83dd950e5571edac15a19ac57d870af8c0fd94949d81ff453871` |
| probe_images.py | `59641b3fef12281731c7c5175ccca3330db49cd884ed263765091a0deb6bbe77` |
| content_probe.py | `0c664dfee77075621e642fa361fe26e2efcbad5e1dd312aaf72f64691931e59f` |

格式参考为此前核对过的公开实现：[NPK 提取器参考](https://github.com/NeroBlackstone/dfo-npk-extractor-bun/tree/c727474f7065f3f4513c8005e3f68158efdd7eec/src)、[DNF parser 参考](https://github.com/onlyGuo/dnf_parser)。附录是本地分析代码，未导入、运行客户端程序或远程仓库代码。

工具说明参考：[Krita](https://krita.org/en/features/)、[Inkscape 命令行](https://inkscape.org/doc/inkscape-man.html)、[Godot 图像导入](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html)。工具状态以本机实测与实际输出为准。

### 附录 A：inspect_clients.py

<!-- BEGIN_SOURCE: inspect_clients.py -->
```python
"""Read-only DNF NPK/PVF inspection. Never imports or launches client code.

Format references inspected, not executed:
https://github.com/NeroBlackstone/dfo-npk-extractor-bun/tree/c727474f7065f3f4513c8005e3f68158efdd7eec/src
https://github.com/onlyGuo/dnf_parser
This is a limited independent inspection implementation, not a game interpreter.
"""
from pathlib import Path
import collections, gzip, hashlib, json, struct, sys, zlib
import numpy as np

BASE = Path('/Users/mac/Downloads')
OUT = Path('/tmp/dnf_client_analysis')
CLIENTS = {'70': BASE/'DNF复古70客户端', '95': BASE/'天堂95起源单机客户端'}

def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2))

def decrypt(data, crc):
    assert len(data)%4 == 0
    words=np.frombuffer(data, dtype='<u4') ^ np.uint32(0x81a79011 ^ crc)
    return ((words >> np.uint32(6)) | (words << np.uint32(26))).tobytes()

class PVF:
    def __init__(self, path):
        self.path=Path(path)
        with self.path.open('rb') as f:
            header=f.read(56)
            assert struct.unpack_from('<I',header)[0]==36
            ver,length,crc,count=struct.unpack_from('<4I',header,40)
            tree=decrypt(f.read(length),crc)
        self.base=56+length
        self.entries={}
        pos=0
        invalid=[]
        parse_error=None
        size=self.path.stat().st_size
        for i in range(count):
            number,n=struct.unpack_from('<II',tree,pos);pos+=8
            if not 0<n<=4096:
                parse_error={'entry':i,'tree_offset':pos-8,'path_length':n}
                break
            name=tree[pos:pos+n].rstrip(b'\0').decode('utf-8','replace').lower();pos+=n
            size_f,crc_f,offset=struct.unpack_from('<III',tree,pos);pos+=12
            e={'path':name,'bytes':size_f,'crc':crc_f,'offset':offset,'number':number}
            if self.base+offset+((size_f+3)&~3)>size:invalid.append(name)
            self.entries[name]=e
        self.header={'version_raw':ver,'tree_bytes':length,'file_count':count,'unique_paths':len(self.entries),'tree_consumed':pos,'tree_padding':length-pos,'tree_crc_expected':crc,'tree_crc_actual':zlib.crc32(tree,count)&0xffffffff,'payload_bounds_errors':invalid,'parse_error':parse_error}
        self.strings=None
    def read(self, name, check=False):
        e=self.entries[name.lower()]
        with self.path.open('rb') as f:
            f.seek(self.base+e['offset']);raw=f.read((e['bytes']+3)&~3)
        d=decrypt(raw,e['crc'])
        if check:
            # CRC schemes in modified clients can differ; report without assuming.
            return d[:e['bytes']], {'expected':e['crc'],'actual_seed_file_number':zlib.crc32(d,e['number'])&0xffffffff,'actual_seed_zero':zlib.crc32(d)&0xffffffff}
        return d[:e['bytes']]
    def load_strings(self):
        data=self.read('stringtable.bin')
        n=struct.unpack_from('<I',data)[0]
        offsets=np.frombuffer(data,dtype='<u4',count=n+1,offset=4)
        assert offsets[-1]+4<=len(data)
        self.strings=[data[4+int(offsets[i]):4+int(offsets[i+1])] for i in range(n)]
        return n
    def tokens(self,name,encoding='gb18030'):
        if self.strings is None:self.load_strings()
        data=self.read(name)
        if not data.startswith(b'\xb0\xd0'):return {'format':'binary','bytes':len(data),'prefix':data[:32].hex()}
        out=[]
        for i in range(2,len(data)-4,5):
            t=data[i];v=struct.unpack_from('<i',data,i+1)[0]
            if t in [5,6,7,8,10] and 0<=v<len(self.strings):
                raw=self.strings[v]
                try:s=raw.decode('utf-8')
                except UnicodeDecodeError:s=raw.decode(encoding,'replace')
                out.append({'type':t,'index':v,'text':s})
            elif t==4:out.append({'type':t,'value':struct.unpack_from('<f',data,i+1)[0]})
            else:out.append({'type':t,'value':v})
        return out

KEY=bytearray(256)
HEAD=b'puchikon@neople dungeon and fighter '
KEY[:len(HEAD)]=HEAD
for _i in range(len(HEAD),255):KEY[_i]=b'DNF'[_i%3]

def npk_entries(path, inspect_headers=True):
    path=Path(path)
    entries=[]
    with path.open('rb') as f:
        h=f.read(20)
        assert h[:16].rstrip(b'\0')==b'NeoplePack_Bill',repr(h)
        n=struct.unpack_from('<I',h,16)[0]
        assert n<100000
        table=f.read(n*264)
        assert len(table)==n*264
        for i in range(n):
            offset,length=struct.unpack_from('<II',table,i*264)
            raw=table[i*264+8:i*264+264]
            name=bytes(a^b for a,b in zip(raw,KEY)).split(b'\0')[0].decode('utf-8','replace').lower()
            assert offset>=20+n*264 and offset+length<=path.stat().st_size
            e={'pack':path.name,'path':name,'offset':offset,'bytes':length}
            if inspect_headers:
                f.seek(offset);b=f.read(min(length,36))
                if b.startswith(b'Neople Img File\0'):
                    index_length,version,count=struct.unpack_from('<QII',b,16)
                    e.update(version=version,frames=count,index_bytes=index_length)
                else:e['signature']=b[:20].hex()
            entries.append(e)
    return entries

def read_album(root, entry):
    with (Path(root)/'ImagePacks2'/entry['pack']).open('rb') as f:
        f.seek(entry['offset']);return f.read(entry['bytes'])

def img_frames(data):
    assert data.startswith(b'Neople Img File\0')
    idx,ver,count=struct.unpack_from('<QII',data,16)
    assert ver in [2,4],ver
    pal=None
    p=32
    if ver==4:
        colors=struct.unpack_from('<I',data,p)[0];p+=4
        assert 0<colors<=65536
        pal=np.frombuffer(data[p:p+colors*4],dtype=np.uint8).reshape(-1,4);p+=colors*4
    index_start=p
    data_pos=p+idx
    frames=[]
    for i in range(count):
        typ=struct.unpack_from('<I',data,p)[0]
        if typ==17:
            target=struct.unpack_from('<I',data,p+4)[0];p+=8
            assert target<count
            frames.append({'link':target});continue
        typ,mode,w,h,length,x,y,fw,fh=struct.unpack_from('<9i',data,p);p+=36
        assert 0<=w<=16384 and 0<=h<=16384
        n=(w*h*(4 if typ==16 else 2)) if mode==5 else length
        assert data_pos+n<=len(data)
        frames.append({'type':typ,'mode':mode,'width':w,'height':h,'x':x,'y':y,'canvas_width':fw,'canvas_height':fh,'data_offset':data_pos,'data_bytes':n,'version':ver})
        data_pos+=n
    assert p==index_start+idx,(p,index_start+idx)
    return frames,pal

def decode_frame(data,index):
    from PIL import Image
    frames,pal=img_frames(data)
    seen=set()
    while 'link' in frames[index]:
        assert index not in seen
        seen.add(index);index=frames[index]['link']
    f=frames[index];n=f['width']*f['height']
    raw=data[f['data_offset']:f['data_offset']+f['data_bytes']]
    if f['mode'] in [6,7]:
        dec=zlib.decompressobj();raw=dec.decompress(raw,max(1,n*4+148))
        assert not dec.unconsumed_tail
    if f['type']==16:
        assert len(raw)==n*4,(len(raw),n)
        rgba=np.frombuffer(raw,dtype=np.uint8).reshape(n,4)[:,[2,1,0,3]].copy()
    elif f['version']==4 and pal is not None and len(raw)==n:
        bgra=pal[np.frombuffer(raw,dtype=np.uint8)];rgba=bgra[:,[2,1,0,3]].copy()
    elif f['type'] in [14,15]:
        v=np.frombuffer(raw,dtype='<u2').astype(np.uint32)
        assert len(v)==n
        if f['type']==14:
            rgba=np.column_stack([np.rint(((v>>10)&31)*255/31),np.rint(((v>>5)&31)*255/31),np.rint((v&31)*255/31),(v>>15)*255]).astype(np.uint8)
        else:
            rgba=np.column_stack([((v>>8)&15)*17,((v>>4)&15)*17,(v&15)*17,((v>>12)&15)*17]).astype(np.uint8)
    else:raise ValueError('Unsupported pixel encoding: '+str(f))
    return Image.fromarray(rgba.reshape(f['height'],f['width'],4),'RGBA'),f

def binary_ani(data):
    pos=0
    def read(fmt):
        nonlocal pos
        vals=struct.unpack_from('<'+fmt,data,pos);pos+=struct.calcsize('<'+fmt)
        return vals[0] if len(vals)==1 else list(vals)
    def string():
        nonlocal pos
        n=read('I');assert n<16384
        s=data[pos:pos+n].rstrip(b'\0').decode('ascii').lower();pos+=n
        return s
    count=read('H');res_count=read('H')
    assert count<10000 and res_count<1000
    resources=[string() for _ in range(res_count)]
    def prop():
        typ=read('H')
        if typ in [0,1,10]:val=read('B')
        elif typ in [3,13,24,26,28]:val=read('H')
        elif typ==7:val=read('ff')
        elif typ==8:val=read('f')
        elif typ==9:val=read('4B')
        elif typ==11:
            val={'effect':read('H')}
            if val['effect']==5:val['rgb']=read('3B')
            elif val['effect']==6:val['pos']=read('2h')
        elif typ in [12,23]:val=read('i')
        elif typ==16:val=string()
        elif typ in [17,25]:val=True
        elif typ==18:val=read('Bii4BH')
        elif typ==27:val=read('4h')
        else:raise ValueError(('unknown ANI property',typ,pos))
        return {'type':typ,'value':val}
    globals=[prop() for _ in range(read('H'))]
    frames=[]
    for _ in range(count):
        boxes=[]
        for __ in range(read('H')):boxes.append({'type':read('H'),'xyz_size':read('6i')})
        rid=read('h');image_frame=read('H') if rid>=0 else -1
        x,y=read('ii');properties=[prop() for __ in range(read('H'))]
        frames.append({'resource':resources[rid] if rid>=0 else None,'image_frame':image_frame,'x':x,'y':y,'boxes':boxes,'properties':properties})
    assert pos==len(data),('trailing ANI data',pos,len(data))
    return {'frames_count':count,'resources':resources,'globals':globals,'frames':frames}

def run():
    all_summary={}
    for key,root in CLIENTS.items():
        dst=OUT/key;dst.mkdir(exist_ok=True)
        print('start',key,flush=True)
        pvf=PVF(root/'Script.pvf')
        save(dst/'pvf_header.json',pvf.header)
        save(dst/'pvf_index.json',list(pvf.entries.values()))
        cats=collections.Counter(e['path'].split('/')[0] for e in pvf.entries.values())
        suffix=collections.Counter(Path(e['path']).suffix for e in pvf.entries.values())
        print(key,'pvf',pvf.header,'categories',cats.most_common(20),flush=True)
        candidates=[p for p in pvf.entries if any(s in p for s in ['westcoast','west_coast','skytower','skycastle','behemoth'])]
        save(dst/'pvf_candidates.json',candidates)
        images=[];errors=[]
        packs=sorted(f for f in (root/'ImagePacks2').iterdir() if f.suffix.lower()=='.npk')
        for j,p in enumerate(packs):
            try:images.extend(npk_entries(p))
            except Exception as e:errors.append({'pack':p.name,'error':str(e)})
        save(dst/'npk_index.json',images)
        vers=collections.Counter(str(i.get('version',i.get('signature'))) for i in images)
        summary={'root':str(root),'pvf':pvf.header,'pvf_categories':dict(cats),'pvf_suffixes':dict(suffix),'image_packs':len(packs),'img_entries':len(images),'img_header_versions':dict(vers),'declared_frames':sum(i.get('frames',0) for i in images),'npk_index_errors':errors,'west_related_pvf_paths':candidates}
        all_summary[key]=summary
        print(key,'npk',len(packs),len(images),vers,'errors',len(errors),flush=True)
    save(OUT/'summary.json',all_summary)

if __name__=='__main__':run()
```
<!-- END_SOURCE: inspect_clients.py -->

### 附录 B：probe_images.py

<!-- BEGIN_SOURCE: probe_images.py -->
```python
from pathlib import Path
import json,sys,collections,hashlib
from PIL import Image,ImageDraw,ImageFont
from inspect_clients import *

FONT='/System/Library/Fonts/Hiragino Sans GB.ttc'
font=ImageFont.truetype(FONT,18)
small=ImageFont.truetype(FONT,13)
samples=[
 ('港口远景','sprite/map/hendonmyre/westfar00.img',0),
 ('港口中景','sprite/map/hendonmyre/westmid00.img',0),
 ('港口船只','sprite/map/hendonmyre/westnearship.img',0),
 ('西海岸过场图','sprite/map/cutscene/westcoast.img',0),
 ('莎兰','sprite/map/npc/npc_sr.img',0),
 ('萝莉安','sprite/map/npc/npc_lo.img',0),
 ('卡坤','sprite/map/npc/npc_kg.img',0),
 ('达芙妮','sprite/map/npc/npc_dp.img',0),
 ('罗杰','sprite/map/npc/npc_rg.img',0),
 ('奥菲利亚','sprite/map/npc/npc_op.img',0),
 ('艾丽丝','sprite/map/npc/npc_ir.img',0),
 ('萝莉安对话头像','sprite/map/npc/npcface01.img',11),
]
results=[]
canvases={}
for k,root in CLIENTS.items():
    entries=json.loads((OUT/k/'npk_index.json').read_text())
    # Explicit canonical packs, never assume runtime overlay order for mod packs.
    selected={e['path']:e for e in entries if e['pack'].startswith('sprite_') or e['pack']=='sprite.NPK'}
    panels=[]
    for label,path,index in samples:
        panel=Image.new('RGBA',(540,290),(28,34,42,255))
        d=ImageDraw.Draw(panel);d.text((14,10),label,font=font,fill='white')
        e=selected.get(path)
        if not e:d.text((14,48),'此规范包中未找到',font=font,fill='#f1ab8b');panels.append(panel);continue
        try:
            data=read_album(root,e);im,meta=decode_frame(data,index)
            if im.width>510 or im.height>216:im.thumbnail((510,216),Image.Resampling.LANCZOS)
            elif im.width<220 and im.height<108:im=im.resize((im.width*2,im.height*2),Image.Resampling.NEAREST)
            panel.alpha_composite(im,((540-im.width)//2,42+(216-im.height)//2))
            d.text((14,266),f"{meta['width']}×{meta['height']} / frame {index} / offset {meta['x']},{meta['y']}",font=small,fill='#bec8d7')
            results.append({'client':k,'label':label,'path':path,'pack':e['pack'],'frame':index,'metadata':meta,'sha256_img_payload':hashlib.sha256(data).hexdigest(),'success':True})
        except Exception as ex:
            results.append({'client':k,'path':path,'success':False,'error':str(ex)});d.text((14,60),str(ex)[:45],font=small,fill='orange')
        panels.append(panel)
    sheet=Image.new('RGB',(1080,80+len(panels)//2*290),(19,25,33))
    draw=ImageDraw.Draw(sheet);draw.text((20,15),f'{k} 包：实际解码素材抽样（规范 NPK；非游戏运行截图）',font=font,fill='white')
    draw.text((20,44),'保持原图透明度；大图缩小显示，小人物按整数倍显示。',font=small,fill='#b8c2cf')
    for i,panel in enumerate(panels):sheet.paste(panel,((i%2)*540,80+(i//2)*290))
    sheet.save(OUT/f'assets_{k}.png')
    canvases[k]=sheet
    # Compose a fixed starter appearance by matching frame indices and canvas offsets.
    layers=['skin/sm_body0000.img','pants/sm_pants0000a.img','shoes/sm_shoes0000a.img','coat/sm_coat0000a.img','hair/sm_hair0000a.img']
    strip=Image.new('RGBA',(1200,250),(28,34,42,255));dd=ImageDraw.Draw(strip)
    for j,frame in enumerate([0,8,19,25,50,105]):
        ch=Image.new('RGBA',(500,500))
        for layer in layers:
            path='sprite/character/swordman/equipment/avatar/'+layer
            if path not in selected:continue
            e=selected[path]
            try:
                im,meta=decode_frame(read_album(root,e),frame)
                ch.alpha_composite(im,(meta['x'],meta['y']))
                results.append({'client':k,'path':path,'frame':frame,'success':True,'metadata':meta})
            except Exception as ex:results.append({'client':k,'path':path,'frame':frame,'success':False,'error':str(ex)})
        crop=ch.crop((125,170,325,370))
        strip.alpha_composite(crop,(j*200,35));dd.text((j*200+10,8),f'帧 {frame}',font=font,fill='white')
    strip.convert('RGB').save(OUT/f'character_{k}.png')
save(OUT/'image_probe.json',results)
print('decoded',sum(r['success'] for r in results),'failed',[r for r in results if not r['success']])
```
<!-- END_SOURCE: probe_images.py -->

### 附录 C：content_probe.py

<!-- BEGIN_SOURCE: content_probe.py -->
```python
from inspect_clients import *
import posixpath

p=PVF(CLIENTS['95']/'Script.pvf');p.load_strings()
images={}
for k in CLIENTS:
    es=json.loads((OUT/k/'npk_index.json').read_text())
    images[k]={e['path']:e for e in es if e['pack'].startswith('sprite_') or e['pack']=='sprite.NPK'}
trans={}
lst=p.tokens('n_string.lst','big5')
for a,b in zip(lst[::2],lst[1::2]):
    file=b.get('text','').lower()
    if file in p.entries:
        text=p.read(file).decode('big5','replace')
        trans[a['value']]={line.split('>',1)[0]:line.split('>',1)[1] for line in text.splitlines() if '>' in line and not line.startswith('//')}

def resolved(tokens):
    out=[];listid=None
    for t in tokens:
        x=t.copy()
        if t['type']==9:listid=t['value']
        if t['type']==10:x['resolved']=trans.get(listid,{}).get(t.get('text',''))
        out.append(x)
    return out

names=[
 'town/westcoast.twn',
 'map/hendonmyre/(f)westcoast.map','map/hendonmyre/(r)westcoast.map',
 'map/hendonmyre/(f)westcoast_magic.map','map/hendonmyre/(r)westcoast_magic.map',
 'map/hendonmyre/(f)gate_west.map','map/hendonmyre/(r)gate_west.map',
 'map/hendonmyre/d_westcoast.map','map/hendonmyre/d_westcoast2.map',
 'map/hendonmyre/sky_westcoast.map','map/hendonmyre/sky_westcoast2.map',
 'map/hendonmyre/west2death.map','map/hendonmyre/west2fallen.map','map/hendonmyre/west2stranger.map','map/hendonmyre/west_ura.map',
 'dungeon/act2/draconiantower.dgn','dungeon/act2/hallofdoll.dgn','dungeon/act2/golemtower.dgn','dungeon/act2/darkentrance.dgn','dungeon/act2/palaceofload.dgn','dungeon/act2/floatingcastle.dgn',
 'skill/swordman/hopsmash.skl','skill/swordman/tripleslash.skl','skill/swordman/upperslash.skl',
 'n_quest/westcost/draconiantower/epic_16_draconiantower_skycastle_1.qst',
 'n_quest/westcost/draconiantower/epic_16_draconiantower_skycastle_2.qst',
 'monster/newmonsters/draconian/magneus/ai/action.ai',
 'character/swordman/swordman.chr',
]
names += ['npc/'+n+'.npc' for n in ['seria','sharan','lorian','kagon','roger','daphne','iris','ophelia','marlene_arad']]
checks=[];all_tokens={}
for name in names:
    if name not in p.entries:
        checks.append({'path':name,'exists':False});continue
    data,crc=p.read(name,True)
    tokens=p.tokens(name,'big5')
    if isinstance(tokens,list):tokens=resolved(tokens)
    all_tokens[name]=tokens
    result={'path':name,'exists':True,'bytes':len(data),'crc_matches':crc['expected']==crc['actual_seed_file_number'],'crc':crc,'decoded_kind':'tokens' if isinstance(tokens,list) else 'binary','token_count':len(tokens) if isinstance(tokens,list) else None}
    checks.append(result)
    save(OUT/'95'/'samples'/(name.replace('/','__')+'.json'),{**result,'tokens':tokens})

ani_names=['character/swordman/animation/'+n+'.ani' for n in ['stay','attack1','attack2','dash','hopsmash']]
ani_names+=['npc/animation/npc_'+n+'.ani' for n in ['sr','lo','kg','rg','dp','ir','op']]
ani_checks=[]
for name in ani_names:
    try:
        data,crc=p.read(name,True);a=binary_ani(data)
        save(OUT/'95'/'samples'/(name.replace('/','__')+'.decoded.json'),a)
        paths=[r.replace('%04d','0000') for r in a['resources']]
        ac={'path':name,'success':True,'frames':a['frames_count'],'resources':paths,'total_boxes':sum(len(f['boxes']) for f in a['frames']),'frame_delays':[next((z['value'] for z in f['properties'] if z['type']==12),None) for f in a['frames']],'crc_matches':crc['expected']==crc['actual_seed_file_number'],'images_in_70':all('sprite/'+r in images['70'] for r in paths),'images_in_95':all('sprite/'+r in images['95'] for r in paths)}
    except Exception as ex:ac={'path':name,'success':False,'error':str(ex)}
    ani_checks.append(ac)

# Resolve a representative old street's actual ANI/TIL -> IMG references.
closure={}
for mapname in ['map/hendonmyre/(f)westcoast.map','map/hendonmyre/(f)westcoast_magic.map']:
    todo=[mapname];seen=set();missing=[];fail=[];imgrefs=set();crc_bad=[]
    while todo:
        name=todo.pop()
        if name in seen:continue
        seen.add(name)
        if name not in p.entries:missing.append(name);continue
        data,crc=p.read(name,True)
        if crc['expected']!=crc['actual_seed_file_number']:crc_bad.append(name)
        if name.endswith('.ani'):
            try:refs=binary_ani(data)['resources']
            except Exception as ex:fail.append({'path':name,'error':str(ex)});continue
        else:
            toks=p.tokens(name,'big5')
            refs=[t.get('text','').lower() for t in toks if t['type']==7 and any(t.get('text','').lower().endswith(s) for s in ['.til','.ani','.img'])] if isinstance(toks,list) else []
        for ref in refs:
            if ref.endswith('.img'):
                imgrefs.add(ref if ref.startswith('sprite/') else 'sprite/'+ref)
            else:todo.append(posixpath.normpath(posixpath.join(posixpath.dirname(name),ref.lower())))
    closure[mapname]={'visited_script_count':len(seen),'missing_pvf':sorted(set(missing)),'parse_failures':fail,'crc_failures':crc_bad,'image_reference_count':len(imgrefs),'missing_images_70':sorted(imgrefs-images['70'].keys()),'missing_images_95':sorted(imgrefs-images['95'].keys()),'image_references':sorted(imgrefs)}

# Check audio payload signatures without playing files.
audio=[]
for k,root in CLIENTS.items():
    music=[f for f in (root/'Music').iterdir() if f.is_file() and any(s in f.name.lower() for s in ['west','hendon','sky','town'])]
    sound_packs=sorted((root/'SoundPacks').glob('*.npk'))
    sounds=[];sound_errors=[]
    for f in sound_packs:
        try:sounds.extend(npk_entries(f,False))
        except Exception as ex:sound_errors.append({'pack':f.name,'error':str(ex)})
    examples=[]
    for s in sounds[:3]:
        f=root/'SoundPacks'/s['pack']
        with f.open('rb') as h:h.seek(s['offset']);sig=h.read(8)
        examples.append({'pack':s['pack'],'path':s['path'],'signature_hex':sig.hex()})
    audio.append({'client':k,'music_candidates':[f.name for f in music],'sound_packs':len(sound_packs),'sound_entries':len(sounds),'errors':sound_errors,'header_samples':examples})

out={'sample_scripts':checks,'animation_probes':ani_checks,'map_dependency_probes':closure,'audio':audio,'translation_encoding':'Big5 for inspected 95 PVF string dictionaries','notes':['CRC verifies bytes, not gameplay correctness or historical version.','Map filename (f)/(r) selection rules not executed or confirmed.','NPK mod precedence not reproduced; image samples use explicit canonical packs.']}
save(OUT/'content_probe.json',out)
print('sample scripts',len(checks),'present',sum(e.get('exists',False) for e in checks),'crc pass',sum(e.get('crc_matches',False) for e in checks))
print('ANI',json.dumps(ani_checks,ensure_ascii=False))
print('dependency',json.dumps(closure,ensure_ascii=False))
print('audio',json.dumps(audio,ensure_ascii=False))
```
<!-- END_SOURCE: content_probe.py -->
