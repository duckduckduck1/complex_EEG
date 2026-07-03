import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/bloc/rt_eeg_data_bloc.dart';
import 'package:iot/fuetures/main_page/widgets/apps/eeg_widget/eeg_widget.dart';

Future<Widget?> showAppSelectorDialog(BuildContext context) async {
  double _xval = 0;
  final RtEegDataBloc bloc = RtEegDataBloc(250);
  Timer timer = Timer.periodic(Duration(milliseconds: 4), (timer) {
    // TODO: Заменить поток данных на данные ээг
    double newData =
        10 *
            math.sin(2 * math.pi * _xval * 2) *
            math.Random().nextDouble() *
            0.5 -
        0.25 +
        14 *
            math.sin(2 * math.pi * _xval * 3) *
            math.Random().nextDouble() *
            0.5 -
        0.25 +
        12 * math.sin(2 * math.pi * _xval * 6) * math.Random().nextDouble() -
        0.5 +
        5 *
            math.sin(2 * math.pi * _xval * 50) *
            math.Random().nextDouble() *
            0.5 -
        0.25 +
        10 *
            math.sin(2 * math.pi * _xval * 25) *
            math.Random().nextDouble() *
            0.5 -
        0.25 +
        10 *
            math.sin(2 * math.pi * _xval + 14) *
            math.Random().nextDouble() *
            0.5 -
        0.25;
    bloc.add(NewEegDataReceived(newEegData: newData));
    _xval += 0.004;
  });
  return await showDialog<Widget>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Select app'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('EEG app'),
              onTap: () {
                Navigator.pop(context, EegWidget(rtEegDataBloc: bloc));
              },
            ),
          ],
        ),
      );
    },
  );
}
