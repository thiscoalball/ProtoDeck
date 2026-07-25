import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/oui/oui_repository.dart';
import '../models/build_info.dart';
import '../models/platform_capability.dart';
import '../services/build_info_service.dart';
import '../services/native_network_service.dart';
import '../services/platform_capability_service.dart';
import '../services/tool_draft_repository.dart';
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

final buildInfoProvider = FutureProvider<BuildInfo>(
  (ref) => const BuildInfoService().load(),
);

final platformCapabilityServiceProvider = Provider<PlatformCapabilityService>(
  (ref) => PlatformCapabilityService(),
);

final platformCapabilitiesProvider = FutureProvider<PlatformCapabilities>(
  (ref) => ref.read(platformCapabilityServiceProvider).probe(),
);

final toolDraftRepositoryProvider = Provider<ToolDraftRepository>((ref) {
  final repository = ToolDraftRepository(ref.read(appStateProvider).database);
  ref.onDispose(repository.dispose);
  return repository;
});
