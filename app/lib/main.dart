import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/oui/oui_repository.dart';
import 'legal_licenses.dart';
import 'state/app_state.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();
  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }
  final state = AppState();
  await state.initialize();
  final ouiRepository = OuiRepository();
  await ouiRepository.initialize();
  runApp(
    ProviderScope(
      overrides: [
        appStateProvider.overrideWith((ref) => state),
        ouiRepositoryProvider.overrideWithValue(ouiRepository),
      ],
      child: NetToolsApp(state: state),
    ),
  );
}
