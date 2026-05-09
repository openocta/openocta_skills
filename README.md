# OpenOcta Skills

本仓库用于汇集第三方贡献的 **OpenOcta** 技能（Skill）资源，便于分享、版本管理与分发。

## 目录约定

- 仓库根目录下的 **每一个顶级子目录** 通常对应一个可独立打包的技能包。
- **`template/`** 是官方脚手架目录，用于快速新建技能，**不参与**「一键全量打包」中的技能列表（见下文脚本说明）。
- 技能目录内建议至少包含：
  - **`SKILL.md`**：供 Agent 读取的核心说明（触发场景、执行步骤、约束等）。
  - **`README.md`**：面向贡献者的说明（安装、示例、变更记录等）。
  - **`mate.json`**（可选）：技能的元数据（名称、版本、描述等），便于平台索引。

## 使用模版快速创建技能

1. 复制模版目录并改名为你的技能名（建议使用小写字母、数字与下划线，例如 `my_skill`）：

   ```bash
   cp -R template my_skill
   ```

2. 进入新目录，按需修改：
   - `SKILL.md`：替换占位内容为真实指令与触发说明。
   - `README.md`：写给人看的介绍与示例。
   - `mate.json`：填写名称、版本、描述等信息。
   - `references/`、`scripts/`：按需增删参考文档或辅助脚本。
   - `scripts/`：可添加辅助脚本，如 `scripts/prepare.sh` 用于准备技能运行环境。
   - `resource/`：可添加辅助需要的资源内容，如 `resource/logo.png` ， `resource/xx.js`

3. 本地自测无误后，向本仓库提交 Pull Request。

更细的字段说明见 [`template/README.md`](template/README.md)。

## 打包分发：`build_zip.sh`

仓库提供 `build_zip.sh`，用于将单个技能目录打成 zip，或在 `all` 模式下为每个技能分别打 zip，再把所有 zip **二次打包**成一个外层压缩包（便于一次性分发）。

```bash
chmod +x build_zip.sh   # 首次使用
./build_zip.sh --help
```

### 常用示例

| 命令 | 说明 |
|------|------|
| `./build_zip.sh k8s_skill` | 将 `k8s_skill/` 打成 `dist/k8s_skill.zip` |
| `./build_zip.sh all` | 为每个技能目录生成独立 zip，再生成外层 `dist/openocta-skills-all-YYYYMMDD-HHMMSS.tar.gz`，内含上述所有 zip |

默认输出目录为 **`dist/`**（若不存在会自动创建）。`all` 模式会跳过模版目录 `template/`、输出目录 `dist/` 以及以 `.` 开头的隐藏目录。

## 贡献流程（建议）

1. Fork 本仓库并从 `main` 拉出分支。
2. 使用 `template/` 复制出新技能目录并完成内容与自测。
3. 运行 `./build_zip.sh <你的目录名>` 确认打包结果符合预期。
4. 提交 PR，并在描述中说明技能用途与依赖环境（若有）。

## 许可证

各技能目录可自带许可证说明；若未特别声明，以仓库根目录许可证为准。
