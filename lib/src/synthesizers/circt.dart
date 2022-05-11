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
  bool generatesDefinition(Module module) =>
      module is ExternalSystemVerilogModule || module is! CustomFunctionality;

  @override
  SynthesisResult synthesize(
      Module module, Map<Module, String> moduleToInstanceTypeMap) {
    return _CirctSynthesisResult(module, moduleToInstanceTypeMap, this);
  }

  int _tempNameCounter = 0;
  String nextTempName() => '${_tempNameCounter++}';

  static String instantiationCirctWithParameters(
      Module module,
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer,
      {Map<String, String>? parameters,
      bool forceStandardInstantiation = false}) {
    if (!forceStandardInstantiation) {
      if (module is CustomCirct) {
        return module.instantiationCirct(
            instanceType, instanceName, inputs, outputs, synthesizer);
      } else if (module is CustomFunctionality) {
        throw Exception('Module $module defines custom functionality but not '
            'an implementation in CIRCT!');
      }
    }

    var portWidths = Map.fromEntries([
      ...inputs.keys.map((e) => MapEntry(e, module.input(e).width)),
      ...outputs.keys.map((e) => MapEntry(e, module.output(e).width))
    ]);

    var receiverStr = outputs.values.map((e) => '%$e').join(', ');
    var inputStr = inputs.entries
        .map((e) => '${e.key}: %${e.value}: i${portWidths[e.key]}')
        .join(', ');
    var outputStr = outputs.keys.map((e) => '$e: i${portWidths[e]}').join(', ');

    var parameterString = '';
    if (module is ExternalSystemVerilogModule) {
      if (module.parameters != null && module.parameters!.isNotEmpty) {
        parameterString = '<' +
            module.parameters!.entries.map((e) {
              var intValue = int.tryParse(e.value);
              if (intValue == null) {
                throw Exception(
                    'CIRCT exporter only supports integer parameters for external SV modules,'
                    ' but found ${e.value} for parameter ${e.key}');
              }
              return '${e.key}: i64 = $intValue';
            }).join(', ') +
            '>';
      }
    }

    var assignReciever = outputs.isEmpty ? '' : '$receiverStr = ';

    return '${assignReciever}hw.instance "$instanceName"'
        ' @$instanceType$parameterString ($inputStr) -> ($outputStr)';
  }

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

mixin VerbatimSystemVerilogCirct on CustomSystemVerilog implements CustomCirct {
  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    Map<String, String> remap(Map<String, String> original,
        [int startingPoint = 0]) {
      var entries = original.entries.toList();
      var remappedEntries = <MapEntry<String, String>>[];
      for (var i = 0; i < original.length; i++) {
        var entry = entries[i];
        remappedEntries.add(MapEntry(entry.key, '{{${i + startingPoint}}}'));
      }
      return Map.fromEntries(remappedEntries);
    }

    var remappedInputs = remap(inputs);
    var remappedOutputs = remap(outputs, inputs.length);
    var sv = instantiationVerilog(
        instanceType, instanceName, remappedInputs, remappedOutputs);

    //TODO: how to do multi-line strings so we don't have to remove comments and new-lines?
    sv = sv.replaceAll(RegExp(r'//.*\n'), '');
    sv = sv.replaceAll('\n', '  ');

    var arguments =
        [...inputs.values, ...outputs.values].map((e) => '%$e').join(', ');
    var widths = [
      ...inputs.keys.map((e) => input(e).width),
      ...outputs.keys.map((e) => output(e).width)
    ].map((e) => 'i$e').join(', ');

    //TODO: is it really necessary to define local logic's here?
    var outputDeclarations = outputs.entries.map((e) {
      var tmpName = synthesizer.nextTempName();
      var width = output(e.key).width;
      return [
        '%$tmpName = sv.reg : !hw.inout<i$width>',
        '%${e.value} = sv.read_inout %$tmpName : !hw.inout<i$width>'
      ].join('\n');
    }).join('\n');

    var circtOut = [
      outputDeclarations,
      'sv.verbatim "$sv" ($arguments) : $widths',
    ].join('\n');

    return circtOut;
  }
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
    _moduleContentsString =
        _circtModuleContents(moduleToInstanceTypeMap, synthesizer);
  }

  static String _referenceName(SynthLogic synthLogic) {
    if (synthLogic.width == 0) {
      throw Exception('Should not reference zero-width signals.');
    }

    if (synthLogic.isConst) {
      throw Exception(
          'Cannot reference a constant, must separately declare it.');
    } else {
      return synthLogic.name;
    }
  }

  String _circtModuleContents(Map<Module, String> moduleToInstanceTypeMap,
      CirctSynthesizer synthesizer) {
    return [
      _circtAssignments(synthesizer),
      subModuleInstantiations(moduleToInstanceTypeMap), //TODO
    ].join('\n');
  }

  String _circtAssignments(CirctSynthesizer synthesizer) {
    var assignmentLines = <String>[];
    for (var assignment in synthModuleDefinition.assignments) {
      var tmpName = synthesizer.nextTempName();
      var width = assignment.dst.width;

      String srcName;
      if (assignment.src.isConst) {
        var constant = assignment.src.constant;
        if (constant.isValid) {
          //TODO: need to handle potential BigInt?
          srcName = synthesizer.nextTempName();
          assignmentLines.add(
              '%$srcName = hw.constant ${constant.toBigInt()} : i${constant.width}');
        } else {
          //TODO: handle CIRCT invalid constants
          throw UnimplementedError(
              "Don't know how to generate bitwise invalid vector in CIRCT yet...");
        }
      } else {
        srcName = _referenceName(assignment.src);
      }

      var dstName = assignment.dst.name;
      assignmentLines.add([
        '%$tmpName = sv.reg : !hw.inout<i$width>',
        'sv.assign %$tmpName, %$srcName : i$width',
        '%$dstName = sv.read_inout %$tmpName : !hw.inout<i$width>'
      ].join('\n'));
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
    return synthModuleDefinition.outputs.isEmpty
        ? ''
        : 'hw.output ' +
            synthModuleDefinition.outputs
                .map((e) => '%' + _referenceName(e))
                .join(', ') +
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

    if (module is ExternalSystemVerilogModule) {
      var extModule = module as ExternalSystemVerilogModule;

      var parameterString = '';
      if (extModule.parameters != null && extModule.parameters!.isNotEmpty) {
        parameterString = '<' +
            extModule.parameters!.keys.map((e) => '$e: i64').join(', ') +
            '>';
      }

      return [
        'hw.module.extern @$circtModuleName$parameterString($_inputsString) -> ($_outputsString)',
        '  attributes { verilogName="${extModule.topModuleName}" }'
      ].join('\n');
    }

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

    // if all the outputs have zero-width, we don't need to generate anything at all
    // but if there's no outputs, then its ok to keep it
    if (outputMapping.isNotEmpty) {
      var totalOutputWidth =
          outputMapping.values.map((e) => e.width).reduce((a, b) => a + b);
      if (totalOutputWidth == 0) return null;
    }

    // collect consts for CIRCT, since you can't in-line them
    var constMap = <SynthLogic, String>{};
    var constDefinitions = <String>[];
    for (var inputSynthLogic in inputMapping.keys) {
      if (inputSynthLogic.isConst) {
        if (inputSynthLogic.logic.width == 0) {
          // shouldn't be using zero-width constants anywhere, omit them
          constMap[inputSynthLogic] = 'INVALID_ZERO_WIDTH_CONST';
        } else {
          var constName = synthesizer.nextTempName();
          //TODO: does this really need to be BigInt?
          constDefinitions.add('%$constName = hw.constant '
              '${inputSynthLogic.constant.toBigInt()} : '
              'i${inputSynthLogic.logic.width}\n');
          constMap[inputSynthLogic] = constName;
        }
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
        );
  }

  String _instantiationCirct(String instanceType, Map<String, String> inputs,
      Map<String, String> outputs) {
    return CirctSynthesizer.instantiationCirctWithParameters(
        module, instanceType, name, inputs, outputs, synthesizer);
  }
}
