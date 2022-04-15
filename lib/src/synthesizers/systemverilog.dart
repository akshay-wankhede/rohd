/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// systemverilog.dart
/// Definition for SystemVerilog Synthesizer
///
/// 2021 August 26
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// A [Synthesizer] which generates equivalent SystemVerilog as the given [Module].
///
/// Attempts to maintain signal naming and structure as much as possible.
class SystemVerilogSynthesizer extends Synthesizer {
  /// Creates a line of SystemVerilog that instantiates [module].
  ///
  /// The instantiation will create it as type [instanceType] and name [instanceName].
  ///
  /// [inputs] and [outputs] map `module` input/output name to a verilog signal name.
  /// For example:
  /// To generate this SystemVerilog:  `sig_c = sig_a & sig_b`
  /// Based on this module definition: `c <= a & b`
  /// The values for [inputs] and [outputs] should be:
  /// inputs:  `{ 'a' : 'sig_a', 'b' : 'sig_b'}` and
  /// outputs: `{ 'c' : 'sig_c' }`
  static String instantiationVerilogWithParameters(
      Module module,
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      {Map<String, String>? parameters,
      bool forceStandardInstantiation = false}) {
    if (!forceStandardInstantiation) {
      if (module is CustomSystemVerilog) {
        return module.instantiationVerilog(
            instanceType, instanceName, inputs, outputs);
      } else if (module is CustomFunctionality) {
        throw Exception('Module $module defines custom functionality but not'
            'an implementation in SystemVerilog!');
      }
    }

    //non-custom needs more details
    var connections = [];
    module.inputs.forEach((signalName, logic) {
      connections.add('.$signalName(${inputs[signalName]})');
    });
    module.outputs.forEach((signalName, logic) {
      connections.add('.$signalName(${outputs[signalName]})');
    });
    var connectionsStr = connections.join(',');
    var parameterString = '';
    if (parameters != null) {
      parameterString = '#(' +
          parameters.entries.map((e) => '.${e.key}(${e.value})').join(',') +
          ')';
    }
    return '$instanceType $parameterString $instanceName($connectionsStr);';
  }

  static String definitionName(int width, String name) {
    if (width > 1) {
      return '[${width - 1}:0] $name';
    } else {
      return name;
    }
  }

  @override
  SynthesisResult synthesize(
      Module module, Map<Module, String> moduleToInstanceTypeMap) {
    return _SystemVerilogSynthesisResult(module, moduleToInstanceTypeMap, this);
  }
}

/// Allows a [Module] to define a custom implementation of SystemVerilog to be
/// injected in generated output instead of instantiating a separate `module`.
mixin CustomSystemVerilog on Module implements CustomFunctionality {
  /// Generates custom SystemVerilog to be injected in place of a `module` instantiation.
  ///
  /// The [instanceType] and [instanceName] represent the type and name, respectively of
  /// the module that would have been instantiated had it not been overridden.  The [Map]s
  /// [inputs] and [outputs] are a mapping from the [Module]'s port names to the names of
  /// the signals that are passed into those ports in the generated SystemVerilog.
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs);
}

/// Allows a [Module] to define a special type of [CustomSystemVerilog] which can
/// be inlined within other SystemVerilog code.
///
/// The inline SystemVerilog will get parentheses wrapped around it and then dropped
/// into other code in the same way a variable name is.
mixin InlineSystemVerilog on Module implements CustomSystemVerilog {
  /// Generates custom SystemVerilog to be injected in place of the output port's corresponding signal name.
  ///
  /// The [inputs] are a mapping from the [Module]'s port names to the names of the signals that are
  /// passed into those ports in the generated SystemVerilog.
  ///
  /// The output will be appropriately wrapped with parentheses to guarantee proper order of operations.
  String inlineVerilog(Map<String, String> inputs);

  @override
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs) {
    if (outputs.length != 1) {
      throw Exception(
          'Inline verilog must have exactly one output, but saw $outputs.');
    }
    var output = outputs.values.first;
    var inline = inlineVerilog(inputs);
    return 'assign $output = $inline;  // $instanceName';
  }
}

/// A [SynthesisResult] representing a conversion of a [Module] to SystemVerilog.
class _SystemVerilogSynthesisResult extends SynthesisResult {
  /// A cached copy of the generated ports
  late final String _portsString;

  /// A cached copy of the generated contents of the module
  late final String _moduleContentsString;

  _SystemVerilogSynthesisResult(
      Module module,
      Map<Module, String> moduleToInstanceTypeMap,
      SystemVerilogSynthesizer synthesizer)
      : super(module, moduleToInstanceTypeMap, synthesizer,
            SystemVeriogSynthModuleDefinition(module)) {
    _portsString = _verilogPorts();
    _moduleContentsString = _verilogModuleContents(moduleToInstanceTypeMap);
  }

  @override
  bool matchesImplementation(SynthesisResult other) =>
      other is _SystemVerilogSynthesisResult &&
      other._portsString == _portsString &&
      other._moduleContentsString == _moduleContentsString;

  @override
  int get matchHashCode =>
      _portsString.hashCode ^ _moduleContentsString.hashCode;

  @override
  String toFileContents() {
    return _toVerilog(moduleToInstanceTypeMap);
  }

  List<String> _verilogInputs() {
    var declarations = synthModuleDefinition.inputs
        .map((sig) =>
            'input logic ${SystemVerilogSynthesizer.definitionName(sig.logic.width, sig.name)}')
        .toList();
    return declarations;
  }

  List<String> _verilogOutputs() {
    var declarations = synthModuleDefinition.outputs
        .map((sig) =>
            'output logic ${SystemVerilogSynthesizer.definitionName(sig.logic.width, sig.name)}')
        .toList();
    return declarations;
  }

  String _verilogInternalNets() {
    var declarations = [];
    for (var sig in synthModuleDefinition.internalNets) {
      if (sig.needsDeclaration) {
        declarations.add(
            'logic ${SystemVerilogSynthesizer.definitionName(sig.logic.width, sig.name)};');
      }
    }
    return declarations.join('\n');
  }

  static String _srcName(SynthLogic src) {
    if (src.isConst) {
      var constant = src.constant;
      if (constant.isValid) {
        return constant.toInt().toString();
      } else {
        return constant.toString();
      }
    } else {
      return src.name;
    }
  }

  String _verilogAssignments() {
    var assignmentLines = [];
    for (var assignment in synthModuleDefinition.assignments) {
      var srcName = '';

      assignmentLines
          .add('assign ${assignment.dst.name} = ${_srcName(assignment.src)};');
    }
    return assignmentLines.join('\n');
  }

  String _verilogModuleContents(Map<Module, String> moduleToInstanceTypeMap) {
    return [
      _verilogInternalNets(),
      _verilogAssignments(),
      subModuleInstantiations(moduleToInstanceTypeMap),
    ].join('\n');
  }

  String _verilogPorts() {
    return [
      ..._verilogInputs(),
      ..._verilogOutputs(),
    ].join(',\n');
  }

  String _toVerilog(Map<Module, String> moduleToInstanceTypeMap) {
    var verilogModuleName = moduleToInstanceTypeMap[module];
    return [
      'module $verilogModuleName(',
      _portsString,
      ');',
      _moduleContentsString,
      'endmodule : $verilogModuleName'
    ].join('\n');
  }
}

class SystemVeriogSynthModuleDefinition extends SynthModuleDefinition {
  SystemVeriogSynthModuleDefinition(Module module)
      : super(module,
            ssmiBuilder: (Module m, String instantiationName) =>
                SystemVerilogSynthSubModuleInstantiation(
                    m, instantiationName)) {
    _collapseChainableModules();
  }

  void _collapseChainableModules() {
    // collapse multiple lines of in-line assignments into one where they are unnamed one-liners
    //  for example, be capable of creating lines like:
    //      assign x = a & b & c & _d_and_e
    //      assign _d_and_e = d & e
    //      assign y = _d_and_e

    // Also feed collapsed chained modules into other modules
    // Need to consider order of operations in systemverilog or else add () everywhere! (for now add the parentheses)

    // Algorithm:
    //  - find submodule instantiations that are inlineable
    //  - filter to those who only output as input to one other module
    //  - pass an override to the submodule instantiation that the corresponding input should map
    //    to the output of another submodule instantiation
    // do not collapse if signal feeds to multiple inputs of other modules

    var inlineableSubmoduleInstantiations = module.subModules
        .whereType<InlineSystemVerilog>()
        .map((subModule) => getSynthSubModuleInstantiation(subModule)
            as SystemVerilogSynthSubModuleInstantiation);

    var signalNameUsage = <String,
        int>{}; // number of times each signal name is used by any module
    var synthModuleInputNames = inputs.map((inputSynth) => inputSynth.name);
    for (var subModuleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      for (var inputSynthLogic in subModuleInstantiation.inputMapping.keys) {
        if (inputSynthLogic.isConst) {
          continue;
        }

        var inputSynthLogicName = inputSynthLogic.name;
        if (synthModuleInputNames.contains(inputSynthLogicName)) {
          // dont worry about inputs to THIS module
          continue;
        }

        if (!signalNameUsage.containsKey(inputSynthLogicName)) {
          signalNameUsage[inputSynthLogicName] = 1;
        } else {
          signalNameUsage[inputSynthLogicName] =
              signalNameUsage[inputSynthLogicName]! + 1;
        }
      }
    }

    var singleUseNames = <String>{};
    signalNameUsage.forEach((signalName, signalUsageCount) {
      if (signalUsageCount == 1) {
        singleUseNames.add(signalName);
      }
    });

    // don't collapse inline modules for preferred names
    singleUseNames =
        singleUseNames.where((name) => Module.isUnpreferred(name)).toSet();

    var singleUsageInlineableSubmoduleInstantiations =
        inlineableSubmoduleInstantiations.where((submoduleInstantiation) =>
            singleUseNames.contains(
                submoduleInstantiation.outputMapping.keys.first.name));

    var synthLogicNameToInlineableSynthSubmoduleMap =
        <String, SystemVerilogSynthSubModuleInstantiation>{};
    for (var submoduleInstantiation
        in singleUsageInlineableSubmoduleInstantiations) {
      var outputSynthLogic = submoduleInstantiation.outputMapping.keys.first;
      outputSynthLogic.clearDeclaration();
      submoduleInstantiation.clearDeclaration();
      synthLogicNameToInlineableSynthSubmoduleMap[outputSynthLogic.name] =
          submoduleInstantiation;
    }

    for (var subModuleInstantiation
        in moduleToSubModuleInstantiationMap.values) {
      subModuleInstantiation as SystemVerilogSynthSubModuleInstantiation;
      subModuleInstantiation.synthLogicNameToInlineableSynthSubmoduleMap =
          synthLogicNameToInlineableSynthSubmoduleMap;
    }
  }
}

class SystemVerilogSynthSubModuleInstantiation
    extends SynthSubModuleInstantiation {
  Map<String, SystemVerilogSynthSubModuleInstantiation>?
      synthLogicNameToInlineableSynthSubmoduleMap;

  SystemVerilogSynthSubModuleInstantiation(Module module, String name)
      : super(module, name);

  Map<String, String> _moduleInputsMap() {
    return inputMapping.map((synthLogic, logic) => MapEntry(
        logic.name, // port name guaranteed to match
        synthLogicNameToInlineableSynthSubmoduleMap?[
                    _SystemVerilogSynthesisResult._srcName(synthLogic)]
                ?.inlineVerilog() ??
            _SystemVerilogSynthesisResult._srcName(synthLogic)));
    //TODO: this logic is less efficient than it could be, multiple _srcName calls...
  }

  String inlineVerilog() {
    return '(' +
        (module as InlineSystemVerilog).inlineVerilog(_moduleInputsMap()) +
        ')';
  }

  @override
  String? instantiationCode(String instanceType) {
    if (!needsDeclaration) return null;
    return SystemVerilogSynthesizer.instantiationVerilogWithParameters(
      module,
      instanceType,
      name,
      _moduleInputsMap(),
      outputMapping.map((synthLogic, logic) => MapEntry(
          logic.name, // port name guaranteed to match
          synthLogic.name)),
    );
  }
}
