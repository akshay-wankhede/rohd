/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// circt_test.dart
/// Unit tests for CIRCT generation
///
/// 2022 January 13
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class SVMod extends Module with CustomSystemVerilog {
  SVMod(Logic a) {
    a = addInput('a', a);
  }

  @override
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs) {
    return 'none';
  }
}

class TopModSV extends Module {
  TopModSV(Logic a) {
    a = addInput('a', a);
    SVMod(a);
  }
}

class CirctMod extends Module {
  CirctMod(Logic a, Logic b) : super(name: 'circtmod') {
    a = addInput('a', a);
    b = addInput('b', b);
    var notA = addOutput('notA');
    notA <= ~a;
  }
}

void main() {
  test('unsupported exception', () async {
    var mod = TopModSV(Logic());
    await mod.build();
    expect(() => mod.generateSynth(CIRCTSynthesizer()), throwsException);
  });

  test('simple gen', () async {
    var mod = CirctMod(Logic(), Logic());
    await mod.build();
    var gen = mod.generateSynth(CIRCTSynthesizer());
    print(gen);
  });
}
