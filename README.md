# OpenOcta Skills

本仓库用于汇集 **OpenOcta** 生态下的第三方技能（Skill）：把你在 **真实工作场景里沉淀下来的排查套路、运维手册、最佳实践** 整理成可被 Agent 加载执行的说明与参考资料，便于社区复用与迭代。

## 我们在征集什么

我们特别欢迎基于「真实踩坑与日常运维」写成的 Skill，例如：

- 典型故障如何定位、看什么指标、执行哪些安全命令；
- 平台/组件的常见配置范式与禁区（含变更前的检查清单）；
- 与你们内部规范对齐的操作边界（哪些必须人工审批、哪些禁止自动化）。

**第一期优先征集主题**见目录 [`wanted-phase1/`](wanted-phase1/README.md)（Kubernetes、Prometheus、Zabbix 等占位示例）。你可以 **先从对应占位目录复制到仓库根目录**，补全内容后提交 Pull Request。

后续我们会在公开致谢或索引中 **记录你的提交**；请务必在 `mate.json` 中填写 **作者与所属（单位/团队/个人均可）**，便于归档与引用。

## 目录约定

| 路径 | 说明 |
|------|------|
| 仓库根目录下 **每个顶级子目录**（如 `k8s_skill/`） | 通常对应一个可独立分发、打包的技能包。 |
| [`template/`](template/) | 通用脚手架；复制后改名即可从零编写。 |
| [`wanted-phase1/`](wanted-phase1/) | **第一期征集占位**：内含若干主题子目录，仅供复制到根目录后完善，**不参与** `build_zip.sh all` 打包。 |

每个技能目录建议至少包含：

- **`SKILL.md`**：Agent 读取的核心说明（触发场景、步骤、约束）。
- **`README.md`**：面向贡献者与审阅者的概述、示例、依赖、变更说明。
- **`mate.json`**：**必填作者与所属信息**（见下），便于登记与检索。

可选：`references/`（长文档）、`scripts/`（辅助脚本）、`resource/`（图标、示例配置片段等）。

## 快速开始（两种方式）

### 方式 A：从第一期占位目录复制（推荐对应主题）

适合 Kubernetes / Prometheus / Zabbix 等第一期方向的贡献者：

```bash
cp -R wanted-phase1/k8s_skill ./my_k8s_skill   # 示例：也可用 prometheus_skill、zabbix_skill
# 将目录改名为你希望发布的名称，编辑 SKILL.md / README.md / mate.json 后提 PR
```

详主题列表与说明见 [`wanted-phase1/README.md`](wanted-phase1/README.md)。

### 方式 B：从通用模版复制

```bash
cp -R template my_skill
```

字段与编写要点见 [`template/README.md`](template/README.md)。

## `mate.json` 与提交归属

提交 PR 前请在 `mate.json` 中写明 **归属信息**（我们会用于致谢与索引），建议至少包含：

- **`author`**：作者昵称或姓名；
- **`affiliation`**：所属公司 / 团队 / 填「个人」亦可；
- **`email`**（可选）：便于维护者联系；
- **`keywords`**：便于搜索的标签（如 `kubernetes`、`observability`）。

字段示例见各占位目录或 [`template/mate.json`](template/mate.json)。

## 打包自检：`build_zip.sh`

```bash
chmod +x build_zip.sh   # 首次使用
./build_zip.sh --help
```

| 命令 | 说明 |
|------|------|
| `./build_zip.sh <目录名>` | 将根目录下 `<目录名>/` 打成 `dist/<目录名>.zip` |
| `./build_zip.sh all` | 为每个**可打包**技能目录生成 zip，再打成外层 `dist/openocta-skills-all-*.tar.gz` |

`all` 会跳过 `template/`、`wanted-phase1/`、`dist/` 及以 `.` 开头的目录。

## 贡献流程（建议）

1. Fork 本仓库并从 `main` 拉出分支。
2. 使用 `wanted-phase1/*` 或 `template/` 复制出新目录并完成内容与自检。
3. 填写 `mate.json` 中的 **author / affiliation** 等归属字段。
4. 执行 `./build_zip.sh <你的目录名>` 确认可打包（可选但推荐）。
5. 提交 Pull Request，并在描述中简要说明：**适用场景、依赖环境（若有）、是否含生产操作建议**。

## 许可证

各技能目录可自带许可证说明；若未特别声明，以仓库根目录许可证为准（若有）。
