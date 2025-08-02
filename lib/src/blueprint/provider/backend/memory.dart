import '../../../abstract/filesystem.dart';
import '../../../backend/index.dart';
import '../../engine/core.dart';

class MemoryFileSystemProvider extends ComponentProvider<IFileSystem> {
  @override
  String get type => 'backend.memory';

  @override
  Future<IFileSystem> createComponent(
    BuildContext ctx,
    Map<String, dynamic> config,
  ) async {
    return MemoryFileSystem();
  }
}
