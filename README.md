# Codex Quota

Codex Quota 是一个原生 macOS 菜单栏应用 + 桌面小组件，用来在桌面上查看 Codex 的本地额度消耗情况。

它会读取本机 `~/.codex` 目录下的 Codex rollout 日志，解析 token 统计事件，然后把脱敏后的额度快照写入本地缓存。桌面小组件只读取这个缓存并展示数据，不直接扫描日志。

## 项目简介和桌面小组件效果说明

小组件主要展示：

- `5小时` 额度剩余百分比
- `周限额` 剩余百分比
- 每个额度窗口的重置时间
- 最近刷新时间
- 近 5 天 token 消耗趋势
- 日均 token 消耗

小组件支持小号和中号两种尺寸：

- 小号：展示 Codex 标题、刷新时间、两个额度进度条、剩余百分比和重置时间
- 中号：在小号信息基础上增加近 5 天 token 消耗趋势图和日均 token 消耗

菜单栏应用负责刷新数据，小组件负责展示数据。界面会自适应浅色 / 深色模式，并在没有数据、数据过期或解析出错时显示对应提示。

## 安装步骤

目前项目采用源码安装方式。用户需要在自己的 Mac 上本地构建、本地签名、本地安装。

### 环境要求

- macOS 14 或更高版本
- 已安装完整 Xcode
- 本机已经运行过 Codex，确保 `~/.codex` 下存在日志

如果只安装了 Command Line Tools，需要先从 Mac App Store 安装完整 Xcode。

### 安装

1. 克隆项目：

   ```sh
   git clone https://github.com/Zaki362/codex-widget.git
   cd codex-widget
   ```

   也可以在 GitHub 页面点击 `Code` -> `Download ZIP` 下载源码。

2. 确认系统使用完整 Xcode：

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

3. 如果是第一次安装 Xcode，先完成 Xcode 组件初始化：

   ```sh
   ./scripts/install-xcode-components.command
   ```

4. 执行本地安装脚本：

   ```sh
   ./scripts/install-local.command
   ```

   脚本会自动完成：

   - Release 构建
   - 本地 ad-hoc 签名
   - 安装到 `~/Applications/CodexQuota.app`
   - 启动菜单栏应用

## 如何添加 macOS 桌面小组件

安装完成后，先确认菜单栏里已经出现 Codex Quota 应用，然后添加小组件：

1. 右键点击 macOS 桌面
2. 选择「编辑小组件」
3. 搜索 `Codex Quota` 或 `Codex 额度`
4. 选择小号或中号尺寸
5. 点击添加到桌面
6. 等待 30-60 秒，小组件会显示第一次刷新后的额度数据

如果小组件列表里暂时搜不到，先打开一次 `~/Applications/CodexQuota.app`，再重新进入「编辑小组件」搜索。

## Codex 额度数据怎么读取、怎么计算

Codex Quota 只扫描以下本地文件：

```text
~/.codex/sessions/**/rollout-*.jsonl
~/.codex/archived_sessions/*.jsonl
```

它不会读取：

```text
~/.codex/auth.json
```

解析逻辑只关注 rollout 日志里的 token 统计事件：

```text
event_msg.payload.type == "token_count"
```

字段映射：

```text
rate_limits.primary.used_percent       -> 5小时额度已用百分比
rate_limits.secondary.used_percent     -> 周限额已用百分比
rate_limits.*.resets_at                -> 额度重置时间
last_token_usage.total_tokens          -> 按本地日期聚合 token 消耗
```

小组件展示的是剩余额度：

```text
remaining = 100 - used_percent
```

近 5 天趋势图使用 `last_token_usage.total_tokens` 按本地自然日聚合。日均 token 消耗则基于这 5 天的数据计算。

解析后的展示快照会写入本地缓存：

```text
~/Library/Containers/com.guohuaz.CodexQuota.Widget/Data/Library/Application Support/CodexQuota/quota-snapshot.json
```

缓存只包含小组件展示需要的数据，不包含账号认证信息。

## 刷新机制、WidgetKit 延迟说明

菜单栏应用运行时会负责刷新数据：

- 启动后自动刷新一次
- 最近 5 分钟有 Codex token 事件时，每 60 秒做一次保底刷新
- Codex 空闲时降频为每 15 分钟做一次保底检查，避免长时间耗电
- 监听 Codex session 目录变化，发现日志更新后自动刷新
- 只扫描近 5 天趋势相关日志，以及最近 24 小时仍在写入的长会话日志；文件未变化时复用解析缓存
- 写入新快照后调用 `WidgetCenter.reloadAllTimelines()` 请求小组件更新

桌面小组件本身不会直接扫描 `~/.codex`，它只读取菜单栏应用生成的本地缓存。

需要注意：WidgetKit 的实际刷新由 macOS 系统调度。应用会主动请求刷新，但系统可能会延迟桌面小组件的更新时间，所以它是接近实时，不保证每次日志变化都立刻显示。

一般情况下等待 30-60 秒即可看到更新。如果仍然没有变化，可以移除小组件后重新添加。

## 常见问题排查

### 小组件列表里搜不到 Codex Quota

可以按下面顺序处理：

1. 打开一次 `~/Applications/CodexQuota.app`
2. 等待 30-60 秒
3. 重新打开「编辑小组件」
4. 搜索 `Codex Quota` 或 `Codex 额度`
5. 如果仍然没有出现，尝试退出登录后重新登录，或重启 Mac

### 小组件出现了，但是没有数据

通常是本机还没有 Codex token 日志，或者菜单栏应用还没完成第一次刷新。

可以检查这个目录是否存在：

```text
~/.codex/sessions
```

如果目录不存在，先运行一次 Codex。之后打开 Codex Quota 菜单栏应用，点击刷新，再等待小组件更新。

### 安装脚本打不开

如果 macOS 阻止打开 `.command` 脚本，可以右键点击：

```text
scripts/install-local.command
```

选择「打开」，再确认执行。

也可以直接在终端中运行：

```sh
./scripts/install-local.command
```

### 构建失败，提示 Xcode 未配置

先执行：

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
./scripts/install-xcode-components.command
```

再重新运行：

```sh
./scripts/install-local.command
```

### 数据没有立刻刷新

这是 WidgetKit 的系统调度限制。菜单栏应用会尽快写入新数据，并请求小组件刷新，但 macOS 可能会延迟实际更新时间。

一般等待 30-60 秒即可。如果仍然不变，可以移除桌面小组件后重新添加。
