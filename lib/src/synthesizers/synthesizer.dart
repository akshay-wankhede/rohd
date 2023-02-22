import 'package:rohd/rohd.dart';

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
    final svDelegate = delegate as CustomSystemVerilog;
    return svDelegate.instantiationVerilog(
        instanceType, instanceName, inputs, outputs);
  }
}

/// An object capable of converting a module into some new output format
abstract class Synthesizer {
  /// Determines whether [module] needs a separate definition or can just be
  /// described in-line.
  bool generatesDefinition(Module module) => module is! CustomFunctionality;

  /// Synthesizes [module] into a [SynthesisResult], given the mapping in
  /// [moduleToInstanceTypeMap].
  SynthesisResult synthesize(
      Module module, Map<Module, String> moduleToInstanceTypeMap);
}
