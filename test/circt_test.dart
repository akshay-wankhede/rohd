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

// TODO: test that exception is thrown if no support

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

class TopMod extends Module {
  TopMod(Logic a) {
    a = addInput('a', a);
    SVMod(a);
  }
}

void main() {
  test('unsupported exception', () async {
    var mod = TopMod(Logic());
    await mod.build();
    expect(() => mod.generateSynth(CIRCTSynthesizer()), throwsException);
  });
}
