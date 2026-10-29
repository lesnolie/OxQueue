# OxQueue

OxQueue 是《魔兽世界》的施法队列窗口调校插件。它记录技能按键时机和网络延迟，推荐延迟容限（`SpellQueueWindow`），帮助你根据自己的操作习惯调整技能提前排队的时间。

## 安装

1. 下载仓库中的 [OxQueue.zip](OxQueue.zip) 并解压。
2. 将解压出的 `OxQueue` 文件夹放入游戏目录的 `_retail_/Interface/AddOns/` 中。
3. 启动或重新载入游戏，在插件列表中启用 OxQueue。

插件声明的客户端接口版本为 `120100` 和 `120105`。安装后应能看到 `AddOns/OxQueue/OxQueue.toc`，避免多套一层文件夹。

## 使用

输入 `/oxq` 打开面板，开始记录后照常战斗或打训练假人。收集足够的公共冷却（Global Cooldown，GCD）样本和延迟数据后，面板会给出推荐值；选择应用后才会修改游戏设置。战斗中应用的值会在脱战后生效。设置和采集数据按专精分别保存，切换专精或重新登录时会恢复对应设置。

常用命令：

| 命令 | 作用 |
| --- | --- |
| `/oxq` | 打开或关闭面板 |
| `/oxq start` / `/oxq stop` | 开始或停止记录 |
| `/oxq status` | 在聊天窗口显示采集状态 |
| `/oxq apply` | 应用推荐值；也可用 `/oxq apply 150` 指定毫秒数 |
| `/oxq reset` | 清空当前专精的采集数据 |
| `/oxq anytime` | 切换是否也在非战斗中记录 |

`/sqw` 和 `/yanchi` 也可代替 `/oxq`。

## 开发与验证

行为测试使用模拟游戏环境，需要 Python 和 `lupa`：

```sh
python tests/check.py
python tests/test_release.py
```

发布说明见 [更新日志](CHANGELOG.md)。打包使用 `python tools/release.py build`；发布规则见 [AGENTS.md](AGENTS.md)。
