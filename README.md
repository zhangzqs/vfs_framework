# VFS Framework

一个基于 Dart 的虚拟文件系统框架，提供统一的文件系统抽象层，支持多种后端存储和前端访问方式。

## 🌟 项目概述

VFS Framework 是一个受 [rclone](https://rclone.org/) 和 [Alist](https://alist.nn.ci/) 启发的虚拟文件系统框架。它提供了一个统一的 API 来访问不同的存储后端，并支持多种前端访问方式。该框架采用插件化架构，易于扩展和定制。

### 核心特性

- 🔌 **插件化架构**：支持多种存储后端和前端
- 🌐 **统一 API**：为所有存储后端提供一致的文件系统接口
- 🚀 **高性能**：全异步操作和流式处理接口
- 🔧 **蓝图编排**：声明式的复杂文件系统编排能力

## 📁 支持的文件系统后端

### 当前支持

- **LocalFileSystem** - 本地文件系统
- **MemoryFileSystem** - 内存文件系统（用于测试和缓存）
- **UnionFileSystem** - Union 文件系统（用于合并挂载多个文件系统后端）
- **AliasFileSystem** - Alias 文件系统（用于将某个文件系统的子目录映射成一个新的文件系统）
- **BlockCacheFileSystem** - 块缓存文件系统（用于分块缓存文件内容，提升访问速度）
- **MetadataCacheFileSystem** - 元数据缓存文件系统（用于缓存文件元数据，减少文件系统后端请求）
- **WebDAVFileSystem** - WebDAV 文件系统（支持 WebDAV 协议的文件访问）

### 计划支持

- SMB
- S3 兼容存储

## 🌐 支持的前端接口

### HTTP 服务器

- **HTTP 服务器** - RESTful API 和 Web 界面

  - 文件浏览和下载
  - 目录列表
  - 中文文件名支持

- **WebDAV 服务器** - 支持 WebDAV 协议的文件访问
  - 文件上传和下载
  - 目录创建和删除
  - 文件重命名和移动

## 其他组件

### 结构化日志框架

VFS Framework 提供了一个支持结构化的日志框架，支持多种日志输出方式，包含 console 和 text 格式，支持输出到文件和控制台，其中输出到文件支持日志滚动和切分。

### 组件图自动导出渲染

蓝图编排引擎中包含一个内建组件，用于分析导出所有的组件间的依赖关系，自动生成 puml 组件图和对应的 SVG 文件。

## ⚙️ 蓝图编排引擎

VFS Framework 包含一个强大的蓝图编排引擎，用于声明式配置和管理组件。编排引擎提供：

- **依赖注入**：自动解析和注入组件依赖
- **生命周期管理**：组件的创建、配置和运行
- **配置驱动**：通过 YAML/JSON 配置文件定义整个系统

### 编排引擎示例

#### 配置文件 (`config.yaml`)

[config.yaml](bin/config.yaml)

#### 运行启动

```bash
cd bin
dart run vfs_framework.dart
```

将得到如下编排可视化图：
![编排可视化图](bin/component_diagram.svg)

访问 [http://localhost:8080](http://localhost:8080) 查看文件系统内容。
