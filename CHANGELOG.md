# OxQueue 更新日志 / Changelog

## 1.0.2 - 2026-10-29

- 新增非商业使用许可：允许非商业免费使用、修改和分享，禁止未经授权的商业用途及收费分发；许可随插件包提供。

- Add a noncommercial license permitting free noncommercial use, modification and sharing while prohibiting unauthorized commercial use and paid distribution; include it in the addon package.

验证 / Validation:

- 45 项插件模拟测试与 5 项发布工具测试通过；未在游戏客户端内验证。

## 1.0.1 - 2026-10-29

- 新增项目说明，介绍安装、使用命令和模拟测试；公开仓库排除临时文件并保留源码原始换行，以保持发布校验一致。

- Add project documentation for installation, commands, and simulated tests; exclude temporary files and preserve source line endings for consistent release checks.

验证 / Validation:

- 45 项插件模拟测试和 5 项发布工具测试通过；未在游戏客户端内验证。

## 1.0.1 - 2026-10-29

- 新增项目说明，介绍安装、使用命令和模拟测试；为公开仓库排除临时文件。

- Add project documentation for installation, commands, and simulated tests, and exclude temporary files from the public repository.

验证 / Validation:

- 45 项插件模拟测试和 5 项发布工具测试通过；未在游戏客户端内验证。

## 1.0.1 - 2026-10-18

- 延迟容限（SpellQueueWindow）按专精分别保存，切换专精或重新登录时恢复对应设置。
- 恢复操作和战斗中等待应用的设置只影响对应专精；旧设置仅迁移到升级时的当前专精，其他未设置的专精使用游戏默认值。
- 新增持续更新日志和发布检查：每次完成修改后记录中英文说明与验证结果，源码或工具修改后未补日志将禁止打包，发行包附带日志。

- Save SpellQueueWindow separately for each spec and restore it on spec changes or login.
- Revert and pending combat changes stay with their own spec. Migrate old settings only to the active spec; unconfigured specs use the game default.
- Add persistent changelogs and a release check that rejects unlogged changes. Include changelogs in the release archive.

验证 / Validation:

- 45 项插件模拟测试通过，包含切换专精、重新登录、旧设置迁移、战斗延后应用和零值。
- 5 项更新日志检查测试通过；未在真实游戏客户端内验证。

## 1.0.0 - 2026-10-18

- 首个公开版本。

- First public release.

验证 / Validation:

- 历史发布记录，沿用网站已发布的版本说明。
