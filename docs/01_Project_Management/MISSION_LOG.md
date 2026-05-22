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
