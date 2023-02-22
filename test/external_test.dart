/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// external_test.dart
/// Unit tests for external modules
///
/// 2022 January 7
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class MyExternalModule extends ExternalSystemVerilogModule {
  Logic get b => output('b');
  MyExternalModule(Logic a, {int width = 2})
      : super(
            definitionName: 'external_module_name',
            parameters: {'WIDTH': '$width'}) {
    addInput('a', a, width: width);
    addOutput('b', width: width);
  }

  static String get testExternalVerilog => '''
module external_module_name #(parameter int WIDTH=2) (
  input [WIDTH-1:0] a,
  output [WIDTH-1:0] b
);

assign b = ~a;

endmodule

''';
}

class TopModule extends Module {
  TopModule(Logic a) {
    a = addInput('a', a, width: a.width);
    final b = addOutput('b', width: a.width);
    b <= MyExternalModule(a, width: a.width).b;
  }
}

//TODO: add tests that use various types of parameters (external types, ints, etc.)

void main() {
  group('instantiate', () {
    test('sv', () async {
      final mod = TopModule(Logic(width: 2));
      await mod.build();
      final sv = mod.generateSynth(SystemVerilogSynthesizer());
      expect(
          sv,
          contains(
              'external_module_name #(.WIDTH(2)) external_module(.a(a),.b(b));'));
    });

    test('circt', () async {
      final mod = TopModule(Logic(width: 2));
      await mod.build();
      final sv = CirctSynthesizer.convertCirctToSystemVerilog(
          mod.generateSynth(CirctSynthesizer()));
      expect(sv, contains('external_module_name #('));
      expect(sv, contains(".WIDTH(64'd2)"));
    });
  });

  group('simulate', () {
    final vectors = [
      Vector({'a': 0xff}, {'b': 0}),
      Vector({'a': 0xa5}, {'b': 0x5a}),
    ];

    tearDown(() async {
      await Simulator.reset();
    });

    test('native rohd sv generated', () async {
      final mod = TopModule(Logic(width: 8));
      await mod.build();
      final simResult = SimCompare.iverilogVector(mod, vectors,
          generatedVerilog: MyExternalModule.testExternalVerilog +
              mod.generateSynth(SystemVerilogSynthesizer()));
      expect(simResult, equals(true));
    });

    test('circt sv generated', () async {
      final mod = TopModule(Logic(width: 8));
      await mod.build();
      final simResult = SimCompare.iverilogVector(
        mod,
        vectors,
        generatedVerilog: MyExternalModule.testExternalVerilog +
            CirctSynthesizer.convertCirctToSystemVerilog(
                mod.generateSynth(CirctSynthesizer())),
      );
      expect(simResult, equals(true));
    });

    //TODO circt test too
    test('instantiate', () async {
      final mod = TopModule(Logic(width: 2));
      await mod.build();
      final sv = mod.generateSynth(SystemVerilogSynthesizer());
      expect(
          sv,
          contains(
              'external_module_name #(.WIDTH(2)) external_module(.a(a),.b(b));'));
    });
  });
}
