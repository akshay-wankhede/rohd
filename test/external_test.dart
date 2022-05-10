/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// external_test.dart
/// Unit tests for external modules
///
/// 2022 January 7
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class MyExternalModule extends ExternalSystemVerilogModule {
  MyExternalModule(Logic a, {int width = 2})
      : super(
            topModuleName: 'external_module_name',
            parameters: {'WIDTH': '$width'}) {
    addInput('a', a, width: width);
    addOutput('b', width: width);
  }
}

class TopModule extends Module {
  TopModule(Logic a) {
    a = addInput('a', a, width: a.width);
    MyExternalModule(a);
  }
}

//TODO: add a test that actually simulates with an external module
//TODO: add tests that use various types of parameters (external types, ints, etc.)

void main() {
  group('instantiate', () {
    test('sv', () async {
      var mod = TopModule(Logic(width: 2));
      await mod.build();
      var sv = mod.generateSynth(SystemVerilogSynthesizer());
      expect(
          sv,
          contains(
              'external_module_name #(.WIDTH(2)) external_module(.a(a),.b(b));'));
    });

    // TODO: fix checking on this external test
    test('circt', () async {
      var mod = TopModule(Logic(width: 2));
      await mod.build();
      var sv = CirctSynthesizer.convertCirctToSystemVerilog(
          mod.generateSynth(CirctSynthesizer()));
      File('tmp.sv').writeAsStringSync(sv);
      // expect(
      //     sv,
      //     contains(
      //         'external_module_name #(.WIDTH(2)) external_module(.a(a),.b(b));'));
    });
  });
}
