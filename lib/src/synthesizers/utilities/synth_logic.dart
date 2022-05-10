import 'package:rohd/rohd.dart';

/// Represents a logic signal in the generated code within a module.
class SynthLogic {
  final Logic logic;
  final String _name;
  final bool _renameable;
  bool get renameable => _mergedNameSynthLogic?.renameable ?? _renameable;
  bool _needsDeclaration = true;
  SynthLogic? _mergedNameSynthLogic;
  LogicValue? _mergedConst;
  bool get needsDeclaration => _needsDeclaration;
  bool get isConst => _mergedNameSynthLogic?.isConst ?? _mergedConst != null;

  /// Returns the width of the underlying [Logic] or constant.
  int get width => isConst ? constant.width : logic.width;

  String get name {
    if (isConst) {
      throw Exception('SynthLogic is a const, has no name!');
    }
    return _mergedNameSynthLogic?.name ?? _name;
  }

  LogicValue get constant {
    if (!isConst) {
      throw Exception('SynthLogic is not a constant, use name instead!');
    }
    return _mergedNameSynthLogic?.constant ?? _mergedConst!;
  }

  SynthLogic(this.logic, this._name, {bool renameable = true})
      : _renameable = renameable,
        _mergedConst = logic is Const ? logic.value : null;

  SynthLogic.ofConstant(LogicValue constant)
      : logic = Const(constant, width: constant.width),
        _name = 'constant#$constant',
        _renameable = false,
        _mergedConst = constant;

  @override
  String toString() {
    return "'${isConst ? constant : name}', logic name: '${logic.name}'";
  }

  void clearDeclaration() {
    _needsDeclaration = false;
    _mergedNameSynthLogic?.clearDeclaration();
  }

  void mergeName(SynthLogic other) {
    // print("Renaming $name to ${other.name}");
    if (!renameable) {
      throw Exception('This _SynthLogic ($this) cannot be renamed to $other.');
    }
    _mergedConst = null;
    _mergedNameSynthLogic
        ?.mergeName(this); // in case we're changing direction of merge
    _mergedNameSynthLogic = other;
    _needsDeclaration = false;
  }

  void mergeConst(LogicValue constant) {
    // print("Renaming $name to const ${constant}");
    if (!renameable) {
      throw Exception(
          'This _SynthLogic ($this) cannot be renamed to $constant.');
    }
    _mergedNameSynthLogic = null;
    _mergedConst = constant;
    _needsDeclaration = false;
  }
}
