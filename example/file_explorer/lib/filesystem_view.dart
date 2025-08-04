import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:vfs_framework/vfs_framework.dart' hide BuildContext;

class FileManagerWidget extends StatefulWidget {
  final IFileSystem fileSystem;
  final Path initialWorkingDir;

  const FileManagerWidget({
    super.key,
    required this.fileSystem,
    required this.initialWorkingDir,
  });

  @override
  State<FileManagerWidget> createState() => _FileManagerWidgetState();
}

class _FileManagerWidgetState extends State<FileManagerWidget> {
  late Path _workingDir;
  List<FileStatus> _currentDirContents = [];
  bool _isLoading = false;
  String? _errorMessage;

  // 用于复制/移动操作的状态
  FileStatus? _selectedItemForOperation;
  String? _operationType; // 'copy' 或 'move'
  bool _showOperationMode = false;

  @override
  void initState() {
    super.initState();
    _workingDir = widget.initialWorkingDir;
    _refreshDirContents();
  }

  // 为每个操作创建新的Context
  Context _buildContext() {
    return Context(); // 根据实际需求构建Context
  }

  Future<void> _refreshDirContents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final contents = await widget.fileSystem
          .list(_buildContext(), _workingDir)
          .toList();
      setState(() {
        _currentDirContents = contents;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _changeDirectory(Path newPath) async {
    setState(() {
      _workingDir = newPath;
      _cancelOperation(); // 切换目录时取消当前操作
    });
    await _refreshDirContents();
  }

  Future<void> _createDirectory(String name) async {
    try {
      final newDirPath = _workingDir.join(name);
      await widget.fileSystem.createDirectory(
        _buildContext(),
        newDirPath,
        options: const CreateDirectoryOptions(createParents: false),
      );
      await _refreshDirContents();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to create directory: ${e.toString()}';
      });
    }
  }

  Future<void> _deleteItem(Path path) async {
    try {
      await widget.fileSystem.delete(
        _buildContext(),
        path,
        options: const DeleteOptions(recursive: false),
      );
      await _refreshDirContents();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to delete item: ${e.toString()}';
      });
    }
  }

  Future<void> uploadFile(Uint8List data, String fileName) async {
    try {
      final filePath = _workingDir.join(fileName);
      await widget.fileSystem.writeBytes(
        _buildContext(),
        filePath,
        data,
        options: const WriteOptions(mode: WriteMode.write),
      );
      await _refreshDirContents();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to upload file: ${e.toString()}';
      });
    }
  }

  Future<Uint8List?> _downloadFile(Path path) async {
    try {
      return await widget.fileSystem.readAsBytes(
        _buildContext(),
        path,
        options: const ReadOptions(),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to download file: ${e.toString()}';
      });
      return null;
    }
  }

  // 复制文件/目录
  Future<void> _copyItem(Path source, Path destination) async {
    try {
      await widget.fileSystem.copy(
        _buildContext(),
        source,
        destination,
        options: const CopyOptions(overwrite: false, recursive: true),
      );
      await _refreshDirContents();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to copy item: ${e.toString()}';
      });
    }
  }

  // 移动文件/目录
  Future<void> _moveItem(Path source, Path destination) async {
    try {
      await widget.fileSystem.move(
        _buildContext(),
        source,
        destination,
        options: const MoveOptions(overwrite: false, recursive: true),
      );
      await _refreshDirContents();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to move item: ${e.toString()}';
      });
    }
  }

  // 开始复制操作
  void _startCopyOperation(FileStatus item) {
    setState(() {
      _selectedItemForOperation = item;
      _operationType = 'copy';
      _showOperationMode = true;
    });
  }

  // 开始移动操作
  void _startMoveOperation(FileStatus item) {
    setState(() {
      _selectedItemForOperation = item;
      _operationType = 'move';
      _showOperationMode = true;
    });
  }

  // 执行复制或移动操作
  void executeOperation(Path destinationPath) {
    if (_selectedItemForOperation == null || _operationType == null) return;

    final sourcePath = _selectedItemForOperation!.path;
    final destination = destinationPath.join(sourcePath.filename!);

    if (_operationType == 'copy') {
      _copyItem(sourcePath, destination);
    } else if (_operationType == 'move') {
      _moveItem(sourcePath, destination);
    }

    _cancelOperation();
  }

  // 取消当前操作
  void _cancelOperation() {
    setState(() {
      _selectedItemForOperation = null;
      _operationType = null;
      _showOperationMode = false;
    });
  }

  // 导航到上一级目录
  void _navigateUp() {
    if (_workingDir.isRoot) return;

    final parentPath = _workingDir.parent;
    _changeDirectory(parentPath!);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 操作模式提示
        if (_showOperationMode)
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.amber[100],
            child: Row(
              children: [
                Icon(
                  _operationType == 'copy' ? Icons.copy : Icons.cut,
                  color: Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_operationType == 'copy' ? 'Copying' : 'Moving'}: ${_selectedItemForOperation?.path.filename}',
                  style: const TextStyle(color: Colors.orange),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _cancelOperation,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),

        // 路径导航栏
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[200],
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward),
                onPressed: _navigateUp,
                tooltip: 'Go up',
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    'Current Directory: ${_workingDir.toString()}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 错误信息显示
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),

        // 加载指示器
        if (_isLoading) const Center(child: CircularProgressIndicator()),

        // 目录内容列表
        Expanded(
          child: ListView.builder(
            itemCount: _currentDirContents.length,
            itemBuilder: (context, index) {
              final item = _currentDirContents[index];
              return ListTile(
                leading: item.isDirectory
                    ? const Icon(Icons.folder)
                    : const Icon(Icons.insert_drive_file),
                title: Text(item.path.filename!),
                subtitle: Text(
                  item.isDirectory
                      ? 'Directory'
                      : 'File (${item.size?.toString() ?? '?'} bytes)',
                ),
                onTap: () {
                  if (item.isDirectory) {
                    _changeDirectory(item.path);
                  } else {
                    _downloadFile(item.path);
                  }
                },
                onLongPress: () {
                  _showContextMenu(context, item);
                },
              );
            },
          ),
        ),

        // 操作按钮
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.create_new_folder),
                label: const Text('New Folder'),
                onPressed: () => _createDirectory('NewFolder'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload'),
                onPressed: () {
                  // 这里应该实现文件选择器逻辑
                  // 然后调用_uploadFile方法
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 显示上下文菜单（长按）
  void _showContextMenu(BuildContext context, FileStatus item) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                _startCopyOperation(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cut),
              title: const Text('Move'),
              onTap: () {
                Navigator.pop(context);
                _startMoveOperation(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(context);
                _deleteItem(item.path);
              },
            ),
            if (item.isDirectory)
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Open'),
                onTap: () {
                  Navigator.pop(context);
                  _changeDirectory(item.path);
                },
              ),
            if (!item.isDirectory)
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Download'),
                onTap: () {
                  Navigator.pop(context);
                  _downloadFile(item.path);
                },
              ),
          ],
        );
      },
    );
  }
}
