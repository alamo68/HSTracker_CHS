# CHS 改动维护笔记

这份文档记录本仓库相对官方 HSTracker 的**全部改动**，供下次同步官方版本时参考。

本仓库不是把官方代码 merge 进来，而是反过来：**以官方某个 release tag 为基线，把本仓库的改动重新带上去**。
每次同步都要走一遍下面的"同步流程"，逐项核对改动清单，否则很容易像 3.6.9 → 3.6.10 那次一样把补丁弄丢
（当时漏掉了 `Game.swift` 的重连修复，导致拔线后 Bob's Buddy 与右侧战绩面板不再出现、当次回合记牌丢失）。

## 当前基线

| 项目 | 值 |
|---|---|
| 官方基线 | `3.6.13`（upstream tag） |
| 本地分支 | `sync-3.6.13`（最新提交见 `git log -1`，别在文档里写死 SHA） |
| 远端 | `origin` = `alamo68/HSTracker_CHS`（发布用）、`upstream` = `HearthSim/HSTracker` |
| 与官方的差异 | 12 个文件（含本文件），见下方清单 |

检查差异是否只有"该有的那些"：

```bash
git fetch upstream --tags
git diff --stat <官方tag> HEAD
git diff --diff-filter=D --name-only <官方tag> HEAD   # 应当为空：绝不删除官方文件
```

## 改动清单

分类代号沿用日常沟通里的叫法：**A** 禁用随从面板、**B** 一键拔线、**C** 拔线/重连修复、**D** 中文文本、**E** 其他。

| 文件 | 类别 | 规模 | 说明 |
|---|---|---|---|
| `HSTracker/DisabledRacesPanel.swift` | A | 新增 400 行 | 左上角合并面板（一键拔线 + 禁用种族） |
| `HSTracker/ClashSkipper.swift` | B | 新增 473 行 | 拔线功能本体 |
| `HSTracker/Logging/Game.swift` | C | +60 / −2 | 重连修复，共 4 处 |
| `HSTracker/AppDelegate.swift` | A+B | +19 | 挂接两个控制器、Dock 菜单、`performClashSkip()` |
| `HSTracker.xcodeproj/project.pbxproj` | A+B | +8 | 登记两个新文件 |
| `Translations/macOS/Localizable.xcstrings` | D | +13 / −1 | 新种族中文名 |
| `HSTracker/UIs/Battlegrounds/BattlegroundsMinionView.swift` | E | +32 / −12 | 四位数属性值不再截断 |
| `README.md` | E | +163 / −29 | 使用文档 |
| `docs/images/*.jpg` | E | 3 个新文件 | 文档截图 |
| `docs/CHS-MAINTENANCE.md` | E | 本文件 | 维护笔记 |

### A：禁用随从面板

**`HSTracker/DisabledRacesPanel.swift`（全部为新增文件，可整文件搬）**

左上角一条面板：绿色「一键拔线」+ 白色「禁用：种族」，样式对齐 Bob's Buddy。要点：

- **高度 30、字号 14、上下不留白**：与 Bob's Buddy 底部状态栏同高同字号；按钮高度 = 行高，撑满整行（整行可点，文字居中）。高度是按 `RootOverlayView` 的 **1080 参考画布**等比缩放的，和 Bob's Buddy 同一套算法。
- **缩放比显式传入**：`contentView.scale` 由控制者写入，**不要**再从 `bounds.height / referenceHeight` 反推——那种写法下一改高度字号就跟着变。
- **吸顶**：上沿贴炉石窗口的**真实顶边**（`SizeHelper.hearthstoneWindow._frame.maxY`）。`SizeHelper` 对外暴露的 `frame` 在非全屏时会减掉标题栏高度，用它会让面板低约 28pt。
- **越过菜单栏**：`TopLeftPanel` 覆写了 `constrainFrameRect(_:to:)` 原样返回请求矩形，否则系统会把窗口压到菜单栏下方，看起来就是没吸顶。
- **显示条件**（`poll()` 每 0.3s 判断一次，状态变化时才写日志）：客户端进程还在 → 前台是炉石或 HSTracker 自己 → `currentMode == .gameplay`。前两条都是**实时查询**，不能改用 `game.isRunning` 这类由通知维护的标志，也不能依赖 `currentMode` 或缓存的窗口矩形——炉石退出后这两者都会停留在对局状态。
- **日志**：`[DisabledRacesPanel] shown: frame=… top=… height=… actual=… screens=…`。`actual` 是窗口服务器最终给到的位置，排查吸顶问题就看它（`actual.y + height` 应等于屏幕高度）。

### B：一键拔线

**`HSTracker/ClashSkipper.swift`（全部为新增文件，可整文件搬）**

通过 Clash/mihomo 的 external controller 断开炉石对局连接，**不误杀 Battle.net 会话**。要点：

- 只匹配进程路径以 `Hearthstone.app/Contents/MacOS/Hearthstone` 结尾、host 为空的连接，优先端口 `1119`。
- 依赖 Clash Verge 的 **TUN 模式** + 全局覆写里的 `find-process-mode: always`，否则 connections 接口拿不到进程信息。
- 入口有三个：左上角面板按钮、菜单栏「拔线 → 一键拔线」（⇧⌘K）、Dock 右键菜单。
- 配置项存在 `UserDefaults`：`clash_external_controller`、`clash_secret`。
- **早期独立悬浮按钮那段死代码已删除**（2026-09-28）：`ClashSkipFloatingButtonController`、`ClashSkipButtonView`、配套的 `ClashSkipOverlayPanel` 和 `clashHearthstoneBundleIdentifier` 常量，共约 248 行。它们来自合并进 HSTracker 之前的独立 App，从来没有任何地方实例化（xib/storyboard/动态构造都没有），只是同步时被一起搬了过来——现在左上角那个合并面板才是唯一的拔线入口。
  **同步时注意**：cherry-pick 早期的 CHS 提交（`sync-3.6.10` 那条线的 A+B 提交）会把这 248 行带回来，直接删掉即可，功能不受影响。判断依据可复核：全仓库搜 `ClashSkipFloatingButtonController`，只应出现在 `ClashSkipper.swift` 自己的声明处。

**`HSTracker/AppDelegate.swift`（+19 行，4 处）**：属性声明两个控制器、`applicationDidFinishLaunching` 里实例化并互相绑定、Dock 菜单里 `installDockMenu`、`performClashSkip()`。

**`HSTracker.xcodeproj/project.pbxproj`（+8 行）**：把上面两个新文件登记进 target。**这里最容易在同步时丢**，官方每次大改工程文件都要重新核对。

### C：拔线/重连修复（`HSTracker/Logging/Game.swift`，4 处）

这 4 处是一套，缺一个就会出现"拔线后面板不回来 / 记牌丢失 / 对手棋盘变空"：

1. `updateBobsBuddyOverlay()`：`leftViaScene` 增加 `&& self.isInMenu`。拔线重连时场景会短暂停在 `bacon`，旧逻辑误判为已离开对局，面板被隐藏且不再回来。
2. `handleGameReconnect()`：补回 `gameEnded / isInMenu / handledGameEnd`，重新从 HearthMirror 同步对局类型与玩家 ID（对手 ID 常为 -1，会从日志的 `PlayerID=xx, PlayerName=xxx` 反查），最后强制 `updateAllTrackers()` 重刷窗口状态，并打印 `Reconnect sync: …`。
3. `reset()`：**移除** `_battlegroundsBoardState?.reset()`（否则重连后对手棋盘变空）。
4. `handleEndGame()` / `inMenu()`：改到真正的对局结束时才清棋盘快照。

> ⚠️ **已知冲突点**：第 3 处删掉的那一行，官方 3.6.12 不仅保留，还在同一位置**新增**了 `_battlegroundsDeityState?.reset()`。合并时正确解法是**保留神明那行、只去掉棋盘那行**：
>
> ```swift
>         _brawlInfo = nil
>         _battlegroundsDeityState?.reset()      // 保留上游新增
>         _battlegroundsHeroPickStatsParams = nil
> ```

另外留意：官方 3.6.12 引入了"神明"（Deity）机制，`_battlegroundsDeityState` 同样在 `reset()` 里被清空。按目前的最小改动策略我们**没有**动它，如果实战发现拔线后"上一个见过的神明"丢失，用与第 3、4 处相同的思路处理。

### D：中文文本

**`Translations/macOS/Localizable.xcstrings`**：给 `aberration` 补 `zh-Hans: 畸变怪`、`zh-Hant: 畸變怪`。

酒馆战棋新增的第 12 个种族，卡牌数据 `CARDRACE = 126` / `Race.aberration`，官方中文译名"畸变怪"。官方只给了英文条目，不补的话左上角面板和随从浏览器会显示生 key。

> 历史上 3.6.9 时代还有一份 **Bob's Buddy 汉化补丁**（`BobsBuddyPanel.xib` + 约 60 条字符串），**从 3.6.10 起已被官方自带中文取代，本仓库不再保留**，不要在这份清单里找它。

### E：其他

**`HSTracker/UIs/Battlegrounds/BattlegroundsMinionView.swift`（+32 / −12）**：`drawText` 按框宽自动缩字号并重新居中。原本攻击/血量画在固定 90pt 宽的框里、字号写死 45pt，只放得下三位数（实测 `139` = 73pt，`1814` = 96pt），酒馆后期随从上千就会被截断，看起来像几个回合前的旧数值。这个视图同时被**对手悬浮面板**和**战绩面板的终盘 tooltip** 使用，一处修好两处生效。

> 官方 3.6.12 改过同一文件（引入 `BattlegroundsMinionDisplay`，把 `entity` 换成 `display`），但**没有碰 `drawText`**，所以这个修复仍然必要；两边改动不重叠，实测可自动合并。

**`README.md` + `docs/images/`**：本仓库的使用文档与截图，官方未动，可整文件覆盖。

## 同步官方新版本的流程

```bash
GIT=/path/to/git          # 见"环境备忘"
cd <repo>

# 1. 取官方最新 tag
$GIT fetch upstream --tags
$GIT tag | grep -E '^3\.6\.' | sort -V | tail -3

# 2. 以官方新 tag 为基线开分支
$GIT checkout -b sync-<新版本> <新tag>

# 3. 把上一版 CHS 分支的提交按原顺序带过来（feature 在前，修复在后）。
#    每次同步都会重写这些提交，所以 SHA 每版都不一样 —— 用命令列出来，
#    别照抄文档/聊天里的旧 SHA（照抄 3.6.12 那次的 SHA 会把文档里已修正的
#    数字又带回来一次，这次就踩到了）。
$GIT log --oneline --reverse <上一版基线tag> <上一版CHS分支>
# 例如本次：
#   $GIT log --oneline --reverse 3.6.12 master
# 然后逐个带过来：
$GIT cherry-pick -x <sha>      # 顺序照上面列出的来
# 各提交大致对应：
#   面板与拔线（A+B）→ 重连修复（C，冲突点见上文）→ 面板尺寸/吸顶 →
#   四位数不截断（E）→ 畸变怪中文名（D）→ 退出后隐藏 → 后台隐藏 →
#   越过菜单栏吸顶 → 高度 30 且上下不留白

# 4. 核对差异：应当只有改动清单里那些文件，且没有任何删除
$GIT diff --stat <新tag> HEAD
$GIT diff --diff-filter=D --name-only <新tag> HEAD
```

> 想少走一步的话，`abf97afc` 与 `b5d21245` 都是面板高度调整，直接取后者即可。

## 编译与安装

```bash
cd <repo>
PATH=<workspace>/work/tools/bin:$PATH \
CLANG_MODULE_CACHE_PATH=/tmp/clang-cache \
SWIFT_MODULECACHE_PATH=/tmp/clang-cache \
xcodebuild -project HSTracker.xcodeproj -scheme HSTracker -configuration Release \
  -derivedDataPath <derived> \
  CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 \
  OTHER_SWIFT_FLAGS='-disable-sandbox -enable-experimental-feature BuiltinModule' build

# 签名（ad-hoc）并打包
codesign --force --deep --sign - --options runtime \
  --entitlements HSTracker/HSTracker.entitlements <HSTracker.app>
ditto -c -k --keepParent <HSTracker.app> HSTracker-CHS-<版本>-macos-universal.zip
```

**环境备忘**

- `CLANG_MODULE_CACHE_PATH` 必不可少：`Compile CardDefs` 阶段要现场编译 `CardDefsCompiler`，默认的 clang 模块缓存目录在受保护路径下会报 `Operation not permitted`。
- 构建脚本会联网下载依赖：`libs.hearthsim.net`（HearthMirror、BobsBuddy、HearthDb）和 GitHub 的 `HearthSim/hsdata`（CardDefs.xml 等三份）。**CardDefs 的下载脚本用 `curl -z` 按时间戳判断，换版本时一定要先删掉本地缓存的那三份 xml**，否则会继续沿用旧版本的卡牌数据。
- **HearthMirror 的新版本 CDN 常常还没发布**：脚本按 `HSTracker/HearthMirror-version.txt` 的 sha 去 `libs.hearthsim.net/hstracker/<sha>/HearthMirror.framework.zip` 下载，官方刚发版时这个 zip 往往是 404（3.6.13 就是），而**官方 release 的应用包里那份 framework 被剥掉了 Headers/Modules，编译用不了**（会报 `Unable to resolve module dependency: 'HearthMirror'`）。处理办法：
  1. 从官方 release 的 `HSTracker.app.zip` 取出 `Contents/Frameworks/HearthMirror.framework`；
  2. 再从 CDN 下载**上一个 sha** 的 zip，得到带 `Headers/Modules` 的骨架，把新二进制覆盖到 `Versions/A/HearthMirror`（连带 `Resources`）；
  3. 用 `otool -ov <二进制>` 读新版本里缺的类/方法的编码（属性编码 `q` = `NSInteger`/`int64_t`、`c` = `BOOL`、`@"NSArray"` = 数组；方法 `@16@0:8` = 无参返回对象），照旧头文件的风格补进 `Headers/HearthMirror_imp.h`；
  4. 把 sha 写进 `downloaded-frameworks/HearthMirror/HearthMirror.sha1`，脚本就会跳过下载。

  3.6.13 这次缺的是 `MirrorBattlegroundsMinionPool` / `MirrorBattlegroundsMinionPoolEntry`（属性 `dbfId`、`tier`、`cardType` 是 `NSInteger`，`minionTypes` 是 `NSArray<NSNumber *>`，`banned` 是 `BOOL`）和 `HearthMirror.getBattlegroundsMinionPool`。`downloaded-frameworks/` 已被 gitignore，所以这些只存在本机；等 CDN 补上对应 zip 就能去掉手工声明。
- `/Applications` 受 macOS「App 管理」保护，`mv`/`rm` 会被拒；`ditto` 是**合并覆盖**，会把上一版残留的文件留下，导致签名失效。做法：`ditto` 覆盖 → 用 `find` 对比两份文件清单移走多余文件 → 重新签名。`~/Applications` 下的副本不受限制。

## 发布

- tag 命名：`v<版本>-chs-<YYYYMMDD>.<序号>`，例如 `v3.6.12-chs-20260923.1`
- 资产命名：`HSTracker-CHS-<版本>-<日期>.<序号>-macos-universal.zip`
- **替换**已发布的 release：`gh release delete <tag> --cleanup-tag --yes` 后同名重建，指向新的提交
- `master` 每次同步都要换基线（新分支基于新 tag，与旧的 master 不是快进关系），所以推送用
  `git push --force-with-lease=refs/heads/master:<旧SHA> origin <分支>:refs/heads/master`。
  旧提交不会真的丢——它们由各自的 release tag 保留着。

## 发布前校验清单

```bash
# 版本号
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' <app>/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' <app>/Contents/Info.plist

# 功能符号（都应当 > 0）
grep -a -c DisabledRacesPanelController <app>/Contents/MacOS/HSTracker   # A
grep -a -c ClashSkipperController        <app>/Contents/MacOS/HSTracker   # B
grep -a -c 'Reconnect sync:'             <app>/Contents/MacOS/HSTracker   # C

# 中文串
plutil -p <app>/Contents/Resources/zh-Hans.lproj/Localizable.strings | grep aberration

# 畸变怪图标（上游 3.6.12 起自带）
xcrun --sdk macosx assetutil --info <app>/Contents/Resources/Assets.car | grep tribe_aberration

# 签名与一致性
codesign --verify --deep <app>
md5 -q <app>/Contents/MacOS/HSTracker   # 与本地安装的两份对比
```

## 与官方保持一致的底线

- **不删除任何官方文件**：`git diff --diff-filter=D` 必须为空。
- **新增功能尽量集中在本仓库自己的文件里**（`ClashSkipper.swift`、`DisabledRacesPanel.swift`），对官方文件的改动越小越好，同步时才好带、也才好看出冲突。
- 面板相关的行为（高度、吸顶、显示条件）都在 `DisabledRacesPanel.swift` 一个文件里，不要为了改样式去动 `BobsBuddyPanelView.swift` 等官方文件。
