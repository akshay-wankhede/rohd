/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// circt.dart
/// Definition for CIRCT Synthesizer
///
/// 2022 January 12
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

class CirctSynthesizer extends Synthesizer {
  @override
  bool generatesDefinition(Module module) => module is! CustomFunctionality;

  @override
  SynthesisResult synthesize(
      Module module, Map<Module, String> moduleToInstanceTypeMap) {
    return _CirctSynthesisResult(module, moduleToInstanceTypeMap, this);
  }

  int _tempNameCounter = 0;
  String nextTempName() => '${_tempNameCounter++}';

  static String convertCirctToSystemVerilog(String circtContents,
      {String? circtBinPath, bool deleteTemporaryFiles = true}) {
    var dir = 'tmp_circt';
    var uniqueId = circtContents.hashCode;
    var tmpCirctFile = '$dir/tmp_circt$uniqueId.mlir';
    var tmpParsedCirctFile = '$dir/tmp_circt$uniqueId.out.mlir';

    Directory(dir).createSync(recursive: true);
    File(tmpCirctFile).writeAsStringSync(circtContents);

    var circtOptExecutable = [
      if (circtBinPath != null) circtBinPath,
      'circt-opt',
    ].join('/');

    var circtResult = Process.runSync(circtOptExecutable,
        ['-export-verilog', '-o=$tmpParsedCirctFile', tmpCirctFile]);

    if (circtResult.exitCode != 0) {
      print(circtResult.stdout);
      print(circtResult.stderr);
      throw Exception(
          'Failed to export verilog from CIRCT, exit code: ${circtResult.exitCode}');
    }

    if (deleteTemporaryFiles) {
      File(tmpCirctFile).deleteSync();
      File(tmpParsedCirctFile).deleteSync();
    }

    var svCode = circtResult.stdout;

    return svCode;
  }
}

mixin CustomCirct on Module implements CustomFunctionality {
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer);
}

class _CirctSynthesisResult extends SynthesisResult {
  /// A cached copy of the generated ports
  late final String _inputsString;

  late final String _outputsString;
  late final String _outputsFooter;

  /// A cached copy of the generated contents of the module
  late final String _moduleContentsString;

  _CirctSynthesisResult(Module module,
      Map<Module, String> moduleToInstanceTypeMap, CirctSynthesizer synthesizer)
      : super(
            module,
            moduleToInstanceTypeMap,
            synthesizer,
            SynthModuleDefinition(module,
                ssmiBuilder: (Module m, String instantiationName) =>
                    CirctSynthSubModuleInstantiation(
                        m, instantiationName, synthesizer))) {
    _inputsString = _circtInputs();
    _outputsString = _circtOutputs();
    _outputsFooter = _circtOutputFooter();
    _moduleContentsString = _circtModuleContents(moduleToInstanceTypeMap);
  }

  static String _referenceName(SynthLogic synthLogic) {
    if (synthLogic.isConst) {
      var constant = synthLogic.constant;
      if (constant.isValid) {
        //TODO: need to handle potential BigInt?
        return 'hw.constant ${constant.toInt()} : i${constant.width}';
      } else {
        //TODO: handle CIRCT invalid constants
        throw UnimplementedError(
            "Don't know how to generate bitwise invalid vector in CIRCT yet...");
      }
    } else {
      return '%${synthLogic.name}';
    }
  }

  String _circtModuleContents(Map<Module, String> moduleToInstanceTypeMap) {
    return [
      _circtAssignments(),
      subModuleInstantiations(moduleToInstanceTypeMap), //TODO
    ].join('\n');
  }

  String _circtAssignments() {
    var assignmentLines = [];
    for (var assignment in synthModuleDefinition.assignments) {
      assignmentLines
          .add('${assignment.dst.name} = ${_referenceName(assignment.src)};');
    }
    return assignmentLines.join('\n');
  }

  String _circtInputs() {
    return synthModuleDefinition.inputs
        .map((sig) => '%${sig.name}: i${sig.logic.width}')
        .join(', ');
  }

  String _circtOutputs() {
    return synthModuleDefinition.outputs
        .map((sig) => '${sig.name}: i${sig.logic.width}')
        .join(', ');
  }

  String _circtOutputFooter() {
    return 'hw.output ' +
        synthModuleDefinition.outputs.map((e) => _referenceName(e)).join(', ') +
        ' : ' +
        synthModuleDefinition.outputs
            .map((e) => 'i${e.logic.width}')
            .join(', ');
  }

  @override
  int get matchHashCode =>
      _inputsString.hashCode ^
      _outputsString.hashCode ^
      _outputsFooter.hashCode ^
      _moduleContentsString.hashCode;

  @override
  bool matchesImplementation(SynthesisResult other) =>
      other is _CirctSynthesisResult &&
      other._inputsString == _inputsString &&
      other._outputsString == _outputsString &&
      other._outputsFooter == _outputsFooter &&
      other._moduleContentsString == _moduleContentsString;

  @override
  String toFileContents() {
    return _toCirct(moduleToInstanceTypeMap);
  }

  String _toCirct(Map<Module, String> moduleToInstanceTypeMap) {
    var circtModuleName = moduleToInstanceTypeMap[module];
    return [
      'hw.module @$circtModuleName($_inputsString) -> ($_outputsString) {',
      _moduleContentsString,
      _outputsFooter,
      '}'
    ].join('\n');
  }
}

class CirctSynthSubModuleInstantiation extends SynthSubModuleInstantiation {
  CirctSynthesizer synthesizer;
  CirctSynthSubModuleInstantiation(Module module, String name, this.synthesizer)
      : super(module, name);

  @override
  String? instantiationCode(String instanceType) {
    if (!needsDeclaration) return null;

    // collect consts for CIRCT, since you can't in-line them
    var constMap = <SynthLogic, String>{};
    var constDefinitions = <String>[];
    for (var inputSynthLogic in inputMapping.keys) {
      if (inputSynthLogic.isConst) {
        var constName = synthesizer.nextTempName();
        //TODO: does this really need to be BigInt?
        constDefinitions.add('%$constName = hw.constant '
            '${inputSynthLogic.constant.toBigInt()} : '
            'i${inputSynthLogic.logic.width}\n');
        constMap[inputSynthLogic] = constName;
      }
    }

    return constDefinitions.join() +
        _instantiationCirct(
            instanceType,
            inputMapping.map((synthLogic, logic) => MapEntry(
                logic.name, // port name guaranteed to match
                constMap[synthLogic] ?? synthLogic.name)),
            outputMapping.map((synthLogic, logic) => MapEntry(
                logic.name, // port name guaranteed to match
                synthLogic.name)),
            Map.fromEntries([...inputMapping.values, ...outputMapping.values]
                .map((e) => MapEntry(e.name, e.width))));
  }

  String _instantiationCirct(String instanceType, Map<String, String> inputs,
      Map<String, String> outputs, Map<String, int> portWidths) {
    if (module is CustomCirct) {
      return (module as CustomCirct)
          .instantiationCirct(instanceType, name, inputs, outputs, synthesizer);
    } else if (module is CustomFunctionality) {
      throw Exception('Module $module defines custom functionality but not'
          'an implementation in CIRCT!');
    }
    //TODO: add a CIRCT verbatim for SystemVerilog available ones
    var receiverStr = outputs.values.map((e) => '%$e').join(', ');
    var inputStr = inputs.entries
        .map((e) => '${e.key} %${e.value}: i${portWidths[e.key]}')
        .join(', ');
    var outputStr = outputs.keys.map((e) => '$e: ${portWidths[e]}');

    return '$receiverStr = hw.instance "$name"'
        ' @$instanceType ($inputStr) -> ($outputStr)';
  }
}
