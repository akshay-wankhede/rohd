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

  static String definitionName(int width, String name) {
    return '%$name: i$width';
  }
}

class _CIRCTSynthesisResult extends SynthesisResult {
  /// A cached copy of the generated ports
  late final String _inputsString;

  late final String _outputsString;

  /// A cached copy of the generated contents of the module
  late final String _moduleContentsString;

  final SynthModuleDefinition _synthModuleDefinition;

  _CIRCTSynthesisResult(
      Module module, Map<Module, String> moduleToInstanceTypeMap)
      : _synthModuleDefinition = SynthModuleDefinition(module,
            ssmiBuilder: (Module m, String instantiationName) =>
                CIRCTSynthSubModuleInstantiation(m, instantiationName)),
        super(module, moduleToInstanceTypeMap) {
    _inputsString = _circtInputs();
    _outputsString = _circtOutputs();
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
      // _verilogSubModuleInstantiations(moduleToInstanceTypeMap), //TODO
    ].join('\n');
  }

  String _circtAssignments() {
    var assignmentLines = [];
    for (var assignment in _synthModuleDefinition.assignments) {
      assignmentLines
          .add('${assignment.dst.name} = ${_referenceName(assignment.src)};');
    }
    return assignmentLines.join('\n');
  }

  String _circtInputs() {
    return _synthModuleDefinition.inputs
        .map(
            (sig) => CIRCTSynthesizer.definitionName(sig.logic.width, sig.name))
        .join(',\n');
  }

  String _circtOutputs() {
    return 'hw.output ' +
        _synthModuleDefinition.outputs
            .map((e) => _referenceName(e))
            .join(', ') +
        ' : ' +
        _synthModuleDefinition.outputs
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
      'hw.module @$circtModuleName(',
      _inputsString,
      ') {',
      _moduleContentsString,
      '}'
    ].join('\n');
  }
}

class CIRCTSynthSubModuleInstantiation extends SynthSubModuleInstantiation {
  CIRCTSynthSubModuleInstantiation(Module module, String name)
      : super(module, name);

  @override
  String? instantiationCode(String instanceType) {
    throw UnimplementedError();
    return 'hw.instance "$name" @$instanceType'; // TODO: inputs and outputs here!
  }
}
