import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/ui/widgets/offline_geo_map.dart';

void main() {
  testWidgets('离线地图在中国坐标下能绘制定位点和路由', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OfflineGeoMap(
            connectPoints: true,
            points: [
              GeoMapPoint(
                latitude: 30.5728,
                longitude: 104.0668,
                label: '成都',
                order: 1,
              ),
              GeoMapPoint(
                latitude: 32.0603,
                longitude: 118.7969,
                label: '南京',
                order: 2,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('高德地图'), findsOneWidget);
    await tester.tap(find.text('高德地图'));
    await tester.pump();
    expect(find.text('离线概览'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
