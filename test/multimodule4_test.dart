/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// multimodule4_test.dart
/// Unit tests for a hierarchy of multiple modules and multiple instantiation (another type)
///
/// 2021 June 30
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/passthrough.dart';
import 'package:test/test.dart';

// mostly all inputs
class InnerModule2 extends Module {
  Logic get z => output('z');
  InnerModule2() : super(name: 'innermodule2') {
    addOutput('z');
    z <= Const(1);
  }
}

class InnerModule1 extends Module {
  InnerModule1(Logic y) : super(name: 'innermodule1') {
    y = addInput('y', y);
    var m = Logic();
    m <= Passthrough(InnerModule2().z).b | y;
  }
}

class TopModule extends Module {
  TopModule(Logic x) : super(name: 'topmod') {
    x = addInput('x', x);
    InnerModule1(x);
  }
}

void main() {
  tearDown(() {
    Simulator.reset();
  });

  test('multimodules4 native sv', () async {
    var ftm = TopModule(Logic());
    await ftm.build();

    // find a module with 'z' output 2 levels deep
    assert(ftm.subModules
        .where((pIn1) => pIn1.subModules
            .where((pIn2) => pIn2.outputs.containsKey('z'))
            .isNotEmpty)
        .isNotEmpty);

    var synth = ftm.generateSynth(SystemVerilogSynthesizer());

    // "z = 1" means it correctly traversed down from inputs
    expect(synth, contains('z = 1'));
  });

  test('multimodules4 circt', () async {
    var ftm = TopModule(Logic());
    await ftm.build();

    // find a module with 'z' output 2 levels deep
    assert(ftm.subModules
        .where((pIn1) => pIn1.subModules
            .where((pIn2) => pIn2.outputs.containsKey('z'))
            .isNotEmpty)
        .isNotEmpty);

    var synth = CirctSynthesizer.convertCirctToSystemVerilog(
        ftm.generateSynth(CirctSynthesizer()));

    // "z = 1" means it correctly traversed down from inputs
    expect(synth, contains("_T = 1'h1"));
    expect(synth, contains('z = _T'));
  });
}
