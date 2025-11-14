# Legacy 代碼存檔

**作者**：蔡秀吉（thc1006）

---

## ⚠️ 重要聲明

此目錄下的代碼**僅供參考**，不應用於生產部署。

### 為什麼保留這些代碼？

1. **學習參考**：了解早期實現方式
2. **問題排查**：比對新舊版本差異
3. **向後兼容**：保留歷史記錄

### 如何使用？

這些 legacy 代碼可以作為：
- 學習 O-RAN xApp 開發的參考
- 理解 E2SM-KPM 和 E2SM-RC 的實現方式
- 研究不同版本的差異

### 不應該做的事

- ❌ **不要部署這些代碼到生產環境**
- ❌ **不要修改這些代碼（它們已經凍結）**
- ❌ **不要將這些代碼與當前版本混用**

---

## 目錄說明

- `kpimon-go-xapp/` - KPIMON xApp 早期版本
- `rc-xapp/` - RAN Control xApp 早期版本
- `traffic-steering/` - Traffic Steering xApp 早期版本
- `kpm-xapp/` - KPM xApp 早期版本

---

## 需要部署 xApp？

請參考以下文檔：
- **快速開始**：[docs/QUICK-START.md](../docs/QUICK-START.md)
- **完整指南**：[docs/deployment-guide-complete.md](../docs/deployment-guide-complete.md)

---

**最後更新**：2025-11-14
