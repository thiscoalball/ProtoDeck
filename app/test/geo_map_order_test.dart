import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/ui/widgets/offline_geo_map.dart';

void main() {
  test('orders route points strictly by traceroute hop', () {
    const input = [
      GeoMapPoint(latitude: 30, longitude: 104, label: 'hop 8', order: 8),
      GeoMapPoint(latitude: 39, longitude: 116, label: 'hop 2', order: 2),
      GeoMapPoint(latitude: 31, longitude: 121, label: 'hop 5', order: 5),
    ];
    expect(orderGeoMapPoints(input).map((point) => point.order), [2, 5, 8]);
  });

  test('preserves insertion order when route order is unavailable', () {
    const input = [
      GeoMapPoint(latitude: 1, longitude: 1, label: 'a'),
      GeoMapPoint(latitude: 2, longitude: 2, label: 'b'),
    ];
    expect(orderGeoMapPoints(input).map((point) => point.label), ['a', 'b']);
  });
}
