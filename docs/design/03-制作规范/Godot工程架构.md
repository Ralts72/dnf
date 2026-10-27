# Godot工程架构

更新日期：2026年10月26日  
状态：新工程建议；尚未创建原创工程或迁移现有代码。

## 结论

采用“按功能分组、模块内部保持内聚”的目录组织：项目根放project.godot与addons，自有脚本、场景和运行时资源放src，原始制作资料放assets并按用途排除导入。

职责、依赖、状态和资源所有权比目录名更重要。优先使用Godot节点组合、明确的动作执行流程和内容数据定义；先为剑士、人形敌人、巨兽和部位规则建立小型模块。开源实例及核实快照独立放在[开源项目架构参考](../05-参考资料/开源项目架构参考.md)。

运行时树以[运行时节点与场景](运行时节点与场景.md)为准：Systems、Session、World、UI、Pause、Transitions与Debug分工；Levels属于World，HUD属于UI。此处描述文件与模块，节点文档描述装配与生命周期。

## 推荐的整体目录

以下为随功能逐步形成的目标结构；实际目录在出现对应功能时创建。

```text
original_game/                         # 仓库根
├── project.godot                      # Godot项目入口
├── addons/                            # 插件与第三方程序扩展
├── assets/                            # 原始制作资料，不作为运行时依赖
│   ├── .gdignore                      # 只用于新工程的原始资料目录
│   ├── characters/                    # Blender工程、原画、原始动画
│   ├── environment/
│   └── audio/
├── src/                               # 自有脚本、场景和运行时资源
│   ├── app/                           # 启动、会话装配、存档与场景切换
│   ├── core/                          # 少量与具体玩法无关的基础工具
│   ├── gameplay/
│   │   ├── actors/
│   │   │   ├── shared/
│   │   │   ├── player/
│   │   │   └── enemies/
│   │   ├── actions/                   # 动作、派生、窗口、取消与执行
│   │   ├── combat/                    # 接触、部位、防御、伤害与失衡
│   │   ├── targeting/                 # 目标选择、部位锁定与辅助朝向
│   │   ├── ai/                        # 感知与决策，向角色提交行动意图
│   │   ├── equipment/                 # 穿戴、适性、套装、装备实例
│   │   ├── inventory/
│   │   ├── progression/
│   │   ├── environment/               # 材料、温湿度状态与反应规则
│   │   ├── interaction/
│   │   └── quests/
│   ├── levels/                        # 具体场景的布置与内容装配
│   │   ├── region_01/
│   │   ├── region_02/
│   │   └── sandbox/
│   ├── content/                       # 具体配置实例与内容目录
│   │   ├── actors/
│   │   ├── actions/
│   │   ├── items/
│   │   ├── recipes/
│   │   ├── materials/
│   │   └── loot/
│   ├── ui/                            # 屏幕、HUD和跨功能通用控件
│   ├── shaders/                       # 跨功能共享着色器
│   ├── shared_assets/                 # 运行时共享字体、纹理、音效等
│   ├── debug/                         # 开发叠加层与可视化工具
│   └── tests/                         # 需要Godot加载的规则与场景测试
├── tools/                             # 导出、转换、校验与构建工具
├── docs/
├── builds/                            # 构建产物，按版本控制策略忽略
├── .gitignore
├── .gitattributes
└── README.md
```

### 仓库根与Godot项目根

本次调整采用常见的工程根布局：打开仓库根的 project.godot，插件位于 res://addons，自有内容主要位于 res://src。

Godot 以 project.godot 所在目录作为项目根，res:// 路径相对于该位置；玩家存档与设置使用 user://。[官方路径说明](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)

对应关系：

```text
仓库中的 src/gameplay/actors/player/player.tscn
运行时为 res://src/gameplay/actors/player/player.tscn

仓库中的 assets/characters/hero/hero.blend
属于原始制作资料；按资产流程导出运行时模型进入src内部
```

例如原始 Blender 文件在 assets 中维护，导出的模型放到 src 中对应角色的 art 目录。运行时所需贴图、声音和动画纳入 src 的功能目录或 shared_assets。

原始 assets 目录添加 .gdignore，docs、tools、builds 等开发资料目录也按用途排除扫描。被忽略的目录不能再通过 load/preload 当作项目资源加载，因此运行时不能依赖其中的文件。[官方导入与目录说明](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html)

addons 应放在 Godot 项目根下。此前把整个 Godot 工程放在 src 的布局中，src/addons 同样对应 res://addons；两种布局都有效。本次建议统一为 project.godot 与 addons 同级位于仓库根，便于识别插件与自有内容。[官方插件安装说明](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/installing_plugins.html)

以上 .gdignore 与目录位置属于新工程建议，本轮未调整现有复刻工程的资产目录。

## 对原目录设想的调整

| 用户设想 | 建议 | 归属原则 |
| --- | --- | --- |
| assets | 保留为原始制作资料 | 运行时导出物进入src内的功能目录或shared_assets |
| src/core | 保留并控制范围 | 数学、通用小工具等基础能力，业务规则有各自模块 |
| src/debug | 保留 | 命中体、锁定点、状态、环境参数等开发可视化 |
| src/gameplay | 保留 | 按角色、动作、命中、装备、环境等职责拆分 |
| src/levels | 保留 | 具体地区、路线、刷怪和场景装配 |
| src/resources | 建议细分用途 | 类型定义跟所属模块，具体数据实例集中在content |
| src/shaders | 保留共享部分 | 功能专用着色器可以跟随角色、特效或环境功能 |
| src/ui | 保留公共界面 | 私有小控件可与对应功能放在一起 |
| 补充app | 增加 | 启动与会话生命周期、各系统的连接 |
| 补充tests和tools | 增加 | 引擎内验证与外部制作工具分开 |

resources 这个名字可以使用，但需要限定它指的是“具体配置实例”还是“Resource类型脚本”。Godot中场景、脚本、模型等本身也都是资源，宽泛命名容易成为杂物目录。

## 功能内部把相关文件放在一起

玩家示例：

```text
src/gameplay/actors/player/
├── player.tscn
├── player.gd
├── player_input.gd
├── player_visual.gd
├── art/
│   ├── player.glb
│   └── body_material.tres
└── audio/
```

一名敌人的专用场景、脚本和模型采用相同原则。跨玩家与敌人复用的移动、动作执行和命中组件，放到明确的共享模块。

Godot官方建议尽量让资源接近使用它们的场景。这样修改或复用一个功能时，可以直接找到它的组成部分。[官方项目组织说明](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html)

本建议保留独立 content 目录，是为了集中维护可被多个角色、地区和工具引用的具体配置。与某个场景强绑定的小资源可以内置或相邻存放。

## Player类与场景组合

需要完整的 Player 入口，负责角色身份、初始化、生命周期和各部分协作；其内部能力由职责明确的组件承担。

概念性场景结构：

```text
Player : CharacterBody3D
├── InputController
├── Locomotion
├── ActionController
├── Combatant
├── BodyParts
│   ├── Head
│   ├── Torso
│   └── Limbs
├── Targeting
└── VisualRoot
    ├── Skeleton3D
    ├── AnimationTree
    └── EquipmentView
```

- InputController把设备操作转换为移动与行动意图。
- Locomotion与角色根节点协作处理地面移动、情境跨越、招式离地及碰撞，不以通用自由跳跃为初版前提。
- ActionController处理当前动作、派生、时序与允许的转换。
- Combatant维护自身运行时战斗状态，并使用统一结算流程。
- BodyParts提供实际接触部位及其状态。
- Targeting维护目标和辅助朝向，动作范围与命中结算仍各有职责。
- VisualRoot与EquipmentView负责模型、动画和装备外观表现。

这是逻辑职责示例，具体受击体需要跟随对应骨骼，而非固定在角色根部。完整场景组合与骨骼挂接见[节点组织方案](运行时节点与场景.md)。独立更新、物理交互与编辑器组合需要使用Node；纯计算可以是普通对象或函数；配置使用Resource；状态数据可以使用独立运行时对象。

敌人通过AI提供行动意图，尽量复用动作执行、命中与受击处理。玩家与敌人的区别主要体现为控制来源、动作配置与专用行为。

## 一次攻击怎样穿过系统

```text
键鼠或手柄输入 / AI决策
    → 行动意图
    → 当前状态判断、输入缓冲与动作派生
    → 动作执行、位移与命中窗口
    → 物理接触与部位信息
    → 防御、肉质、装备属性等统一结算
    → 修改目标运行时状态
    → 受击动作、声音、特效与UI响应
```

动作模块决定什么时候允许攻击、派生与取消；接触检测负责报告实际碰到的部位；结算模块决定该次接触造成的结果。动作动画、伤害公式与HUD通过明确接口协作。

在具体动作中，动画事件可以提供窗口信息。时序验证和关键状态由动作执行逻辑维护，避免仅凭界面、动画名称或特效播放决定伤害。

一击覆盖多个碰撞体时，由统一规则处理重复上报与多部位接触。到底取哪些接触、每个窗口能命中几次，属于战斗规则，后续明确。

## 配置定义 具体内容与运行时状态

三者需要分别归属：

| 层次 | 示例位置 | 内容 |
| --- | --- | --- |
| 类型与规则 | gameplay/equipment/weapon_definition.gd | 一把武器有哪些可配置字段 |
| 具体定义实例 | content/items/weapons/early_sword.tres | 某把武器的基础数据、外观引用、分支等 |
| 运行时实例 | gameplay/equipment/weapon_instance.gd | 玩家持有的那把武器的ID、升级与改造记录 |

类似地：

- ActionDefinition保存动作配置；ActionRuntime保存当前执行时间与命中记录。
- SurfaceDefinition保存材料性质；SurfaceState保存当前温度、湿度等变化。
- EnemyDefinition保存初始配置；每个敌人的生命、失衡和部位状态属于自己的运行实例。

建议把定义Resource视为只读配置，这是项目约定，需要在写法与校验中维护。Godot会缓存和共享已加载的Resource，不能把所有对象的当前生命、技能冷却、环境变化都写入共用定义。[官方Resource说明](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html)

存档记录稳定内容ID、玩家选择和必要的变化状态，并由加载流程恢复场景。具体存哪些世界变化，需要结合环境持久化与任务设计决定。

## 模块依赖与通信

建议保持以下方向：

- app装配玩法对象、具体关卡、UI和会话服务。
- gameplay依赖基础工具与明确的玩法接口。
- levels实例化玩法对象，配置场景内容和外部引用。
- ui读取公开状态、订阅变化，并提交玩家命令。
- 玩法规则独立于某个HUD路径、主菜单和具体地区文件名。

对象之间发起行动，使用明确的方法或命令；已经发生的变化，使用信号通知。局部引用通过场景内明确节点、导出属性或初始化参数传入。

Godot官方的场景组织建议同样强调子场景的独立性，并由拥有者提供必要外部依赖。[官方场景组织说明](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html)

Autoload只承载真正跨场景、具有清楚生命周期的服务。角色、敌人、伤害计算与所有装备数据不需要全部变成全局Manager。输入、存档、设置等是否成为Autoload，在启动与会话设计时逐项决定。

环境反应通过材料、状态和接触关系工作，避免依赖“当前对象是不是玩家”的大量分支。多个模块协作时传递必要数据与清楚事件，模块间依赖在接口处记录。

## 调试 测试与导出

- debug显示攻击窗口、接触部位、朝向辅助、动作状态与环境参数。
- levels/sandbox提供角色操控、命中、防御和环境反应的独立试验场。
- tests优先验证伤害与部位规则、素材与配方引用、资源隔离和存档往返等容易出现跨功能错误的行为。
- tools负责原始资产转换、内容校验和构建流程，避免把制作脚本混入运行场景。

需要通过Godot运行的测试场景留在src内，方便使用res://引用。开发内容是否进入正式包，通过导出入口、资源选择和排除配置管理；.gdignore会影响编辑器导入与运行加载，不能直接代替测试内容的导出策略。[官方导出说明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)

.godot缓存与构建产物按版本控制规则忽略；运行必需的场景、脚本、资源、导入配置等纳入版本管理。[官方版本控制说明](https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html)

## 当前最小落地范围

第一轮只需要建立能够支撑战斗验证的目录与职责：

- app的启动场景与最小会话。
- gameplay中的角色、动作、命中、锁定和少量AI。
- content中的首个动作、角色和武器定义。
- levels/sandbox中的战斗试验场。
- ui中的最小HUD和debug中的战斗观察工具。
- 对应的运行时素材与关键规则验证。

装备制作、任务、地区内容与环境模拟，在相应验证阶段加入模块。划分时保留清楚边界，按真实复用需要逐步抽取共用能力。

这一方案与现有设计清单衔接：纯单人、手柄优先、基础剑士、人形与巨兽统一部位规则、少量装配技能加丰富动作派生。联机模块仍留在初版之外。

## 尚需技术验证的决策

- 新工程Godot版本、脚本语言与渲染配置。
- 角色骨架、动画来源、导出与换装规范。
- 动作配置与AnimationTree、AnimationPlayer的配合。
- 部位碰撞体、武器轨迹与高速接触检测方式。
- 环境状态更新规模、持久化范围与后续性能需求。
- 存档格式、稳定ID、版本迁移和内容引用校验。
- 具体模块接口、会话生命周期与Autoload名单。

目录建议可以先确定；这些实现决策需要通过代表性原型验证后收敛。
