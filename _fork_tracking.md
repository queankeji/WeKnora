# WeKnora Fork 跟踪文档（luyin 知识引擎）

> 本文档由 KB-M0-001 创建，是本 fork 与上游 Tencent/WeKnora 同步的**唯一事实来源**。
> 任何 rebase 操作前必读本文档；每次 rebase 后必须更新"上游版本记录"与"冲突热点清单"。

---

## 一、上游版本记录

| 项目 | 值 |
|---|---|
| fork 时间 | 2026-10（KB-M0-001） |
| 上游仓库 | https://github.com/Tencent/WeKnora |
| fork 仓库 | https://github.com/queankeji/WeKnora |
| fork 基线 commit | `e28c68cf5`（feat(background): shared background-work runtime (#4579)） |
| fork 基线 VERSION | `0.8.3`（VERSION 文件内容） |
| 本地工作仓库 | /Users/shi/Desktop/WeKnora（完整克隆，非 shallow） |

### rebase 历史记录（每次 rebase 追加一行）

| 日期 | rebase 前基线 | rebase 后基线 | 上游新版本号 | 冲突文件数 | 备注 |
|---|---|---|---|---|---|
| —（首次 fork，尚无 rebase） | — | e28c68cf5 | 0.8.3 | 0 | fork 起始点 |

---

## 二、Rebase 纪律

### 节奏：季度 rebase

- **固定节奏**：每季度执行一次 upstream rebase（对应任务 KB-M4-005 周期化后持续维护）。
- **触发式提前 rebase**：出现以下任一情况可提前：
  - 上游发布安全修复（关注 GitHub Security Advisory / SECURITY.md 更新）；
  - 上游发布了 fork 定制区依赖的能力（如新的多模态 embedding 接入点）；
  - 冲突热点清单积累超过 10 个文件（防止债务滚大）。
- **禁止**：超过两个季度不 rebase（冲突成本会非线性增长）。

### 标准流程（每次 rebase 必须执行）

1. **Ghost 分支备份（强制）**：
   ```bash
   git checkout main
   git branch backup/pre-rebase-<YYYYQn>-<旧基线短hash>   # ghost 备份分支，永不删除
   git fetch upstream
   git rebase upstream/main
   ```
   备份分支命名规范：`backup/pre-rebase-2027Q1-e28c68c`。rebase 失败时 `git rebase --abort` + `git reset --hard backup/...` 即可完整回退。
2. **冲突处理顺序**：先 `git rebase --abort` 试算冲突面（`git merge-tree` 或临时分支），冲突面过大（>20 文件）时暂停并评估是否值得跟进该版本。
3. **回归验证**：rebase 后必须跑通 fork 定制区测试 + `make build`（或上游 CI 对应命令）+ BFF 联调冒烟，全绿才允许推送 origin/main。
4. **更新本文档**：rebase 完成当日更新"rebase 历史记录"表与"冲突热点清单"。

### 冲突热点清单（维护约定）

- 每次冲突解决的文件**必须**登记到下方表格（路径 + 冲突原因 + 解决策略），作为下次 rebase 的预判依据。
- 初始为空——fork 起步阶段未修改上游任何文件，**首次 rebase 理论上零冲突**；一旦开始品牌剥离与定制改造，此表必须同步维护。

| 文件路径 | 冲突原因（哪类改动） | 解决策略 |
|---|---|---|
| `deploy-luyin/`（values-luyin.yaml / networkpolicy.yaml / README.md / model-setup.sh） | 纯新增目录，不触碰上游文件 | rebase 天然零冲突；仅当上游 helm values 键名变更时人工核对覆盖键是否仍有效 |
| `.env`（本地起栈用） | 不入库（上游 .gitignore 已排除） | 无冲突风险 |
| `frontend/public/favicon.ico`、`frontend/src/assets/img/weknora.png` | 二进制同名替换（A1/A3，都会美家品牌） | rebase 时二进制冲突直接取 ours；上游若换原图需评估是否保留我方品牌图 |
| `frontend/index.html` | title/keywords/description 字符串改动（A2） | 上游低频改动；冲突时保留我方 meta 块，合并上游脚本部分 |
| `config/builtin_agents.yaml` | 助手显示名改「都会美家助手」（A9，id 未动） | 上游低频改动；冲突时以功能配置为准、显示名取 ours |
| `frontend/src/views/auth/Login.vue` | 移除官网/GitHub header 外链、logo 链接中性化（A5） | **上游常改页面，冲突热点**；rebase 时重放"删外链块"语义而非照搬上下文 |
| `frontend/src/components/UserMenu.vue` | 移除 GitHub 菜单项及 openGithub（A6） | 上游常改组件，冲突热点；同上语义重放 |
| `frontend/src/views/settings/SystemInfo.vue` | 新增产品信息署名行（A7，「基于腾讯开源 WeKnora (MIT)」合规） | 我方为纯新增行，冲突概率低 |
| `frontend/src/utils/docsUrl.ts` | 仅注释变更，URL 保留（A8 决策：内部文档站就绪后单点替换） | 冲突概率极低 |
| （其余暂无——未修改上游其他文件） | — | — |

---

## 三、本 fork 定制区约定

> 核心原则：**定制扩展一律放独立模块目录，绝不修改上游核心文件**（规划文档 §四/§五 rebase 风险对策的落地）。

### 允许的定制方式（按优先级）

1. **独立模块目录（首选）**：
   - 商品库扩展（products/product_images 表、图查商品 API）→ 放 `internal/luyin/`（或上游认可的扩展点）独立包，Go module 内新目录对 rebase 是"仅新增"，天然零冲突。
   - 租户桥/认证适配 → 同样收敛到独立目录。
2. **配置/环境变量注入**：优先用上游既有配置机制（config 文件、模型目录自定义模型），不改代码。
3. **新增文件**：在前端/文档站新增文件冲突风险低；修改已有文件必须先登记冲突热点清单。

### 品牌剥离实施状态

- **A 区已于 2026-10-22 落地**（任务 #9，品牌名「都会美家知识库」，logo 方案 A·藏青金·书页屋形）：A1/A3 图片同名替换（favicon.ico 多尺寸 16/32/48/64 + weknora.png 400x126 同尺寸）、A2 index.html 标题/meta、A5 Login.vue 外链收敛、A6 UserMenu.vue GitHub 菜单移除、A7 SystemInfo.vue 署名行（MIT 合规）、A9 builtin_agents.yaml 助手名、A8 docsUrl.ts 仅注释（URL 暂指 WeKnora 官方文档，内部文档站就绪后单点替换）。i18n 复核零品牌字样（与清单结论一致）。全部触碰文件已登记上方冲突热点清单。
- 其余 A 区项（A2/A5-A9）在品牌资产到位后与 A1/A3 一并实施，届时逐项登记冲突热点清单。 ← 已完成，见上

### 禁止事项

- ❌ 直接修改上游核心文件（retriever/chunker/rerank/docreader/its server 核心逻辑）——需要上游能力时先评估"独立模块包裹调用"是否可行。
- ❌ 品牌剥离采用大改 HTML/CSS 的方式——遵循 `/Users/shi/Desktop/luyin/tmp/weknora_brand_checklist.md` 的最小改动建议，且每改一处必须登记冲突热点清单。
- ❌ 删除上游文件/目录（包括暂不用的 miniprogram、website-docs 等）——删除会让 rebase 产生 delete/modify 冲突；不用的目录留置即可，部署侧不打包。
- ❌ 在 main 分支直接开发——定制开发走 feature 分支，main 保持"上游镜像 + 已合入定制"。

### 分支模型

- `main`：始终等于 upstream/main + 已验证的定制提交（rebase 式推进）。
- `feature/*`：定制开发分支。
- `backup/pre-rebase-*`：ghost 备份分支，只增不删。

---

## 四、其他备忘

- 所有 git 网络操作走代理：`http_proxy=http://127.0.0.1:7897 https_proxy=http://127.0.0.1:7897`。
- 上游活跃度高（3,500+ commits，数周一版），rebase 前先 `git log upstream/main --oneline -20` 概览变更面。
- 品牌剥离清单（只调研不改码阶段的产出）：`/Users/shi/Desktop/luyin/tmp/weknora_brand_checklist.md`。
