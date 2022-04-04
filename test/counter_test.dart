/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// counter_test.dart
/// Unit tests for a basic counter
///
/// 2021 May 10
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:async';
// import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';
import 'package:rohd/src/utilities/simcompare.dart';

class Counter extends Module {
  final int width;
  Logic get val => output('val');
  Counter(Logic en, Logic reset, {this.width = 8}) : super(name: 'counter') {
    en = addInput('en', en);
    reset = addInput('reset', reset);

    var val = addOutput('val', width: width);

    var nextVal = Logic(name: 'nextVal', width: width);

    nextVal <= val + 1;

    Sequential.multi([
      SimpleClockGenerator(10).clk,
      reset
    ], [
      If(reset, then: [
        val < 0
      ], orElse: [
        If(en, then: [val < nextVal])
      ])
    ]);
  }
}

void main() {
  tearDown(() {
    Simulator.reset();
  });

  group('simcompare', () {
    test('counter', () async {
      var reset = Logic();
      var counter = Counter(Logic(), reset);
      await counter.build();
      // WaveDumper(counter);
      // File('tmp_counter.sv').writeAsStringSync(counter.generateSynth());

      // check that 1 timestep after reset, the value has reset properly
      unawaited(reset.nextPosedge
          .then((value) => Simulator.registerAction(Simulator.time + 1, () {
                expect(counter.val.value.toInt(), equals(0));
              })));

      var vectors = [
        Vector({'en': 0, 'reset': 0}, {}),
        Vector({'en': 0, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 1}),
        Vector({'en': 1, 'reset': 0}, {'val': 2}),
        Vector({'en': 1, 'reset': 0}, {'val': 3}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 1, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 5}),
      ];
      await SimCompare.checkFunctionalVector(counter, vectors);
      var simResult = SimCompare.iverilogVector(
          counter.generateSynth(), counter.runtimeType.toString(), vectors,
          signalToWidthMap: {'val': 8});
      expect(simResult, equals(true));
    });
  });
}
