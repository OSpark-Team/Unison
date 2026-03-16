# AppScope 模块文档

[根目录](../CLAUDE.md) > **AppScope**

> 文档生成时间：2026-02-04T07:45:43Z

## 变更记录 (Changelog)

| 日期 | 版本 | 变更内容 |
|------|------|----------|
| 2026-02-04 | 1.0.0 | 初始化模块文档 |

---

## 模块职责

AppScope 是应用全局配置模块，包含应用级别的元信息和全局资源。

---

## 配置文件

### app.json5
```json5
{
  "app": {
    "bundleName": "zone.yby.unison",
    "vendor": "example",
    "versionCode": 1000000,
    "versionName": "1.0.0",
    "icon": "$media:layered_image",
    "label": "$string:app_name"
  }
}
```

### 配置项说明
| 字段 | 值 | 说明 |
|------|-----|------|
| bundleName | zone.yby.unison | 应用包名 |
| vendor | example | 开发商 |
| versionCode | 1000000 | 版本号 |
| versionName | 1.0.0 | 版本名称 |
| icon | $media:layered_image | 应用图标 |
| label | $string:app_name | 应用名称 |

---

## 资源文件

### 资源目录结构
```
AppScope/resources/
├── base/
│   ├── element/
│   │   └── string.json    # 字符串资源（app_name等）
│   └── media/
│       ├── background.png # 应用背景
│       ├── foreground.png # 应用前景
│       └── layered_image.json # 分层图像配置
```

### 字符串资源 (base/element/string.json)
- `app_name` - 应用名称字符串

---

## 相关文件清单

| 文件 | 描述 |
|------|------|
| `app.json5` | 应用全局配置 |
| `resources/base/element/string.json` | 全局字符串资源 |
| `resources/base/media/background.png` | 应用背景图 |
| `resources/base/media/foreground.png` | 应用前景图 |
| `resources/base/media/layered_image.json` | 分层图像配置 |