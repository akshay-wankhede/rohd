import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// Represents an instantiation of a module within another module.
abstract class SynthSubModuleInstantiation {
  final Module module;
  final String name;
  final Map<SynthLogic, Logic> inputMapping = {};
  final Map<SynthLogic, Logic> outputMapping = {};
  bool _needsDeclaration = true;
  bool get needsDeclaration => _needsDeclaration;
  SynthSubModuleInstantiation(this.module, this.name);

  @override
  String toString() {
    return "_SynthSubModuleInstantiation '$name', module name:'${module.name}'";
  }

  void clearDeclaration() {
    _needsDeclaration = false;
  }

  String? instantiationCode(String instanceType);
}
