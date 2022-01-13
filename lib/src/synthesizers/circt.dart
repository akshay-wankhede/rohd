/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// circt.dart
/// Definition for CIRCT Synthesizer
///
/// 2022 January 12
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

class CIRCTSynthesizer extends Synthesizer {
  @override
  bool generatesDefinition(Module module) => module is! CustomFunctionality;

  @override
  SynthesisResult synthesize(
      Module module, Map<Module, String> moduleToInstanceTypeMap) {
    // TODO: implement synthesize
    throw UnimplementedError();
  }

  static String instantiationCIRCT(
      Module module,
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      Map<String, int> portWidths) {
    var receiverStr = outputs.values.map((e) => '%$e').join(', ');
    var inputStr = inputs.entries
        .map((e) => '${e.key} %${e.value}: i${portWidths[e.key]}')
        .join(', ');
    var outputStr = outputs.keys.map((e) => '$e: ${portWidths[e]}');

    return '$receiverStr = hw.instance "$instanceName" @$instanceType ($inputStr) -> ($outputStr)';
  }
}

class _CIRCTSynthesisResult extends SynthesisResult {
  /// A cached copy of the generated ports
  late final String _inputsString;

  late final String _outputsString;
  late final String _outputsFooter;

  /// A cached copy of the generated contents of the module
  late final String _moduleContentsString;

  _CIRCTSynthesisResult(Module module,
      Map<Module, String> moduleToInstanceTypeMap, CIRCTSynthesizer synthesizer)
      : super(
            module,
            moduleToInstanceTypeMap,
            synthesizer,
            SynthModuleDefinition(module,
                ssmiBuilder: (Module m, String instantiationName) =>
                    CIRCTSynthSubModuleInstantiation(m, instantiationName))) {
    _inputsString = _circtInputs();
    _outputsString = _circtOutputs();
    _outputsFooter = _circtOutputFooter();
    _moduleContentsString = _circtModuleContents(moduleToInstanceTypeMap);
  }

  static String _referenceName(SynthLogic synthLogic) {
    if (synthLogic.isConst) {
      var constant = synthLogic.constant;
      if (constant.isValid) {
        return 'hw.constant ${constant.toInt()} : i${constant.length}';
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
        .join(',\n');
  }

  String _circtOutputs() {
    return synthModuleDefinition.outputs
        .map((sig) => '${sig.name}: i${sig.logic.width}')
        .join(',\n');
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
  // TODO: implement matchHashCode
  int get matchHashCode => throw UnimplementedError();

  @override
  bool matchesImplementation(SynthesisResult other) {
    // TODO: implement matchesImplementation
    throw UnimplementedError();
  }

  @override
  String toFileContents() {
    // TODO: implement toFileContents
    throw UnimplementedError();
  }

  String _toCIRCT(Map<Module, String> moduleToInstanceTypeMap) {
    var circtModuleName = moduleToInstanceTypeMap[module];
    return [
      'hw.module @$circtModuleName($_inputsString) -> ($_outputsString) {',
      _moduleContentsString,
      _outputsFooter,
      '}'
    ].join('\n');
  }
}

class CIRCTSynthSubModuleInstantiation extends SynthSubModuleInstantiation {
  CIRCTSynthSubModuleInstantiation(Module module, String name)
      : super(module, name);

  @override
  String? instantiationCode(String instanceType) {
    if (!needsDeclaration) return null;
    return CIRCTSynthesizer.instantiationCIRCT(
        module,
        instanceType,
        name,
        inputMapping.map((synthLogic, logic) => MapEntry(
            logic.name, // port name guaranteed to match
            synthLogic.name)),
        outputMapping.map((synthLogic, logic) => MapEntry(
            logic.name, // port name guaranteed to match
            synthLogic.name)),
        Map.fromEntries([...inputMapping.values, ...outputMapping.values]
            .map((e) => MapEntry(e.name, e.width))));
  }
}
