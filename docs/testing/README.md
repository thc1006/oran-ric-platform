# Shell 脚本测试策略文档索引

**作者**: 蔡秀吉 (thc1006)
**评估日期**: 2025-11-17

---

## 快速导航

### 想快速了解结论？
👉 阅读 [**执行摘要**](./EXECUTIVE-SUMMARY.md) (4 KB, 5 分钟阅读)

### 想了解详细评估？
👉 阅读 [**BATS 测试评估报告**](./BATS-TESTING-EVALUATION.md) (15 KB, 20 分钟阅读)

### 想知道如何改进脚本质量？
👉 阅读 [**Shell 脚本质量保证指南**](./SHELL-SCRIPT-QUALITY-GUIDE.md) (11 KB, 15 分钟阅读)

### 想执行改进措施？
👉 阅读 [**行动计划**](./ACTION-PLAN-SHELL-QUALITY.md) (11 KB, 15 分钟阅读)

---

## 文档清单

| 文档 | 大小 | 用途 | 受众 |
|------|------|------|------|
| [EXECUTIVE-SUMMARY.md](./EXECUTIVE-SUMMARY.md) | 4 KB | 决策参考 | 项目负责人 |
| [BATS-TESTING-EVALUATION.md](./BATS-TESTING-EVALUATION.md) | 15 KB | 详细分析 | 技术评审者 |
| [SHELL-SCRIPT-QUALITY-GUIDE.md](./SHELL-SCRIPT-QUALITY-GUIDE.md) | 11 KB | 实施指南 | 开发者 |
| [ACTION-PLAN-SHELL-QUALITY.md](./ACTION-PLAN-SHELL-QUALITY.md) | 11 KB | 执行计划 | 开发团队 |

---

## 工具清单

| 文件 | 大小 | 用途 |
|------|------|------|
| `/scripts/smoke-test.sh` | 5.5 KB | 部署后快速健康检查 |
| `/scripts/lib/validation.sh` | 9.9 KB | 通用验证函数库 |
| `/.shellcheckrc` | 845 B | ShellCheck 配置 |
| `/scripts/hooks/pre-commit.sample` | TBD | Git pre-commit hook 范例 |

---

## 核心结论

### ❌ 不建议引入 BATS 测试框架

**原因**:
- 投资成本高 (20-36 小时)
- 只能防止 20% 的实际问题（语法错误）
- 过去 6 个月的 11 次修复都是路径/配置问题

### ✅ 推荐替代方案

**四层防护体系**:
1. **ShellCheck** (静态) → 捕获语法错误
2. **Smoke Test** (快速) → 验证部署结果
3. **E2E Test** (完整) → 全流程测试
4. **文档测试** (真实) → 用户体验

**投资**: 7-11 小时 | **收益**: 防止 80% 问题

---

## 立即开始（10 分钟）

### 1. 安装 ShellCheck

```bash
sudo apt install shellcheck
```

### 2. 启用 Git Hook

```bash
cp scripts/hooks/pre-commit.sample .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### 3. 测试 Smoke Test

```bash
sudo bash scripts/smoke-test.sh
```

### 4. 检查关键脚本

```bash
shellcheck scripts/deployment/setup-k3s.sh
shellcheck scripts/deployment/deploy-all.sh
shellcheck scripts/deployment/deploy-ric-platform.sh
```

---

## 关键发现

### 脚本现状分析

```
脚本总数:     11 个
总代码行:     3,116 行
关键脚本:     3 个 (setup-k3s, deploy-all, deploy-ric-platform)
```

### 过去 6 个月问题类型

```
语法错误:     0 次 (0%)  ← BATS 主要防护目标
路径硬编码:   5 次 (45%) ← 需静态分析
资源配置:     4 次 (36%) ← 需集成测试
文档不一致:   2 次 (18%) ← 需文档测试
```

### ROI 对比

| 方案 | 投资 | 防止问题 | ROI |
|------|------|---------|-----|
| BATS 单元测试 | 20-36h | 20% | ⭐ 低 |
| ShellCheck | 1-2h | 20% | ⭐⭐⭐⭐⭐ 极高 |
| Smoke Test | 4-6h | 60% | ⭐⭐⭐⭐⭐ 极高 |
| E2E 测试 | 已有 | 80% | ⭐⭐⭐⭐⭐ 极高 |
| 文档测试 | 已有 | 100% | ⭐⭐⭐⭐⭐ 极高 |

---

## 使用场景

### 场景 1: 我要修改部署脚本

1. 阅读 [质量保证指南](./SHELL-SCRIPT-QUALITY-GUIDE.md) 的 "Shell 脚本模板" 章节
2. 使用 `scripts/lib/validation.sh` 中的验证函数
3. 本地运行 `shellcheck` 检查
4. Commit 时 Git hook 会自动检查

### 场景 2: 我要验证部署结果

```bash
# 部署完成后运行
sudo bash scripts/smoke-test.sh
```

### 场景 3: 我是项目负责人，要决策是否引入 BATS

阅读 [执行摘要](./EXECUTIVE-SUMMARY.md)，**建议决策：不引入 BATS**

### 场景 4: 我要改进现有脚本

按照 [行动计划](./ACTION-PLAN-SHELL-QUALITY.md) 的优先级：
- **P0**: setup-k3s.sh, deploy-all.sh, deploy-ric-platform.sh
- **P1**: redeploy-xapps-with-metrics.sh, deploy-ml-xapps.sh
- **P2**: 其他工具脚本

---

## 预期效果（1 个月后）

| 指标 | 当前 | 目标 |
|------|------|------|
| ShellCheck 零警告脚本 | 0% | 80% |
| 部署成功率 | TBD | 95% |
| 脚本 bug/月 | ~4 | <2 |
| Smoke Test 通过率 | N/A | 100% |

---

## 何时重新考虑 BATS

### 触发条件

✅ 当满足以下**全部**条件时：
1. 脚本逻辑复杂度显著增加（如复杂 JSON/YAML 解析）
2. 语法错误成为主要问题（连续 3+ 次）
3. 需支持多种 OS/发行版变体
4. 有专门的 DevOps 团队维护脚本

**当前状态**: 均未满足

---

## 维护计划

### 每周回顾（15 分钟）
- 检查本周脚本相关 commit
- 记录新问题到 TROUBLESHOOTING.md
- 更新 smoke-test.sh（如有新服务）

### 每月回顾（1 小时）
- 统计脚本 bug 修复次数
- 评估 smoke test 覆盖率
- 更新验证函数库

### 每季回顾（2 小时）
- 评估质量改进效果
- 决定是否需要新工具
- 更新最佳实践文档

---

## 相关资源

### 项目文档
- [E2E 测试报告](../E2E_TESTING_REPORT.md)
- [故障排除指南](../deployment/TROUBLESHOOTING.md)
- [部署问题日志](../../DEPLOYMENT_ISSUES_LOG.md)

### 外部参考
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [Bash Strict Mode](http://redsymbol.net/articles/unofficial-bash-strict-mode/)

---

## 反馈与改进

如有问题或建议，请：
1. 创建 GitHub Issue
2. 联系维护者：蔡秀吉 (thc1006)
3. 更新本文档并提交 PR

---

**维护者**: 蔡秀吉 (thc1006)
**最后更新**: 2025-11-17
**下次回顾**: 2025-12-17
