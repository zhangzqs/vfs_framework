import 'engine/index.dart';
import 'provider/index.dart';

export 'engine/index.dart';
export 'provider/index.dart';

BlueprintEngine newDefaultEngine() {
  return BlueprintEngine(providers: defaultProviders);
}
