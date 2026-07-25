import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/models/tool_experience.dart';
import 'package:nettools_mobile/models/tool_route_args.dart';
import 'package:nettools_mobile/ui/tool_catalog.dart';

void main() {
  test('every catalog tool has a valid experience profile', () {
    final ids = toolCatalog.map((tool) => tool.id).toSet();
    expect(ids.length, toolCatalog.length);
    for (final tool in toolCatalog) {
      final profile = tool.experience;
      expect(
        profile.relatedToolIds.where((id) => !ids.contains(id)),
        isEmpty,
        reason: '${tool.id} references an unknown related tool',
      );
    }
  });

  test('active protocol tools keep app-session semantics', () {
    expect(
      toolExperienceFor('api_workbench').taskBehavior,
      ToolTaskBehavior.continueInApp,
    );
    expect(
      toolExperienceFor('api_workbench').draftBehavior,
      ToolDraftBehavior.secureProfile,
    );
    expect(
      toolExperienceFor('iperf').taskBehavior,
      ToolTaskBehavior.foregroundCapable,
    );
  });

  test('route arguments normalize host into an HTTP URL', () {
    const args = ToolRouteArgs(target: ' 192.168.8.1 ', port: 8080);
    expect(args.normalizedTarget, '192.168.8.1');
    expect(args.httpUrl, 'http://192.168.8.1:8080');
  });
}
