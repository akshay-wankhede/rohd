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

class CirctMod extends Module with CustomCirct {
  CirctMod(Logic a) {
    a = addInput('a', a);
  }

  @override
  String instantiationCirct(
          String instanceType,
          String instanceName,
          Map<String, String> inputs,
          Map<String, String> outputs,
          CirctSynthesizer synthesizer) =>
      'none';
}

class TopMod extends Module {
  TopMod(Logic a) {
    a = addInput('a', a);
    CirctMod(a);
  }
}

void main() {
  test('unsupported exception', () async {
    final mod = TopMod(Logic());
    await mod.build();
    expect(
        () => mod.generateSynth(SystemVerilogSynthesizer()), throwsException);
  });
}
