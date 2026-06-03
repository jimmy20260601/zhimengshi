# 织梦师

《织梦师》是一个 Windows 本地版 SEEDANCE 2.0 提示词生成工具。用户可以输入短文本，或上传 Excel 分镜表、Word 小说/剧本文档，调用自己配置的 GPT、Gemini 或 DeepSeek API，生成专业版或大师版视频提示词，并支持导出 Word 文档。

## 功能特点

- 本地运行，API Key 只保存在用户自己的电脑上
- 支持 GPT、Gemini、DeepSeek 三类模型配置
- 支持短文本生成 SEEDANCE 2.0 提示词
- 短文本输入上限为 5000 字符
- 支持 Excel 分镜表批量生成提示词
- 支持 Word 小说/剧本文档批量生成提示词
- 支持专业版和大师版两种提示词模式
- 支持生成可下载的 Word 提示词文档
- 支持局域网共享访问
- 支持打包为 Windows 便携版

## 提示词模式

### 专业版

专业版用于动作场景、短视频分镜和批量分镜生成。生成时会尽量保留完整场景、关键动作、镜头类型、运镜、台词和时间轴。

### 大师版

大师版用于对话场景，会在专业版完整分镜骨架基础上，强化人物性格、台词语气、关键词发音、微表情、眼神、潜台词、听者反应和镜头调度。

单条 SEEDANCE 2.0 视频提示词最长 15 秒。遇到长台词或长场景时，工具会要求模型拆分为多条完整提示词。

## 本地启动

双击：

```text
启动织梦师.cmd
```

启动后在浏览器打开：

```text
http://localhost:3000
```

## 局域网共享

双击：

```text
启动织梦师-局域网共享.cmd
```

然后在同一局域网的其他电脑浏览器中打开启动窗口显示的 LAN URL。

## 打包便携版

双击：

```text
打包织梦师便携版.cmd
```

打包结果会生成在 `dist` 文件夹中。

## 项目结构

```text
server.ps1                 本地后端服务、模型调用、文件解析、提示词规则、Word 导出
public/index.html          主界面结构
public/styles.css          暗黑极客风界面样式
public/app.js              前端交互、模型设置、生成、复制、下载
package-portable.ps1       便携版打包脚本
启动织梦师.cmd              本地启动脚本
启动织梦师-局域网共享.cmd    局域网共享启动脚本
打包织梦师便携版.cmd         打包入口脚本
```

## 安全说明

API Key 只保存在本机 `.zhimengshi/` 目录中。该目录已加入 `.gitignore`，请不要上传到 GitHub。

开源上传时请不要上传：

```text
.zhimengshi/
dist/
ui-previews/
video-frames/
video-frames-play/
video-frames2/
*.zip
*.docx
*.log
```

## GitHub 网页上传建议

如果使用 GitHub 网页上传，请只上传源码和必要文档。推荐上传：

```text
public/
docs-assets/
.gitignore
README.md
package.json
server.js
server.ps1
start-zhimengshi.ps1
package-portable.ps1
启动织梦师.cmd
启动织梦师-局域网共享.cmd
打包织梦师便携版.cmd
织梦师-开发守则.md
织梦师-项目记忆.md
织梦师-另一台电脑使用说明.md
AI员工-分镜助理.md
AI员工-短视频分镜助理.md
AI员工-简介助理.md
```

不要上传本机配置、API Key、打包产物、测试截图帧和临时文件。

## 许可证

建议开源时选择 MIT License。可以在 GitHub 创建仓库时添加 `LICENSE` 文件。

