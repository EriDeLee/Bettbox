import 'package:bett_box/common/common.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/providers/app.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkSpeedSmall extends StatelessWidget {
  const NetworkSpeedSmall({super.key});

  // Cache as const
  static const _initPoints = [Point(0, 0), Point(1, 0)];

  static List<Point> _getPoints(List<Traffic> traffics) {
    if (traffics.isEmpty) return _initPoints;

    // Pre-allocate array capacity
    final totalLength = traffics.length + _initPoints.length;
    final result = List<Point>.filled(totalLength, Point(0, 0));

    // Assign init points
    result[0] = _initPoints[0];
    result[1] = _initPoints[1];

    // Assign traffic points
    for (int i = 0; i < traffics.length; i++) {
      result[i + 2] = Point((i + 2).toDouble(), traffics[i].speed.toDouble());
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return RepaintBoundary(
      child: SizedBox(
        height: getWidgetHeight(1),
        child: CommonCard(
          onPressed: () {
            globalState.openUrl('https://ispeedtest.appshub.cc');
          },
          info: Info(
            label: appLocalizations.networkSpeed,
            iconData: Icons.speed_sharp,
          ),
          child: Consumer(
            builder: (_, ref, _) {
              final traffics = ref.watch(
                trafficsProvider.select((state) => state.list),
              );
              final points = _getPoints(traffics);
              return Padding(
                padding: const EdgeInsets.only(
                  top: 16,
                  left: 0,
                  right: 0,
                  bottom: 0,
                ),
                child: LineChart(
                  gradient: true,
                  color: primaryColor,
                  points: points,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
