import 'dart:async';
import 'dart:typed_data';

import '../abstract/context.dart';
import '../abstract/index.dart';

/// 一个基于非递归列举形成递归列举的函数
Stream<FileStatus> recursiveList(
  FileSystemContext context, {
  required Stream<FileStatus> Function(
    FileSystemContext context,
    Path path, {
    ListOptions options,
  })
  nonRecursiveList, // 普通的非递归列举函数
  required Path path,
  required ListOptions options,
}) async* {
  if (!options.recursive) {
    yield* nonRecursiveList(context, path, options: options);
    return;
  }
  // 如果是递归列举，则使用队列来处理
  final queue = <Path>[path];
  final seen = <Path>{};

  while (queue.isNotEmpty) {
    final currentPath = queue.removeLast();
    if (seen.contains(currentPath)) continue;
    seen.add(currentPath);

    await for (final status in nonRecursiveList(
      context,
      currentPath,
      options: options,
    )) {
      yield status;
      if (status.isDirectory) {
        queue.add(status.path);
      }
    }
  }
}

Future<void> recursiveCreateDirectory(
  FileSystemContext context, {
  required Future<void> Function(
    FileSystemContext context,
    Path path, {
    CreateDirectoryOptions options,
  })
  nonRecursiveCreateDirectory,
  required Path path,
  required CreateDirectoryOptions options,
}) async {
  if (!options.createParents) {
    await nonRecursiveCreateDirectory(context, path, options: options);
    return;
  }
  // 递归逐级依次创建目录
  var dirs = <Path>[];
  var currentPath = path;
  while (!currentPath.isRoot) {
    dirs.add(currentPath);
    currentPath = currentPath.parent!;
  }
  // 反转顺序，从根目录开始创建
  for (final dir in dirs.reversed) {
    try {
      await nonRecursiveCreateDirectory(context, dir, options: options);
    } on FileSystemException catch (e) {
      if (e.code != FileSystemErrorCode.alreadyExists) {
        rethrow; // 如果不是因为目录已存在，则抛出异常
      }
    }
  }
}

Future<void> recursiveDelete(
  FileSystemContext context, {
  required Future<void> Function(
    FileSystemContext context,
    Path path, {
    DeleteOptions options,
  })
  nonRecursiveDelete, // 普通的非递归删除函数
  required Stream<FileStatus> Function(
    FileSystemContext context,
    Path path, {
    ListOptions options,
  })
  nonRecursiveList, // 普通的非递归列举函数
  required Path path,
  required DeleteOptions options,
}) async {
  if (!options.recursive) {
    await nonRecursiveDelete(context, path, options: options);
    return;
  }
  // 递归删除目录
  final queue = <Path>[path];
  final seen = <Path>{};

  while (queue.isNotEmpty) {
    final currentPath = queue.removeLast();
    if (seen.contains(currentPath)) continue;
    seen.add(currentPath);

    await for (final status in nonRecursiveList(
      context,
      currentPath,
      options: const ListOptions(recursive: true),
    )) {
      if (status.isDirectory) {
        queue.add(status.path);
      } else {
        await nonRecursiveDelete(context, status.path, options: options);
      }
    }
    await nonRecursiveDelete(context, currentPath, options: options);
  }
}

Future<void> recursiveCopy(
  FileSystemContext context, {
  required Path source,
  required Path destination,
  required CopyOptions options,
  required Future<void> Function(
    FileSystemContext context,
    Path source,
    Path destination, {
    CopyOptions options,
  })
  nonRecursiveCopyFile,
  required Stream<FileStatus> Function(
    FileSystemContext context,
    Path path, {
    ListOptions options,
  })
  nonRecursiveList,
  required Future<void> Function(
    FileSystemContext context,
    Path path, {
    CreateDirectoryOptions options,
  })
  recursiveCreateDirectory,
}) async {
  // 检查源是否存在
  if (await nonRecursiveList(context, source).isEmpty) {
    throw FileSystemException.notFound(source);
  }

  // 检查目标是否已存在
  if (!(await nonRecursiveList(context, destination).isEmpty)) {
    if (!options.overwrite) {
      throw FileSystemException.alreadyExists(destination);
    }
  } else {
    // 如果目标目录不存在，则创建它
    await recursiveCreateDirectory(
      context,
      destination.parent!,
      options: const CreateDirectoryOptions(createParents: true),
    );
  }

  // 开始递归复制
  final queue = <Path>[source];
  final seen = <Path>{};

  while (queue.isNotEmpty) {
    final currentSource = queue.removeLast();
    if (seen.contains(currentSource)) continue;
    seen.add(currentSource);

    await for (final status in nonRecursiveList(
      context,
      currentSource,
      options: const ListOptions(recursive: true),
    )) {
      if (status.isDirectory) {
        final newDest = destination.join(status.path.filename!);
        await recursiveCreateDirectory(
          context,
          newDest,
          options: const CreateDirectoryOptions(createParents: true),
        );
        queue.add(status.path);
      } else {
        final newDest = destination.join(status.path.filename!);
        await nonRecursiveCopyFile(
          context,
          status.path,
          newDest,
          options: options,
        );
      }
    }
  }
}

Future<void> copyFileByReadAndWrite(
  FileSystemContext context,
  Path source,
  Path destination, {
  required Future<StreamSink<List<int>>> Function(
    FileSystemContext context,
    Path path, {
    WriteOptions options,
  })
  openWrite,
  required Stream<List<int>> Function(
    FileSystemContext context,
    Path path, {
    ReadOptions options,
  })
  openRead,
}) async {
  final readStream = openRead(context, source);
  final writeSink = await openWrite(
    context,
    destination,
    options: const WriteOptions(mode: WriteMode.overwrite),
  );
  await for (final chunk in readStream) {
    writeSink.add(chunk);
  }
  await writeSink.close();
}

mixin FileSystemHelper on IFileSystem {
  /// 基于非递归list实现支持递归的list
  Stream<FileStatus> listImplByNonRecursive(
    FileSystemContext context, {
    required Stream<FileStatus> Function(
      FileSystemContext context,
      Path path, {
      ListOptions options,
    })
    nonRecursiveList,
    required Path path,
    required ListOptions options,
  }) async* {
    // 检查路径是否存在
    final statRes = await stat(context, path);
    if (statRes == null) {
      throw FileSystemException.notFound(path);
    }
    if (!statRes.isDirectory) {
      throw FileSystemException.notADirectory(path);
    }
    yield* recursiveList(
      context,
      nonRecursiveList: nonRecursiveList,
      path: path,
      options: options,
    );
  }

  /// 基于非递归createDirectory实现支持递归的createDirectory
  Future<void> createDirectoryImplByNonRecursive(
    FileSystemContext context, {
    required Future<void> Function(
      FileSystemContext context,
      Path path, {
      CreateDirectoryOptions options,
    })
    nonRecursiveCreateDirectory,
    required Path path,
    required CreateDirectoryOptions options,
  }) async {
    // 检查路径是否存在
    final statRes = await stat(context, path);
    if (statRes == null) {
      await recursiveCreateDirectory(
        context,
        nonRecursiveCreateDirectory: nonRecursiveCreateDirectory,
        path: path,
        options: options,
      );
    } else {
      if (statRes.isDirectory) {
        // 如果目录已存在且是目录，则不需要创建
        if (!options.createParents) {
          throw FileSystemException.alreadyExists(path);
        }
      } else {
        // 如果路径已存在但不是目录，则抛出异常
        throw FileSystemException.alreadyExists(path);
      }
    }
  }

  Future<void> deleteImplByNonRecursive(
    FileSystemContext context, {
    required Future<void> Function(
      FileSystemContext context,
      Path path, {
      DeleteOptions options,
    })
    nonRecursiveDelete,
    required Stream<FileStatus> Function(
      FileSystemContext context,
      Path path, {
      ListOptions options,
    })
    nonRecursiveList,
    required Path path,
    required DeleteOptions options,
  }) async {
    final statRes = await stat(context, path);
    if (statRes == null) {
      // 如果目标路径找不到则报错
      throw FileSystemException.notFound(path);
    } else {
      if (statRes.isDirectory) {
        // 目标是目录
        final emptyDir = await list(context, path).isEmpty;
        if (emptyDir) {
          // 空目录可以直接删除
          await nonRecursiveDelete(context, path, options: options);
        } else {
          if (!options.recursive) {
            throw FileSystemException.notEmptyDirectory(path);
          } else {
            // 递归删除目录
            await recursiveDelete(
              context,
              nonRecursiveDelete: nonRecursiveDelete,
              nonRecursiveList: nonRecursiveList,
              path: path,
              options: options,
            );
          }
        }
      } else {
        // 目标是文件，直接删除
        await nonRecursiveDelete(context, path, options: options);
      }
    }
  }

  Future<void> copyImplByNonRecursive(
    FileSystemContext context, {
    required Path source,
    required Path destination,
    required CopyOptions options,
    required Future<void> Function(
      FileSystemContext context,
      Path source,
      Path destination, {
      CopyOptions options,
    })
    nonRecursiveCopyFile,
    required Stream<FileStatus> Function(
      FileSystemContext context,
      Path path, {
      ListOptions options,
    })
    nonRecursiveList,
    required Future<void> Function(
      FileSystemContext context,
      Path path, {
      CreateDirectoryOptions options,
    })
    nonRecursiveCreateDirectory,
  }) async {
    // 检查源是否存在
    final srcStat = await stat(context, source);
    if (srcStat == null) {
      throw FileSystemException.notFound(source);
    }
    // 检查目标是否已存在
    final destStat = await stat(context, destination);
    if (destStat == null) {
      if (srcStat.isDirectory) {
        // 源是目录，目标不存在
        if (!options.recursive) {
          // 如果没有递归选项，则报错
          throw FileSystemException.recursiveNotSpecified(destination);
        }
        // 递归复制目录
        await recursiveCopy(
          context,
          source: source,
          destination: destination,
          options: options,
          nonRecursiveCopyFile: nonRecursiveCopyFile,
          nonRecursiveList: nonRecursiveList,
          recursiveCreateDirectory: createDirectory,
        );
      } else {
        // 源是文件，目标不存在
        // 正常的文件复制到目标所在的文件夹，如果目标所在的文件夹不存在，则报错NotFound
        final destDir = destination.parent;
        if (destDir != null && !(await exists(context, destDir))) {
          throw FileSystemException.notFound(destDir);
        }
        // 如果目标目录存在，则复制到目标目录上
        await nonRecursiveCopyFile(
          context,
          source,
          destination,
          options: options,
        );
      }
    } else {
      if (srcStat.isDirectory) {
        if (destStat.isDirectory) {
          // 源和目标都是目录，且目标已存在
          if (!options.recursive) {
            // 如果没有递归选项，则报错
            throw FileSystemException.recursiveNotSpecified(destination);
          }
          // 递归复制目录
          await recursiveCopy(
            context,
            source: source,
            destination: destination,
            options: options,
            nonRecursiveCopyFile: nonRecursiveCopyFile,
            nonRecursiveList: nonRecursiveList,
            recursiveCreateDirectory: createDirectory,
          );
        } else {
          // 源是目录，目标是文件，且目标已存在
          // 预期需要报错不能覆盖，无论怎样参数都报错alreadyExists
          throw FileSystemException.alreadyExists(destination);
        }
      } else {
        if (destStat.isDirectory) {
          // 源是文件，目标是目录，且目标已存在
          // 将文件复制到目标目录下
          final destPath = destination.join(source.filename!);
          await nonRecursiveCopyFile(
            context,
            source,
            destPath,
            options: options,
          );
        } else {
          // 源和目标都是文件，且目标已存在
          if (!options.overwrite) {
            throw FileSystemException.alreadyExists(destination);
          }
          // 如果允许覆盖，则直接复制
          await nonRecursiveCopyFile(
            context,
            source,
            destination,
            options: options,
          );
        }
      }
    }
  }

  Future<void> preOpenWriteCheck(
    FileSystemContext context,
    Path path, {
    WriteOptions options = const WriteOptions(),
  }) async {
    // 检查文件是否已存在且不允许覆盖
    final statRes = await stat(context, path);
    if (statRes == null) {
      // 确保父目录存在
      final parentDir = path.parent;
      if (parentDir == null) {
        throw FileSystemException.notFound(path);
      }
      final parentStat = await stat(context, parentDir);
      if (parentStat == null) {
        throw FileSystemException.notFound(parentDir);
      }
      if (!parentStat.isDirectory) {
        throw FileSystemException.notADirectory(parentDir);
      }
      // 可以写文件
    } else {
      // 文件或目录已存在
      if (statRes.isDirectory) {
        throw FileSystemException.notAFile(path);
      } else {
        // 如果文件已存在
        switch (options.mode) {
          case WriteMode.write:
            // 不允许覆盖，则抛出异常
            throw FileSystemException.alreadyExists(path);
          case WriteMode.overwrite:
            // 可以覆盖写了
            break;
          case WriteMode.append:
            // 可以追加写了
            break;
        }
      }
    }
  }

  Future<void> preOpenReadCheck(
    FileSystemContext context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) async {
    // 检查文件是否存在
    final statRes = await stat(context, path);
    if (statRes == null) {
      throw FileSystemException.notFound(path);
    }
    // 如果是目录，则抛出异常
    if (statRes.isDirectory) {
      throw FileSystemException.notAFile(path);
    }
  }

  /// 检查是否存在
  @override
  Future<bool> exists(
    FileSystemContext context,
    Path path, {
    ExistsOptions options = const ExistsOptions(),
  }) async {
    final status = await stat(context, path);
    return status != null;
  }

  /// 读取全部文件内容
  @override
  Future<Uint8List> readAsBytes(
    FileSystemContext context,
    Path path, {
    ReadOptions options = const ReadOptions(),
  }) async {
    final buffer = BytesBuilder();
    await for (final chunk in openRead(context, path, options: options)) {
      buffer.add(chunk);
    }
    return buffer.takeBytes();
  }

  /// 覆盖写入全部文件内容
  @override
  Future<void> writeBytes(
    FileSystemContext context,
    Path path,
    Uint8List data, {
    WriteOptions options = const WriteOptions(),
  }) {
    return openWrite(context, path, options: options).then((sink) {
      sink.add(data);
      return sink.close();
    });
  }

  /// 移动文件/目录
  @override
  Future<void> move(
    FileSystemContext context,
    Path source,
    Path destination, {
    MoveOptions options = const MoveOptions(),
  }) async {
    await copy(
      context,
      source,
      destination,
      options: CopyOptions(
        overwrite: options.overwrite,
        recursive: options.recursive,
      ),
    );
    await delete(
      context,
      source,
      options: DeleteOptions(recursive: options.recursive),
    );
  }
}
