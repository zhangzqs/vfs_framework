import '../engine/index.dart';
import 'backend/index.dart';
import 'compdiagram/index.dart';
import 'frontend/index.dart';
import 'frontend/webdav.dart';
import 'logger/logger.dart';

final defaultProviders = <ComponentProvider>[
  MemoryFileSystemProvider(),
  LocalFileSystemProvider(),
  AliasFileSystemProvider(),
  UnionFileSystemProvider(),
  HttpServerProvider(),
  BlockCacheFileSystemProvider(),
  MetadataCacheFileSystemProvider(),
  WebDAVFileSystemProvider(),
  WebDAVServerProvider(),
  LoggerProvider(),
  ComponentDiagramProvider(),
];
