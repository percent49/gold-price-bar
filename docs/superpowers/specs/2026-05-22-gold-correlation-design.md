# 金价相关性分析系统 — 设计规范

> 日期：2026-05-22
> 状态：已确认，待实施

## 1. 目标

将 GoldPrice 从单一金价追踪工具升级为投资辅助工具。逐步引入与金价相关的多类金融数据源，计算并展示它们与金价的相关性，辅助用户判断市场走向。

核心原则：
- 只观察相关性，不做预测
- 免费 API，能拿多少频率就拿多少
- 逐步探索，一个一个加数据源
- 零第三方依赖（SQLite 用系统自带 libsqlite3）

## 2. 架构：3 层 + 协议驱动

```
数据源层（DataSource 协议）
    ↓
持久化层（SQLite，系统 libsqlite3）
    ↓
展示层（SwiftUI）
```

### 2.1 DataSource 协议

```swift
protocol DataSource: Sendable {
    var id: String { get }
    var name: String { get }
    var unit: String { get }
    var refreshInterval: TimeInterval { get }
    var enabled: Bool { get set }

    func fetchQuote() async throws -> DataSourceQuote
    func fetchHistory(from: Date, to: Date) async throws -> [DailyPricePoint]
}
```

### 2.2 通用数据模型

```swift
struct DataSourceQuote: Sendable {
    let price: Double
    let bid: Double?
    let ask: Double?
    let fetchedAt: Date
    let sourceUpdatedAt: Date?
    let sourceName: String
    let currency: String
}

struct DailyPricePoint: Sendable, Codable {
    let sourceID: String
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
}
```

## 3. 第一批数据源

| 数据源 | ID | 实时频率 | 实时来源 | 历史来源 |
|--------|-----|---------|---------|---------|
| 黄金 | gold | 1秒 | Kitco 网页解析 + Gold API 兜底 | FRED / Nasdaq Data Link |
| 白银 | silver | 1秒 | Kitco 白银页面 | MetalPrice API |
| 美元指数 | dxy | 5分钟 | FRED API (`DTWEXBGS`) | FRED API |
| 10Y 美债 | ust10y | 5分钟 | FRED API (`DGS10`) | FRED API |

FRED API Key: `558c939e2e3fd0ff4607c9c936cd4110`（存入 `.env`，不提交）

## 4. SQLite 持久化

### 4.1 数据库位置

`~/Library/Application Support/GoldPrice/data.db`

### 4.2 表结构

```sql
CREATE TABLE data_sources (
    id      TEXT PRIMARY KEY,
    name    TEXT NOT NULL,
    unit    TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE daily_prices (
    source_id TEXT NOT NULL REFERENCES data_sources(id),
    date      TEXT NOT NULL,
    open      REAL,
    high      REAL,
    low       REAL,
    close     REAL NOT NULL,
    volume    REAL,
    PRIMARY KEY (source_id, date)
);
```

### 4.3 DatabaseManager

Swift actor 保证线程安全。提供：`registerSource`、`upsertDailyPrice`（单条/批量）、按 source_id 和日期范围查询、`getLastDate` 用于增量判断。

### 4.4 导入策略

- 首次启动：每个数据源拉取 20 年日线，事务批量写入
- 后续启动：从 `getLastDate` 到昨天，增量拉取
- 运行时：收盘价确认后写入当日记录

## 5. 相关性计算

### 5.1 计算方法

- 皮尔逊相关系数，基于日收盘价的对数收益率：`r = ln(price_t / price_{t-1})`
- 4 个时间窗口：30天、90天、180天、1年
- 补充指标：滚动 Beta、背离天数占比

### 5.2 CorrelationEngine

Swift actor。核心方法 `compute(sourceA, sourceB, window) -> CorrelationResult`。日线数据更新后自动重算并刷新缓存。

### 5.3 性能

3 个目标数据源 × 4 个窗口，最长窗口 252 个数据点，完全重算 < 1ms。

## 6. UI 布局

### 6.1 菜单栏
保持现状，只显示金价。

### 6.2 下拉面板
新增：其他数据源价格行（金、银、DXY、US10Y 竖排）+ "相关性"入口按钮。

### 6.3 详情窗口（三栏式）
- 左栏（180px）：数据源列表，显示当前价和涨跌幅
- 中间（弹性）：走势图，可切换"单数据源走势"和"叠加对比"模式
- 右栏（260px）：相关性矩阵表 + 中文解读文字

### 6.4 叠加对比图
双 Y 轴，黄金固定左轴，选中数据源右轴。走势背离时高亮标注。

## 7. 数据流

```
DataSource.refreshInterval → fetchQuote() → @Published quotes → UI 更新
当日收盘确认 → DatabaseManager.upsertDailyPrice() → CorrelationEngine.invalidateCache() → 相关性矩阵更新
```

## 8. 错误处理

- 实时轮询失败：静默重试 3 次（间隔递增），超限显示 `--`，不影响其他数据源
- 历史导入失败：记日志，跳过该数据源，不阻塞启动
- SQLite 写入失败：记日志，内存数据继续工作

## 9. 刷新频率

| 数据源 | 轮询间隔 | 说明 |
|--------|---------|------|
| 黄金 | 1秒 | 保持现有 |
| 白银 | 1秒 | 同 Kitco 解析 |
| DXY | 5分钟 | FRED，交易时段更新 |
| US10Y | 5分钟 | FRED，交易时段更新 |

各数据源独立轮询，互不影响。
