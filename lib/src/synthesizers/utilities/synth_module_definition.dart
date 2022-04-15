import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';
import 'package:rohd/src/utilities/traverseable_collection.dart';
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
      var instantiationName = _getUniqueSynthSubModuleInstantiationName(
          m.uniqueInstanceName, m.reserveName);
      newSSMI = ssmiBuilder(m, instantiationName);
      moduleToSubModuleInstantiationMap[m] = newSSMI;
      return newSSMI;
    }
  }

  @override
  String toString() {
    return "module name: '${module.name}'";
  }

  late final Uniquifier SynthLogicNameUniquifier;
  String _getUniqueSynthLogicName(String? initialName, bool portName) {
    if (portName && initialName == null) {
      throw Exception('Port name cannot be null.');
    }
    return SynthLogicNameUniquifier.getUniqueName(
        initialName: initialName, reserved: portName);
  }

  final Uniquifier SynthSubModuleInstantiationNameUniquifier = Uniquifier();
  String _getUniqueSynthSubModuleInstantiationName(
      String? initialName, bool reserved) {
    return SynthSubModuleInstantiationNameUniquifier.getUniqueName(
        initialName: initialName, nullStarter: 'm', reserved: reserved);
  }

  SynthLogic? _getSynthLogic(Logic? logic, bool allowPortName) {
    if (logic == null) {
      return null;
    } else if (logicToSynthMap.containsKey(logic)) {
      return logicToSynthMap[logic]!;
    } else {
      var newSynth = SynthLogic(
          logic, _getUniqueSynthLogicName(logic.name, allowPortName),
          renameable: !allowPortName);
      logicToSynthMap[logic] = newSynth;
      return newSynth;
    }
  }

  SynthModuleDefinition(this.module, {required this.ssmiBuilder}) {
    SynthLogicNameUniquifier = Uniquifier(
        reservedNames: {...module.inputs.keys, ...module.outputs.keys});

    // start by traversing output signals
    var logicsToTraverse = TraverseableCollection<Logic>()
      ..addAll(module.outputs.values);
    for (var output in module.outputs.values) {
      outputs.add(_getSynthLogic(output, true)!);
    }

    // make sure disconnected inputs are included
    for (var input in module.inputs.values) {
      inputs.add(_getSynthLogic(input, true)!);
    }

    // make sure floating modules are included
    for (var subModule in module.subModules) {
      getSynthSubModuleInstantiation(subModule);
      logicsToTraverse.addAll(subModule.inputs.values);
      logicsToTraverse.addAll(subModule.outputs.values);
    }

    // search for other modules contained within this module

    for (var i = 0; i < logicsToTraverse.length; i++) {
      var receiver = logicsToTraverse[i];
      var driver = receiver.srcConnection;

      var receiverIsModuleInput = module.isInput(receiver);
      var receiverIsModuleOutput = module.isOutput(receiver);
      var driverIsModuleInput = driver == null ? false : module.isInput(driver);
      var driverIsModuleOutput =
          driver == null ? false : module.isOutput(driver);

      var synthReceiver = _getSynthLogic(
          receiver, receiverIsModuleInput || receiverIsModuleOutput)!;
      var synthDriver =
          _getSynthLogic(driver, driverIsModuleInput || driverIsModuleOutput);

      if (receiverIsModuleInput) {
        inputs.add(synthReceiver);
      } else if (receiverIsModuleOutput) {
        outputs.add(synthReceiver);
      } else {
        internalNets.add(synthReceiver);
      }

      var receiverIsSubModuleOutput =
          receiver.isOutput && (receiver.parentModule?.parent == module);
      if (receiverIsSubModuleOutput) {
        var subModule = receiver.parentModule!;
        var subModuleInstantiation = getSynthSubModuleInstantiation(subModule);
        subModuleInstantiation.outputMapping[synthReceiver] = receiver;

        for (var element in subModule.inputs.values) {
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
      } else if (driver == null && receiver.hasValidValue()) {
        assignments.add(SynthAssignment(
            SynthLogic.ofConstant(receiver.value), synthReceiver));
      } else if (driver == null && !receiver.isFloating()) {
        // this is a signal that is *partially* invalid (e.g. 0b1z1x0)
        assignments.add(SynthAssignment(
            SynthLogic.ofConstant(receiver.value), synthReceiver));
      }

      var receiverIsSubModuleInput =
          receiver.isInput && (receiver.parentModule?.parent == module);
      if (receiverIsSubModuleInput) {
        var subModule = receiver.parentModule!;
        var subModuleInstantiation = getSynthSubModuleInstantiation(subModule);
        subModuleInstantiation.inputMapping[synthReceiver] = receiver;
      }
    }

    _collapseAssignments();
  }

  //TODO: collapse in-line assignments where the driver is equal to eliminate duplicates (decrease verbosity)
  //  for example, merge these two:
  //      assign out = {b,a};  // swizzle_0
  //      assign out_0 = {b,a};  // swizzle
  // void _collapseEquivalentInlineModules() {
  //   //WARNING: do not collapse non-renameable outputs directly, create a buffer signal
  //   //  maybe do this before collapsing assignments, always add a buffer, then let assignment collapsing handle it?

  //   // this can be easily done using existing merge capabilities for synthlogic?
  // }

  void _collapseAssignments() {
    // there might be more assign statements than necessary, so let's ditch them
    var prevAssignmentCount = 0;
    while (prevAssignmentCount != assignments.length) {
      // keep looping until it stops shrinking
      var reducedAssignments = <SynthAssignment>[];
      for (var assignment in assignments) {
        var dst = assignment.dst;
        SynthLogic src = assignment.src;
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
