import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../l10n/app_localizations.dart';

class GeoMapPoint {
  const GeoMapPoint({
    required this.latitude,
    required this.longitude,
    required this.label,
    this.order,
  });

  final double latitude;
  final double longitude;
  final String label;
  final int? order;
}

List<GeoMapPoint> orderGeoMapPoints(Iterable<GeoMapPoint> points) {
  final indexed = points.indexed.toList();
  indexed.sort((a, b) {
    final aOrder = a.$2.order;
    final bOrder = b.$2.order;
    if (aOrder != null && bOrder != null) {
      final value = aOrder.compareTo(bOrder);
      if (value != 0) return value;
    } else if (aOrder != null) {
      return -1;
    } else if (bOrder != null) {
      return 1;
    }
    return a.$1.compareTo(b.$1);
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

class OfflineGeoMap extends StatefulWidget {
  const OfflineGeoMap({
    super.key,
    required this.points,
    this.height = 240,
    this.connectPoints = false,
  });

  final List<GeoMapPoint> points;
  final double height;
  final bool connectPoints;

  @override
  State<OfflineGeoMap> createState() => _OfflineGeoMapState();
}

class _OfflineGeoMapState extends State<OfflineGeoMap> {
  bool _online = true;
  int _tileErrors = 0;

  @override
  Widget build(BuildContext context) {
    final ordered = orderGeoMapPoints(widget.points);
    final corrected = ordered.map(_gcjPoint).toList();
    final coordinates = corrected
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC8E3F5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: _online
          ? Stack(
              children: [
                FlutterMap(
                  key: ValueKey(
                    corrected
                        .map((p) => '${p.latitude},${p.longitude}')
                        .join('|'),
                  ),
                  options: MapOptions(
                    initialCenter: coordinates.last,
                    initialZoom: coordinates.length == 1 ? 7 : 5,
                    initialCameraFit: coordinates.length > 1
                        ? CameraFit.bounds(
                            bounds: LatLngBounds.fromPoints(coordinates),
                            padding: const EdgeInsets.fromLTRB(42, 54, 42, 34),
                            maxZoom: 8,
                          )
                        : null,
                    backgroundColor: const Color(0xFFEAF6FF),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=7&x={x}&y={y}&z={z}',
                      subdomains: const ['1', '2', '3', '4'],
                      userAgentPackageName: 'com.nettools.nettools_mobile',
                      errorTileCallback: (_, _, _) {
                        _tileErrors++;
                        if (_tileErrors >= 8 && mounted && _online) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _online = false);
                          });
                        }
                      },
                    ),
                    if (widget.connectPoints && coordinates.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: coordinates,
                            color: const Color(0xFF2583D8),
                            strokeWidth: 3.5,
                            borderStrokeWidth: 2.5,
                            borderColor: Colors.white.withValues(alpha: .88),
                            gradientColors: const [
                              Color(0xFF65B9F4),
                              Color(0xFF2583D8),
                              Color(0xFF007F7A),
                            ],
                            strokeCap: StrokeCap.round,
                            strokeJoin: StrokeJoin.round,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: corrected.asMap().entries.map((entry) {
                        final index = entry.key;
                        final point = entry.value;
                        return Marker(
                          point: LatLng(point.latitude, point.longitude),
                          width: 128,
                          height: 52,
                          alignment: Alignment.topCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 124,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '${point.order == null ? '' : '${point.order} · '}${point.label}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF17425F),
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.location_on,
                                size: 25,
                                color: index == corrected.length - 1
                                    ? const Color(0xFFE64A3B)
                                    : const Color(0xFF1976D2),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution(context.tr('© 高德地图')),
                      ],
                    ),
                  ],
                ),
                _mapModeButton('高德地图', Icons.map_outlined),
              ],
            )
          : Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _OfflineGeoPainter(ordered, widget.connectPoints),
                  ),
                ),
                _mapModeButton('离线概览', Icons.cloud_off_outlined),
              ],
            ),
    );
  }

  Widget _mapModeButton(String label, IconData icon) => Positioned(
    left: 9,
    top: 8,
    child: Material(
      color: Colors.white.withValues(alpha: .94),
      elevation: 2,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => setState(() {
          _online = !_online;
          _tileErrors = 0;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: const Color(0xFF39779F)),
              const SizedBox(width: 5),
              LocalizedText(
                label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF285F83)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.swap_horiz, size: 14, color: Color(0xFF66859D)),
            ],
          ),
        ),
      ),
    ),
  );

  GeoMapPoint _gcjPoint(GeoMapPoint point) {
    if (_outsideChina(point.latitude, point.longitude)) return point;
    final delta = _gcjDelta(point.latitude, point.longitude);
    return GeoMapPoint(
      latitude: point.latitude + delta.$1,
      longitude: point.longitude + delta.$2,
      label: point.label,
      order: point.order,
    );
  }

  bool _outsideChina(double lat, double lon) =>
      lon < 72.004 || lon > 137.8347 || lat < .8293 || lat > 55.8271;

  (double, double) _gcjDelta(double lat, double lon) {
    const axis = 6378245.0;
    const eccentricity = 0.006693421622965943;
    final x = lon - 105;
    final y = lat - 35;
    var dLat =
        -100 +
        2 * x +
        3 * y +
        .2 * y * y +
        .1 * x * y +
        .2 * math.sqrt(x.abs());
    dLat +=
        (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) *
        2 /
        3;
    dLat +=
        (20 * math.sin(y * math.pi) + 40 * math.sin(y / 3 * math.pi)) * 2 / 3;
    dLat +=
        (160 * math.sin(y / 12 * math.pi) + 320 * math.sin(y * math.pi / 30)) *
        2 /
        3;
    var dLon =
        300 + x + 2 * y + .1 * x * x + .1 * x * y + .1 * math.sqrt(x.abs());
    dLon +=
        (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) *
        2 /
        3;
    dLon +=
        (20 * math.sin(x * math.pi) + 40 * math.sin(x / 3 * math.pi)) * 2 / 3;
    dLon +=
        (150 * math.sin(x / 12 * math.pi) + 300 * math.sin(x / 30 * math.pi)) *
        2 /
        3;
    final radLat = lat / 180 * math.pi;
    var magic = math.sin(radLat);
    magic = 1 - eccentricity * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    dLat =
        dLat *
        180 /
        ((axis * (1 - eccentricity)) / (magic * sqrtMagic) * math.pi);
    dLon = dLon * 180 / (axis / sqrtMagic * math.cos(radLat) * math.pi);
    return (dLat, dLon);
  }
}

class _Bounds {
  const _Bounds(this.minLat, this.maxLat, this.minLon, this.maxLon);
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
}

class _OfflineGeoPainter extends CustomPainter {
  _OfflineGeoPainter(this.points, this.connectPoints);

  final List<GeoMapPoint> points;
  final bool connectPoints;

  static const _land = <List<Offset>>[
    [
      Offset(-168, 70),
      Offset(-138, 59),
      Offset(-126, 49),
      Offset(-123, 32),
      Offset(-104, 20),
      Offset(-82, 9),
      Offset(-77, 25),
      Offset(-60, 47),
      Offset(-82, 61),
      Offset(-108, 72),
    ],
    [
      Offset(-81, 12),
      Offset(-68, 5),
      Offset(-50, -2),
      Offset(-35, -8),
      Offset(-44, -24),
      Offset(-55, -40),
      Offset(-69, -55),
      Offset(-76, -34),
    ],
    [
      Offset(-11, 36),
      Offset(5, 44),
      Offset(28, 40),
      Offset(42, 53),
      Offset(75, 72),
      Offset(135, 68),
      Offset(169, 58),
      Offset(147, 42),
      Offset(130, 32),
      Offset(120, 22),
      Offset(105, 8),
      Offset(78, 8),
      Offset(57, 25),
      Offset(38, 31),
      Offset(30, 40),
      Offset(15, 36),
    ],
    [
      Offset(-17, 35),
      Offset(13, 37),
      Offset(34, 30),
      Offset(51, 12),
      Offset(43, -12),
      Offset(31, -35),
      Offset(17, -35),
      Offset(4, -18),
      Offset(-5, 5),
    ],
    [
      Offset(112, -11),
      Offset(154, -12),
      Offset(151, -38),
      Offset(132, -44),
      Offset(114, -31),
    ],
    [Offset(-52, 60), Offset(-20, 70), Offset(-27, 83), Offset(-56, 82)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = _visibleBounds();
    Offset project(double latitude, double longitude) => Offset(
      (longitude - bounds.minLon) /
          (bounds.maxLon - bounds.minLon) *
          size.width,
      (bounds.maxLat - latitude) /
          (bounds.maxLat - bounds.minLat) *
          size.height,
    );

    final grid = Paint()
      ..color = const Color(0xFF87B7D7).withValues(alpha: .20)
      ..strokeWidth = 1;
    final lonStep = (bounds.maxLon - bounds.minLon) <= 50 ? 10.0 : 30.0;
    final latStep = (bounds.maxLat - bounds.minLat) <= 35 ? 5.0 : 20.0;
    for (
      var lon = (bounds.minLon / lonStep).ceil() * lonStep;
      lon < bounds.maxLon;
      lon += lonStep
    ) {
      final x = project(0, lon).dx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (
      var lat = (bounds.minLat / latStep).ceil() * latStep;
      lat < bounds.maxLat;
      lat += latStep
    ) {
      final y = project(lat, 0).dy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final landFill = Paint()..color = const Color(0xFFD5EACF);
    final landLine = Paint()
      ..color = const Color(0xFF8EB48C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final polygon in _land) {
      final path = Path();
      for (var index = 0; index < polygon.length; index++) {
        final point = project(polygon[index].dy, polygon[index].dx);
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, landFill);
      canvas.drawPath(path, landLine);
    }

    final projected = points
        .map((point) => project(point.latitude, point.longitude))
        .toList();
    if (connectPoints && projected.length > 1) {
      final route = Path()..moveTo(projected.first.dx, projected.first.dy);
      for (final point in projected.skip(1)) {
        route.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        route,
        Paint()
          ..color = Colors.white.withValues(alpha: .9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      for (var index = 0; index < projected.length - 1; index++) {
        final progress = index / math.max(1, projected.length - 2);
        canvas.drawLine(
          projected[index],
          projected[index + 1],
          Paint()
            ..color = Color.lerp(
              const Color(0xFF65B9F4),
              const Color(0xFF007F7A),
              progress,
            )!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    final text = TextPainter(textDirection: TextDirection.ltr);
    for (var index = 0; index < points.length; index++) {
      final point = projected[index];
      final item = points[index];
      final color = index == points.length - 1
          ? const Color(0xFFE64A3B)
          : const Color(0xFF1976D2);
      canvas.drawCircle(point, 8, Paint()..color = Colors.white);
      canvas.drawCircle(point, 5.5, Paint()..color = color);
      final prefix = item.order == null ? '' : '${item.order} · ';
      text.text = TextSpan(
        text: '$prefix${item.label}',
        style: const TextStyle(
          color: Color(0xFF17425F),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );
      text.layout(maxWidth: math.min(130, size.width * .42));
      final labelX = (point.dx + 7)
          .clamp(3, size.width - text.width - 5)
          .toDouble();
      final labelY = (point.dy - text.height - 7)
          .clamp(27, size.height - 18)
          .toDouble();
      final bubble = RRect.fromRectAndRadius(
        Rect.fromLTWH(labelX - 4, labelY - 2, text.width + 8, text.height + 4),
        const Radius.circular(5),
      );
      canvas.drawRRect(
        bubble,
        Paint()..color = Colors.white.withValues(alpha: .92),
      );
      text.paint(canvas, Offset(labelX, labelY));
    }
    canvas.restore();
  }

  _Bounds _visibleBounds() {
    if (points.isEmpty) return const _Bounds(-60, 85, -180, 180);
    var minLat = points.map((p) => p.latitude).reduce(math.min);
    var maxLat = points.map((p) => p.latitude).reduce(math.max);
    var minLon = points.map((p) => p.longitude).reduce(math.min);
    var maxLon = points.map((p) => p.longitude).reduce(math.max);
    final latSpan = math.max(12.0, maxLat - minLat);
    final lonSpan = math.max(18.0, maxLon - minLon);
    final latCenter = (minLat + maxLat) / 2;
    final lonCenter = (minLon + maxLon) / 2;
    minLat = (latCenter - latSpan * .75).clamp(-85, 85);
    maxLat = (latCenter + latSpan * .75).clamp(-85, 85);
    minLon = (lonCenter - lonSpan * .75).clamp(-180, 180);
    maxLon = (lonCenter + lonSpan * .75).clamp(-180, 180);
    return _Bounds(minLat, maxLat, minLon, maxLon);
  }

  @override
  bool shouldRepaint(covariant _OfflineGeoPainter oldDelegate) => true;
}
