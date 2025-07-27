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
];
