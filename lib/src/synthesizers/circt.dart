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
          Module module, Map<Module, String> moduleToInstanceTypeMap) =>
      _CirctSynthesisResult(module, moduleToInstanceTypeMap, this);

  final Map<Object, int> _tempNameCounters = {};

  /// Returns the next temporary name within the specified context.
  ///
  /// Typically, context would be the parent module.
  String nextTempName(Object context) => _tempNameCounters
      .update(
        context,
        (value) => value + 1,
        ifAbsent: () => 0,
      )
      .toString();

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

    final portWidths = Map.fromEntries([
      // ignore: invalid_use_of_protected_member
      ...inputs.keys.map((e) => MapEntry(e, module.input(e).width)),
      ...outputs.keys.map((e) => MapEntry(e, module.output(e).width))
    ]);

    final receiverStr = outputs.values.map((e) => '%$e').join(', ');
    final inputStr = inputs.entries
        .map((e) => '${e.key}: %${e.value}: i${portWidths[e.key]}')
        .join(', ');
    final outputStr =
        outputs.keys.map((e) => '$e: i${portWidths[e]}').join(', ');

    var parameterString = '';
    if (module is ExternalSystemVerilogModule) {
      if (module.parameters != null && module.parameters!.isNotEmpty) {
        parameterString = '<${module.parameters!.entries.map((e) {
          final intValue = int.tryParse(e.value);
          if (intValue == null) {
            throw Exception(
                'CIRCT exporter only supports integer parameters for'
                ' external SV modules, but found ${e.value} for'
                ' parameter ${e.key}');
          }
          return '${e.key}: i64 = $intValue';
        }).join(', ')}>';
      }
    }

    final assignReciever = outputs.isEmpty ? '' : '$receiverStr = ';

    return '${assignReciever}hw.instance "$instanceName"'
        ' @$instanceType$parameterString ($inputStr) -> ($outputStr)';
  }

  static String convertCirctToSystemVerilog(String circtContents,
      {String? circtBinPath, bool deleteTemporaryFiles = true}) {
    const dir = 'tmp_circt';
    final uniqueId = circtContents.hashCode;
    final tmpCirctFile = '$dir/tmp_circt$uniqueId.mlir';
    final tmpParsedCirctFile = '$dir/tmp_circt$uniqueId.out.mlir';

    Directory(dir).createSync(recursive: true);
    File(tmpCirctFile).writeAsStringSync(circtContents);

    final circtOptExecutable = [
      if (circtBinPath != null) circtBinPath,
      'circt-opt',
    ].join('/');

    final circtResult = Process.runSync(circtOptExecutable,
        ['-export-verilog', '-o=$tmpParsedCirctFile', tmpCirctFile]);

    if (circtResult.exitCode != 0) {
      // ignore: avoid_print
      print('STDOUT:\n${circtResult.stdout}');
      // ignore: avoid_print
      print('STDERR:\n${circtResult.stderr}');
      throw Exception('Failed to export verilog from CIRCT,'
          ' exit code: ${circtResult.exitCode}');
    }

    if (deleteTemporaryFiles) {
      File(tmpCirctFile).deleteSync();
      File(tmpParsedCirctFile).deleteSync();
    }

    final svCode = circtResult.stdout as String;

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
      final entries = original.entries.toList();
      final remappedEntries = <MapEntry<String, String>>[];
      for (var i = 0; i < original.length; i++) {
        final entry = entries[i];
        remappedEntries.add(MapEntry(entry.key, '{{${i + startingPoint}}}'));
      }
      return Map.fromEntries(remappedEntries);
    }

    final remappedInputs = remap(inputs);
    final remappedOutputs = remap(outputs, inputs.length);
    var sv = instantiationVerilog(
        instanceType, instanceName, remappedInputs, remappedOutputs);

    // TODO(mkorbel1): how to do multi-line strings so we don't have to
    //  remove comments and new-lines?
    //  What???  Why do we need this at all?
    sv = sv.replaceAll(RegExp(r'//.*\n'), '');
    sv = sv.replaceAll('\n', '  ');

    final arguments =
        [...inputs.values, ...outputs.values].map((e) => '%$e').join(', ');
    final widths = [
      ...inputs.keys.map((e) => input(e).width),
      ...outputs.keys.map((e) => output(e).width)
    ].map((e) => 'i$e').join(', ');

    // TODO(mkorbel1): is it really necessary to define local logic's here?
    final outputDeclarations = outputs.entries.map((e) {
      final tmpName = synthesizer.nextTempName(parent!);
      final width = output(e.key).width;
      return [
        '%$tmpName = sv.reg : !hw.inout<i$width>',
        '%${e.value} = sv.read_inout %$tmpName : !hw.inout<i$width>'
      ].join('\n');
    }).join('\n');

    final circtOut = [
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
                ssmiBuilder: (m, instantiationName) =>
                    CirctSynthSubModuleInstantiation(
                        m, instantiationName, synthesizer))) {
    _inputsString = _circtInputs();
    _outputsString = _circtOutputs();
    _outputsFooter = _circtOutputFooter();
    _moduleContentsString =
        _circtModuleContents(moduleToInstanceTypeMap, synthesizer, module);
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
          CirctSynthesizer synthesizer, Module module) =>
      [
        _circtAssignments(synthesizer, module),
        subModuleInstantiations(moduleToInstanceTypeMap),
      ].join('\n');

  String _circtAssignments(CirctSynthesizer synthesizer, Module module) {
    final assignmentLines = <String>[];
    for (final assignment in synthModuleDefinition.assignments) {
      final tmpName = synthesizer.nextTempName(module);
      final width = assignment.dst.width;

      String srcName;
      if (assignment.src.isConst) {
        final constant = assignment.src.constant;
        if (constant.isValid) {
          // TODO(mkorbel1): need to handle potential BigInt?
          srcName = synthesizer.nextTempName(module);
          assignmentLines.add(constant._toCirctDefinition(
              srcName, () => synthesizer.nextTempName(module.parent!)));
        } else {
          // TODO(mkorbel1): handle CIRCT invalid constants here too
          throw UnimplementedError(
              "Don't know how to generate bitwise invalid vector"
              ' in CIRCT yet...');
        }
      } else {
        srcName = _referenceName(assignment.src);
      }

      final dstName = assignment.dst.name;
      assignmentLines.add([
        '%$tmpName = sv.reg : !hw.inout<i$width>',
        'sv.assign %$tmpName, %$srcName : i$width',
        '%$dstName = sv.read_inout %$tmpName : !hw.inout<i$width>'
      ].join('\n'));
    }
    return assignmentLines.join('\n');
  }

  String _circtInputs() => synthModuleDefinition.inputs
      .map((sig) => '%${sig.name}: i${sig.logic.width}')
      .join(', ');

  String _circtOutputs() => synthModuleDefinition.outputs
      .map((sig) => '${sig.name}: i${sig.logic.width}')
      .join(', ');

  String _circtOutputFooter() => synthModuleDefinition.outputs.isEmpty
      ? ''
      : 'hw.output'
          ' ${synthModuleDefinition.outputs.map((e) => '%${_referenceName(e)}').join(', ')} :'
          ' ${synthModuleDefinition.outputs.map((e) => 'i${e.logic.width}').join(', ')}';

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
  String toFileContents() => _toCirct(moduleToInstanceTypeMap);

  String _toCirct(Map<Module, String> moduleToInstanceTypeMap) {
    final circtModuleName = moduleToInstanceTypeMap[module];

    if (module is ExternalSystemVerilogModule) {
      final extModule = module as ExternalSystemVerilogModule;

      var parameterString = '';
      if (extModule.parameters != null && extModule.parameters!.isNotEmpty) {
        parameterString =
            '<${extModule.parameters!.keys.map((e) => '$e: i64').join(', ')}>';
      }

      return [
        'hw.module.extern @$circtModuleName$parameterString($_inputsString) -> ($_outputsString)',
        '  attributes { verilogName="${extModule.definitionName}" }'
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
  CirctSynthSubModuleInstantiation(super.module, super.name, this.synthesizer);

  @override
  String? instantiationCode(String instanceType) {
    if (!needsDeclaration) {
      return null;
    }

    // if all the outputs have zero-width, we don't need to generate
    // anything at all but if there's no outputs, then its ok to keep it
    if (outputMapping.isNotEmpty) {
      final totalOutputWidth =
          outputMapping.values.map((e) => e.width).reduce((a, b) => a + b);
      if (totalOutputWidth == 0) {
        return null;
      }
    }

    // collect consts for CIRCT, since you can't in-line them
    final constMap = <SynthLogic, String>{};
    final constDefinitions = <String>[];
    for (final inputSynthLogic in inputMapping.keys) {
      if (inputSynthLogic.isConst) {
        if (inputSynthLogic.logic.width == 0) {
          // shouldn't be using zero-width constants anywhere, omit them
          constMap[inputSynthLogic] = 'INVALID_ZERO_WIDTH_CONST';
          // TODO(mkorbel1): why not exception?
        } else {
          final constName = synthesizer.nextTempName(module.parent!);
          constDefinitions.add(inputSynthLogic.constant._toCirctDefinition(
              constName, () => synthesizer.nextTempName(module.parent!)));
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
          Map<String, String> outputs) =>
      CirctSynthesizer.instantiationCirctWithParameters(
          module, instanceType, name, inputs, outputs, synthesizer);
}

extension _CirctConstLogicValue on LogicValue {
  String _toCirctDefinition(
    String toAssign,
    String Function() nextTempName,
  ) {
    //cases: int, bigint, all x, all z, mixed invalid
    if (isValid) {
      return '%$toAssign = hw.constant ${toBigInt()} : i$width\n';
    } else {
      if (this == LogicValue.filled(width, LogicValue.x)) {
        return '%$toAssign = sv.constantX : i$width\n';
      } else if (this == LogicValue.filled(width, LogicValue.z)) {
        return '%$toAssign = sv.constantZ : i$width\n';
      } else {
        // Need to swizzle together the proper info
        final tmpBitNames = List.generate(width, (i) => nextTempName());
        final lineBuffer = StringBuffer();
        for (var i = 0; i < width; i++) {
          lineBuffer.write('%${tmpBitNames[i]} = ');
          if (this[i].isValid) {
            lineBuffer.writeln('hw.constant ${this[i].toInt()} : i1');
          } else if (this[i] == LogicValue.x) {
            lineBuffer.writeln('sv.constantX : i1');
          } else if (this[i] == LogicValue.z) {
            lineBuffer.writeln('sv.constantZ : i1');
          }
        }

        final bitsString = tmpBitNames.reversed.map((e) => '%$e').join(', ');
        final widthsString = List.generate(width, (i) => 'i1').join(', ');
        lineBuffer
            .writeln('%$toAssign = comb.concat $bitsString : $widthsString');

        return lineBuffer.toString();
      }
    }
  }
}
