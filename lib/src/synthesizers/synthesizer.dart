/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// synthesizer.dart
/// Generic definition for something that synthesizes output files
///
/// 2021 August 26
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// An object which implements custom simulation functionality.
///
/// Modules that are [CustomFunctionality] must have appropriate synthesis instructions
/// for supported synthesizers.
mixin CustomFunctionality on Module {}

abstract class DelegatingCustomFunctionalityModule extends Module
    with CustomFunctionality, CustomSystemVerilog {
  CustomFunctionality get delegate;

  //TODO: add circt in here
  //TODO: test delegating

  @override
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs) {
    if (delegate is! CustomSystemVerilog) {
      throw Exception(
          'Delegate module $delegate does not support conversion to SystemVerilog.');
    }
    var svDelegate = delegate as CustomSystemVerilog;
    return svDelegate.instantiationVerilog(
        instanceType, instanceName, inputs, outputs);
  }
}

/// An object capable of converting a module into some new output format
abstract class Synthesizer {
  /// Determines whether [module] needs a separate definition or can just be described in-line.
  bool generatesDefinition(Module module) => module is! CustomFunctionality;

  /// Synthesizes [module] into a [SynthesisResult], given the mapping in
  /// [moduleToInstanceTypeMap].
  SynthesisResult synthesize(
      Module module, Map<Module, String> moduleToInstanceTypeMap);
}

/// An object representing the output of a Synthesizer
abstract class SynthesisResult {
  /// The top level [Module] associated with this result.
  final Module module;

  /// A [Map] from [Module] instances to synthesis instance type names.
  final Map<Module, String> moduleToInstanceTypeMap;

  final Synthesizer synthesizer;

  SynthesisResult(this.module, this.moduleToInstanceTypeMap, this.synthesizer,
      this.synthModuleDefinition);

  /// Whether two implementations are identical or not
  ///
  /// Note: this doesn't include things like the top-level uniquified module
  /// name, just contents
  bool matchesImplementation(SynthesisResult other);

  /// Like the hashCode for [matchesImplementation] as an equality check.
  ///
  /// This is directly used as the [hashCode] of this object.
  int get matchHashCode;

  @override
  bool operator ==(Object other) =>
      other is SynthesisResult && matchesImplementation(other);

  @override
  int get hashCode => matchHashCode;

  /// Generates what could go into a file
  String toFileContents();
  //TODO: this could be a FileContents object of some sort, including file name and contents

  @protected
  final SynthModuleDefinition synthModuleDefinition;

  @protected
  String subModuleInstantiations(Map<Module, String> moduleToInstanceTypeMap) {
    var subModuleLines = <String>[];
    for (var subModuleInstantiation
        in synthModuleDefinition.moduleToSubModuleInstantiationMap.values) {
      if (synthesizer.generatesDefinition(subModuleInstantiation.module) &&
          !moduleToInstanceTypeMap.containsKey(subModuleInstantiation.module)) {
        throw Exception('No defined instance type found.');
      }
      var instanceType =
          moduleToInstanceTypeMap[subModuleInstantiation.module] ??
              '*NO_INSTANCE_TYPE_DEFINED*';
      var instantiationCode =
          subModuleInstantiation.instantiationCode(instanceType);
      if (instantiationCode != null) {
        subModuleLines.add(instantiationCode);
      }
    }
    return subModuleLines.join('\n');
  }
}
