# 书声 · 英语学习 App

一款自用的原生 iOS 英语学习 App：以「英语电子书 + 系统 TTS 按句朗读」为核心，串起查词、生词本、间隔复习、跟读评分、AI 情景对话与学习打卡，视觉风格参考百词斩（暖橙色、卡片化）。

> 当前阶段：**V2 完成**（2026-11-10）。全部功能已在 iPhone 真机与模拟器验证。

## 截图

| 书库 | 朗读与高亮 | 夜间模式 |
| :---: | :---: | :---: |
| ![书库](docs/screenshots/library_with_mobi.png) | ![朗读](docs/screenshots/reader_highlight.png) | ![夜间](docs/screenshots/reader_night.png) |

| 目录跟随 | 我的标记 | 阅读设置 |
| :---: | :---: | :---: |
| ![目录](docs/screenshots/toc_follow.png) | ![标记](docs/screenshots/marks_panel.png) | ![设置](docs/screenshots/settings_speed_voice.png) |

## 功能清单（当前阶段）

### 1. 书库与导入

- 支持格式：TXT、EPUB、MOBI / PRC（含 PalmDOC 压缩）
- 多种导入方式：文件 App 选择、微信「用其他应用打开」、隔空投送、直接放入 App 的 Documents（自动收纳）
- 书籍左滑或长按删除，同时清理进度、书签与高亮

### 2. 阅读与朗读

- 按句朗读（系统端侧 TTS），当前句高亮并自动滚动
- 点击任意句子从该句开始朗读，自动记住上次位置续读
- 上一句 / 下一句、可拖动句进度条、单句循环
- 睡眠定时（15 / 30 / 60 分钟），到点停止并保留进度
- 章节目录：EPUB 层级目录（toc.ncx / nav.xhtml）、TXT 按「Chapter / 第 X 章」正则识别；当前章实时跟随、点击跳转并继续播放
- 书签、文字高亮与「我的标记」面板（分书签/高亮两栏，可跳转、滑动删除）
- 阅读设置：字号（小/中/大/特大）、背景（白纸/米黄/夜间）、朗读语速、中英文朗读声音
- 中英双语书籍按句自动切换中/英文发音
- 锁屏、控制中心、耳机线控控制播放；锁屏显示书名与进度

### 3. 单词与复习

- 阅读中长按选中文字即可「加入生词本」，自动取原句，去重
- 联网查词：有道词典 + dictionaryapi.dev 兜底，展示音标、中文/英文释义、双语例句，结果本地缓存
- 生词本列表、系统词典兜底
- 百词斩式复习卡：翻面查看原句与释义，三档自评（不认识 / 模糊 / 认识），间隔 12h / 1d / 2d / 4d / 7d / 15d / 30d

### 4. 口语练习

- 跟读评分：系统语音识别 + 编辑距离比对，逐词绿/橙/红标记，0–100 分
- 素材来自当前阅读句，或内置示例句
- AI 情景对话：日常 / 咖啡店 / 机场 / 酒店 / 面试五个场景，自动朗读回复、可随时插话、中文纠错点评
- AI 引擎：DeepSeek / GLM（智谱）在线模型可切换，Key 仅存本机；iOS 26+ 且设备支持时可回退端侧 Apple Intelligence

### 5. 学习统计

- 连续打卡天数、累计活跃天数
- 跟读次数 / 复习卡片 / 朗读句数 / 对话轮数统计
- 近 16 周学习热力图

## 技术栈

- SwiftUI（iOS 17+），XcodeGen 管理工程
- AVSpeechSynthesizer（朗读）、SFSpeechRecognizer（跟读识别）、AVAudioEngine
- MediaPlayer（锁屏与控制中心）
- 自研 TXT / EPUB / MOBI 解析器；EPUB 解压使用 ZIPFoundation
- FoundationModels（端侧 AI，可选）与 OpenAI 兼容在线接口
- 本地持久化：Documents 下的 JSON 文件 + UserDefaults，无账号、无云端

## 构建与安装

需要 macOS + Xcode、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
xcodegen generate
open EnglishReader.xcodeproj
```

命令行构建示例（模拟器）：

```bash
xcodebuild -project EnglishReader.xcodeproj -scheme EnglishReader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

真机安装（免费 Personal Team 需替换为你自己的 Team ID）：

```bash
xcodebuild -project EnglishReader.xcodeproj -scheme EnglishReader \
  -destination 'platform=iOS,id=<设备 UDID>' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=<TEAM_ID> build
xcrun devicectl device install app --device <设备 UDID> <App 路径>
```

> 免费签名 7 天过期，过期后重新构建安装即可。

## 已知限制

- 不支持 DRM 加密书籍；不支持 AZW3 / KF8
- MOBI 仅提取纯文本（不显示图片），EPUB 暂不渲染原书 CSS 与插图
- 所有数据仅保存在本机，换机不迁移
- AI 对话需要配置在线模型 Key，且需要网络

## 后续优化计划

### P0 · 阅读体验补全

- [ ] 书内搜索（按章节/全书，结果跳转）
- [ ] 封面提取与网格书库视图
- [ ] EPUB 图片与基础样式渲染
- [ ] AZW3 / KF8 格式支持
- [ ] PDF 阅读支持

### P1 · 学习闭环打磨

- [ ] 复习算法升级为 SM-2，动态调整间隔
- [ ] 生词本按书分组、标签与筛选
- [ ] 内置离线词库，查词不再依赖网络
- [ ] 跟读历史趋势、常见错词统计与专项练习
- [ ] 统计目标设置（每日句数 / 复习数提醒）

### P2 · AI 与体验

- [ ] AI 对话流式输出，降低等待感
- [ ] 纯语音双向对话模式（免手动点按）
- [ ] 自定义情景与难度（CEFR A1–C1）
- [ ] 全局深色模式与 iPad 适配
- [ ] 单元测试与 CI 构建

### 远期（可选）

- [ ] iCloud 同步与多设备接续
- [ ] 书源/书城与多语言支持
- [ ] 朗读音色增强与角色对话朗读
