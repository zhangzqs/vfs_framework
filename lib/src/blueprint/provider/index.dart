import 'package:vfs_framework/src/blueprint/provider/frontend/webdav.dart';

import '../engine/index.dart';
import 'backend/index.dart';
import 'frontend/index.dart';

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
];
