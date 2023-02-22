import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/collections/traverseable_collection.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

/// Represents the definition of a module.
class SynthModuleDefinition {
  final Module module;
  final List<SynthAssignment> assignments = [];
  final Set<SynthLogic> internalNets = {};
  final Set<SynthLogic> inputs = {};
  final Set<SynthLogic> outputs = {};
  final Map<Logic, SynthLogic> logicToSynthMap = {};

  final Map<Module, SynthSubModuleInstantiation>
      moduleToSubModuleInstantiationMap = {};

  SynthSubModuleInstantiation Function(Module m, String instantiationName)
      ssmiBuilder;

  @protected
  SynthSubModuleInstantiation getSynthSubModuleInstantiation(Module m) {
    if (moduleToSubModuleInstantiationMap.containsKey(m)) {
      return moduleToSubModuleInstantiationMap[m]!;
    } else {
      SynthSubModuleInstantiation newSSMI;
      final instantiationName = _getUniqueSynthSubModuleInstantiationName(
          m.uniqueInstanceName, m.reserveName);
      newSSMI = ssmiBuilder(m, instantiationName);
      moduleToSubModuleInstantiationMap[m] = newSSMI;
      return newSSMI;
    }
  }

  @override
  String toString() => "module name: '${module.name}'";

  /// Used to uniquify any identifiers, including signal names
  /// and module instances.
  late final Uniquifier synthInstantiationNameUniquifier;

  String _getUniqueSynthLogicName(String? initialName, bool portName) {
    if (portName && initialName == null) {
      throw Exception('Port name cannot be null.');
    }
    return synthInstantiationNameUniquifier.getUniqueName(
        initialName: initialName, reserved: portName);
  }

  String _getUniqueSynthSubModuleInstantiationName(
          String? initialName, bool reserved) =>
      synthInstantiationNameUniquifier.getUniqueName(
          initialName: initialName, nullStarter: 'm', reserved: reserved);

  SynthLogic? _getSynthLogic(Logic? logic, bool allowPortName) {
    if (logic == null) {
      return null;
    } else if (logicToSynthMap.containsKey(logic)) {
      return logicToSynthMap[logic]!;
    } else {
      final newSynth = SynthLogic(
          logic, _getUniqueSynthLogicName(logic.name, allowPortName),
          renameable: !allowPortName);
      logicToSynthMap[logic] = newSynth;
      return newSynth;
    }
  }

  ///TODO
  SynthModuleDefinition(this.module, {required this.ssmiBuilder}) {
    synthInstantiationNameUniquifier = Uniquifier(
        reservedNames: {...module.inputs.keys, ...module.outputs.keys});

    // start by traversing output signals
    final logicsToTraverse = TraverseableCollection<Logic>()
      ..addAll(module.outputs.values);
    for (final output in module.outputs.values) {
      outputs.add(_getSynthLogic(output, true)!);
    }

    // make sure disconnected inputs are included
    for (final input in module.inputs.values) {
      inputs.add(_getSynthLogic(input, true)!);
    }

    // make sure floating modules are included
    for (final subModule in module.subModules) {
      getSynthSubModuleInstantiation(subModule);
      logicsToTraverse.addAll(subModule.inputs.values);
      logicsToTraverse.addAll(subModule.outputs.values);
    }

    // search for other modules contained within this module

    for (var i = 0; i < logicsToTraverse.length; i++) {
      final receiver = logicsToTraverse[i];
      final driver = receiver.srcConnection;

      final receiverIsModuleInput = module.isInput(receiver);
      final receiverIsModuleOutput = module.isOutput(receiver);
      final driverIsModuleInput =
          driver == null ? false : module.isInput(driver);
      final driverIsModuleOutput =
          driver == null ? false : module.isOutput(driver);

      final synthReceiver = _getSynthLogic(
          receiver, receiverIsModuleInput || receiverIsModuleOutput)!;
      final synthDriver =
          _getSynthLogic(driver, driverIsModuleInput || driverIsModuleOutput);

      if (receiverIsModuleInput) {
        inputs.add(synthReceiver);
      } else if (receiverIsModuleOutput) {
        outputs.add(synthReceiver);
      } else {
        internalNets.add(synthReceiver);
      }

      final receiverIsSubModuleOutput =
          receiver.isOutput && (receiver.parentModule?.parent == module);
      if (receiverIsSubModuleOutput) {
        final subModule = receiver.parentModule!;
        final subModuleInstantiation =
            getSynthSubModuleInstantiation(subModule);
        subModuleInstantiation.outputMapping[synthReceiver] = receiver;

        for (final element in subModule.inputs.values) {
          if (!logicsToTraverse.contains(element)) {
            logicsToTraverse.add(element);
          }
        }
      } else if (driver != null) {
        if (!module.isInput(receiver)) {
          // stop at the input to this module
          if (!logicsToTraverse.contains(driver)) {
            logicsToTraverse.add(driver);
          }
          assignments.add(SynthAssignment(synthDriver!, synthReceiver));
        }
      } else if (driver == null && receiver.value.isValid) {
        assignments.add(SynthAssignment(
            SynthLogic.ofConstant(receiver.value), synthReceiver));
      } else if (driver == null && !receiver.value.isFloating) {
        // this is a signal that is *partially* invalid (e.g. 0b1z1x0)
        assignments.add(SynthAssignment(
            SynthLogic.ofConstant(receiver.value), synthReceiver));
      }

      final receiverIsSubModuleInput =
          receiver.isInput && (receiver.parentModule?.parent == module);
      if (receiverIsSubModuleInput) {
        final subModule = receiver.parentModule!;
        final subModuleInstantiation =
            getSynthSubModuleInstantiation(subModule);
        subModuleInstantiation.inputMapping[synthReceiver] = receiver;
      }
    }

    _collapseAssignments();
  }

  void _collapseAssignments() {
    // there might be more assign statements than necessary, so let's ditch them
    var prevAssignmentCount = 0;
    while (prevAssignmentCount != assignments.length) {
      // keep looping until it stops shrinking
      final reducedAssignments = <SynthAssignment>[];
      for (final assignment in assignments) {
        final dst = assignment.dst;
        final src = assignment.src;
        if (!src.isConst && dst.name == src.name) {
          //TODO: is this ok? just let it continue and delete the assignment?
          throw Exception(
              'Circular assignment detected between $dst and $src.');
        }
        if (!src.isConst) {
          if (dst.renameable && src.renameable) {
            if (Module.isUnpreferred(dst.name)) {
              dst.mergeName(src);
            } else {
              src.mergeName(dst);
            }
          } else if (dst.renameable) {
            dst.mergeName(src);
          } else if (src.renameable) {
            src.mergeName(dst);
          } else {
            reducedAssignments.add(assignment);
          }
        } else if (dst.renameable) {
          // src is a constant, feed that string directly in
          dst.mergeConst(assignment.src.constant);
          assert(dst.isConst, 'Expected a constant, but did not receive one.');
        } else {
          // nothing can be done here, keep it as-is
          reducedAssignments.add(assignment);
        }
      }
      prevAssignmentCount = assignments.length;
      assignments.clear();
      assignments.addAll(reducedAssignments);
    }
  }
}
