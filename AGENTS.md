# OxQueue working rules

- 每次完成一组修改，必须保存更新日志，再结束任务。记录实际行为变化、涉及范围和验证结果，不要只写“修复问题”。
- 日志以根目录 `CHANGELOG.json` 为准，`CHANGELOG.md` 由工具生成；保留历史记录，不覆盖或删除旧条目。
- 修改后的记录命令：`python tools/release.py record --note "中文改动" --note-en "English change" --verified "实际验证结果"`。多项改动可以重复传入参数。
- 发布新功能或修复前，同时更新 `OxQueue/OxQueue.toc` 和 `OxQueue/OxQueue.lua` 的版本号，不复用已经发布的版本号。
- 用 `python tools/release.py build` 打包。它会核对版本、检查修改是否已记日志、运行 `tests/check.py`，并把日志放进压缩包。禁止绕过检查手动生成发布包。
- 源码、测试、工具或本规则在日志记录后又有修改，必须再次记录；只有日志对应当前文件内容时才能打包。
- 网站发布时，同步版本、下载包、中英文更新日志和文件大小；保留旧版下载包。未获部署授权时，只准备产物。
- 行为测试使用模拟游戏环境；没有在游戏内验证时，明确说明，不声称已经实机验证。
