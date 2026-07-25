import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/oui/oui_repository.dart';
import '../services/native_network_service.dart';
import 'app_state.dart';

final appStateProvider = ChangeNotifierProvider<AppState>(
  (ref) =>
      throw StateError('AppState must be initialized before ProviderScope'),
);

final ouiRepositoryProvider = Provider<OuiRepository>(
  (ref) => throw StateError(
    'OuiRepository must be initialized before ProviderScope',
  ),
);

final nativeNetworkServiceProvider = Provider<NativeNetworkService>(
  (ref) => NativeNetworkService(),
);
