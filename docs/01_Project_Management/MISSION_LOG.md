# 战报

### 2026-05-21 - 2604c39

- **已完成**：gold-price-bar 价格提醒功能迭代
  - 人民币/美元菜单栏币种切换，偏好持久化
  - 价格提醒：设定目标价 → 穿越触发 → 菜单栏文字闪烁 + Glass 提示音 + 面板横幅（含触发时间）
  - 未关闭时每 2 分钟重复提示音
  - 提醒历史记录，面板「历史」按钮可回溯，UserDefaults 持久化
  - 文件日志系统（`~/Library/Caches/com.goldprice.app/goldprice.log`），每秒记录价格
  - 中英文 README 更新，补全 4 份中文文档 + 2 张预览图

### 2026-05-22 - 475a956

- **已完成**：金价相关性分析系统（完整版）
  - 架构：DataSource 协议驱动 + SQLite 持久化 + SwiftUI 三栏 Dashboard
  - 数据源：黄金（Kitco+Yahoo）、白银（Kitco+Yahoo）、WTI 原油（Yahoo）、美元指数 DXY（FRED）、10Y 美债（FRED）、人民币汇率 USD/CNY（FRED）
  - 相关性引擎：皮尔逊相关系数（30D/90D/180D/1Y 四窗口），对数收益率，滚动 Beta，背离率
  - 渐进式回填：首批拉最近 90 天保证相关性立即可用，后续每 60 秒拉 90 天历史数据，UserDefaults 游标断电续传
  - UI：默认人民币显示，全界面中文化，菜单栏自动关闭，提醒布局优化，数据采集实时进度条
  - 零第三方依赖：SQLite 用系统 libsqlite3，Yahoo Finance v8 chart API，FRED API
  - 修复：sqlite3_bind_text SQLITE_TRANSIENT 防止数据丢失，回填游标避免实时数据干扰，金银历史改用 Yahoo 替代不可用的 FRED 黄金系列

### 2026-05-23 - e7e6be8

- **已完成**：
  - 图表提醒价位线：价格图表上以红色虚线（RuleMark）标出提醒目标价，Y 轴范围自动扩展以包含提醒线（菜单栏面板和详情窗口均已添加）
  - 菜单栏版本号显示：面板标题栏显示 `v1.0` 格式的 App 版本号，取自 `CFBundleShortVersionString`
  - 提醒已设提示：设定提醒价后菜单栏标题前显示 🔔 图标，让用户知道提醒处于活跃状态
  - 菜单栏面板布局优化：标题与版本号同行、副标题独立一行
  - 构建产物清理：删除仓库中的 `GoldPrice.dmg` 二进制文件
  - 代码整理：`GoldPriceApp.swift` 添加 MARK 分区注释、移除冗余注释

### 2026-06-05 — v1.0.5

- **已完成**：网络层修复
  - FRED API（汇率/DXY/美债）：绕过 Clash 代理解决 TLS 错误，`connectionProxyDictionary = [:]`
  - GUI 启动时 `FRED_API_KEY` 从 UserDefaults 兜底读取（环境变量为空时）
  - 数据源启动/回填错开延迟 5s，避免 FRED 并发 429 限流
  - Yahoo Finance（金/银/油）保持走代理，FRED 不走代理（相反需求）
  - 重试逻辑改为指数退避（10s/20s/40s），成功即恢复
  - HTTP 429/错误详情写入日志以便排查

- **已完成**：回填系统重构
  - 游标方向修正：从「往未来推」改为「往历史深处倒退」，`cursor = chunkFrom`
  - 回填上限从 20 年扩至 50 年（1976 年起）
  - 两阶段启动：先补齐近期缺口（30s 一轮），再继续历史回填
  - 各源数据极限：黄金/白银/原油 2000-08（Yahoo 极限），汇率 1981-01，DXY 2006-01，美债 1976-06（FRED 极限）

- **已完成**：详情页左侧行情卡片重构
  - 显示实时报价 + 🟢🟠 状态灯 + 数据起止时间（如 `2000/08 → 06/05`）
  - 点击卡片切换中间图表数据源（黄金/白银/原油/汇率/美元指数/10Y美债）
  - 选中卡片淡金色高亮

- **已完成**：图表功能增强
  - 纵坐标人民币/美元切换（仅黄金）
  - 时间范围选择器：实时/7天/30天/90天/1年/全部
  - 横坐标自适应：实时=HH:mm:ss，短周期=月/日，1年=月/年，全部=年份
  - 每种资产独立纵坐标格式（黄金$整数、白银$1位小数、汇率¥4位、美债%2位、DXY纯数值）

- **已完成**：相关性分析面板增强
  - 时间窗口选择（全部/30D/90D/180D/1Y）
  - 自定义起止日期 + 复选框开关 +「重新计算」按钮
  - 相关系数可视化强度条，NaN/inf 保护

- **已完成**：菜单栏铃铛 icon 替换为 macOS SF Symbol `bell.fill`
- **已完成**：版本迭代 1.0.1 → 1.0.5

### 2026-06-21

- **已完成**：修复日志系统递归死锁导致程序无法启动的严重 Bug
  - 根因：`Formatting.swift` 中 `logFile` 静态属性懒加载闭包内调用 `rotateIfNeeded()`，而 `rotateIfNeeded()` 又通过 `logFile?.closeFile()` 回访 `logFile`，形成递归 `dispatch_once`。macOS 26.5 的 libdispatch 检测到递归锁直接 `SIGTRAP` 杀死进程，导致程序双击无响应（连续 5 条崩溃日志均指向同一位置）
  - 修复：将 `rotateIfNeeded()` 从 `logFile` 初始化闭包中移除，改到 `ensureLogFile()` 开头调用，此时 `logFile` 已完成初始化，不再触发 `dispatch_once`
  - 构建产物管理：清理 `/Applications/` 中旧 Release 和 `DerivedData`/`build/` 下 3 个编译副产物，防止 Spotlight/Launchpad 扫描出多个 `GoldPrice.app` 混淆用户
  - 长效防护：在 `~/Library/Developer/Xcode/DerivedData/` 放置 `.metadata_never_index`，彻底阻止 Spotlight 扫描编译中间产物
