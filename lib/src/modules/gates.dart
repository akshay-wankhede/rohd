/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// gates.dart
/// Definition for basic gates
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:math';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/exceptions.dart';

/// A [Module] which has only combinational logic within it and defines
/// custom functionality.
///
/// This type of [Module] implies that any input port may combinationally
/// affect any output.
mixin FullyCombinational on Module {
  @override
  Map<Logic, List<Logic>> getCombinationalPaths() {
    // combinational gates are all combinational paths
    final allOutputs = outputs.values.toList();
    return Map.fromEntries(
        inputs.values.map((inputPort) => MapEntry(inputPort, allOutputs)));
  }
}

/// A gate [Module] that performs bit-wise inversion.
class NotGate extends Module
    with InlineSystemVerilog, FullyCombinational, CustomCirct {
  /// Name for the input of this inverter.
  late final String _inName;

  /// Name for the output of this inverter.
  late final String _outName;

  /// The input to this [NotGate].
  Logic get _in => input(_inName);

  /// The output of this [NotGate].
  Logic get out => output(_outName);

  /// Constructs a [NotGate] with [in_] as its input.
  ///
  /// You can optionally set [name] to name this [Module].
  NotGate(Logic in_, {super.name = 'not'}) {
    _inName = Module.unpreferredName(in_.name);
    _outName = Module.unpreferredName('${in_.name}_b');
    addInput(_inName, in_, width: in_.width);
    addOutput(_outName, width: in_.width);
    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _in.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    out.put(~_in.value);
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 1) {
      throw Exception('Gate has exactly one input.');
    }
    final a = inputs[_inName]!;
    return '~$a';
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == 1, 'Expected 1 input');
    assert(outputs.length == 1, 'Expected 1 output');
    final inName = inputs[_inName]!;
    final outName = outputs[_outName]!;
    final neg1 = synthesizer.nextTempName(parent!);
    return [
      '// $instanceName',
      '%$neg1 = hw.constant -1 : i${_in.width}',
      '%$outName = comb.xor %$inName, %$neg1 : i${out.width}'
    ].join('\n');
  }
}

/// A generic unary gate [Module].
///
/// It always takes one input, and the output width is always 1.
abstract class _OneInputUnaryGate extends Module
    with InlineSystemVerilog, FullyCombinational, CustomCirct {
  /// Name for the input port of this module.
  late final String _inName;

  /// Name for the output port of this module.
  late final String _outName;

  /// The input to this gate.
  Logic get _in => input(_inName);

  /// The output of this gate (width is always 1).
  Logic get out => output(_outName);

  /// The output of this gate (width is always 1).
  ///
  /// Deprecated: use [out] instead.
  @Deprecated('Use `out` instead.')
  Logic get y => out;

  final LogicValue Function(LogicValue a) _op;
  final String _svOpStr;

  /// Constructs a unary gate for an abitrary custom functional implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When
  /// this [Module] is in-lined as SystemVerilog, it will use [_svOpStr] as the
  /// prefix to the input signal name (e.g. if [_svOpStr] was "&", generated
  /// SystemVerilog may look like "&a").
  _OneInputUnaryGate(this._op, this._svOpStr, Logic in_,
      {String name = 'ugate'})
      : super(name: name) {
    _inName = Module.unpreferredName(in_.name);
    _outName = Module.unpreferredName('${name}_${in_.name}');
    addInput(_inName, in_, width: in_.width);
    addOutput(_outName);
    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _in.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    out.put(_op(_in.value));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 1) {
      throw Exception('Gate has exactly one input.');
    }
    final in_ = inputs[_inName]!;
    return '$_svOpStr$in_';
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == 1, 'Expected 1 input');
    assert(outputs.length == 1, 'Expected 1 output');
    final aName = inputs[_inName]!;
    final yName = outputs[_outName]!;
    return [
      '// $instanceName',
      _generateCirct(aName, yName, synthesizer),
    ].join('\n');
  }

  String _generateCirct(
      String aName, String yName, CirctSynthesizer synthesizer);
}

/// A generic two-input bitwise gate [Module].
///
/// It always takes two inputs and has one output.  All ports have the
/// same width.
abstract class _TwoInputBitwiseGate extends Module
    with InlineSystemVerilog, FullyCombinational, CustomCirct {
  /// Name for a first input port of this module.
  late final String _in0Name;

  /// Name for a second input port of this module.
  late final String _in1Name;

  /// Name for the output port of this module.
  late final String _outName;

  /// An input to this gate.
  Logic get _in0 => input(_in0Name);

  /// An input to this gate.
  Logic get _in1 => input(_in1Name);

  /// The output of this gate.
  Logic get out => output(_outName);

  /// The output of this gate.
  ///
  /// Deprecated: use [out] instead.
  @Deprecated('Use `out` instead.')
  Logic get y => out;

  /// The functional operation to perform for this gate.
  final LogicValue Function(LogicValue in0, LogicValue in1) _op;

  // TODO(mkorbel1): rewrite and doc

  /// The `String` representing the operation to perform in generated code.
  final String _svOpStr;

  final String _circtOpStr;

  /// Constructs a two-input bitwise gate for an abitrary custom functional
  /// implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When
  /// this [Module] is in-lined as SystemVerilog, it will use [_opStr] as a
  /// String between the two input signal names (e.g. if [_opStr] was "&",
  /// generated SystemVerilog may look like "a & b").
  _TwoInputBitwiseGate(
      this._op, this._svOpStr, this._circtOpStr, Logic in0, dynamic in1,
      {String name = 'gate2'})
      : super(name: name) {
    if (in1 is Logic && in0.width != in1.width) {
      throw Exception('Input widths must match,'
          ' but found $in0 and $in1 with different widths.');
    }

    final in1Logic = in1 is Logic ? in1 : Const(in1, width: in0.width);

    _in0Name = Module.unpreferredName('in0_${in0.name}');
    _in1Name = Module.unpreferredName('in1_${in1Logic.name}');
    _outName = Module.unpreferredName('${in0.name}_${name}_${in1Logic.name}');

    addInput(_in0Name, in0, width: in0.width);
    addInput(_in1Name, in1Logic, width: in1Logic.width);
    addOutput(_outName, width: in0.width);

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _in0.glitch.listen((args) {
      _execute();
    });
    _in1.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    dynamic toPut;
    try {
      toPut = _op(_in0.value, _in1.value);
    } on Exception {
      // in case of things like divide by 0
      toPut = LogicValue.x;
    }
    out.put(toPut);
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) {
      throw Exception('Gate has exactly two inputs.');
    }
    final in0 = inputs[_in0Name]!;
    final in1 = inputs[_in1Name]!;
    return '$in0 $_svOpStr $in1';
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == 2, 'Expected 2 inputs');
    assert(outputs.length == 1, 'Expected 1 output');
    final in0 = inputs[_in0Name]!;
    final in1 = inputs[_in1Name]!;
    final outName = outputs[_outName]!;
    return [
      '// $instanceName',
      '%$outName = comb.$_circtOpStr %$in0, %$in1 : i${out.width}'
    ].join('\n');
  }
}

/// A generic two-input comparison gate [Module].
///
/// It always takes two inputs of the same width and has one 1-bit output.
abstract class _TwoInputComparisonGate extends Module
    with InlineSystemVerilog, FullyCombinational, CustomCirct {
  /// Name for a first input port of this module.
  late final String _in0Name;

  /// Name for a second input port of this module.
  late final String _in1Name;

  /// Name for the output port of this module.
  late final String _outName;

  /// An input to this gate.
  Logic get _in0 => input(_in0Name);

  /// An input to this gate.
  Logic get _in1 => input(_in1Name);

  /// The output of this gate.
  Logic get out => output(_outName);

  /// The output of this gate.
  ///
  /// Deprecated: use [out] instead.
  @Deprecated('Use `out` instead.')
  Logic get y => out;

  /// The functional operation to perform for this gate.
  final LogicValue Function(LogicValue in0, LogicValue in1) _op;

  // TODO(mkorbel1): fix doc strings

  /// The `String` representing the operation to perform in generated code.
  final String _svOpStr;
  final String _circtOpStr;

  /// Constructs a two-input comparison gate for an abitrary custom functional
  /// implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When
  /// this [Module] is in-lined as SystemVerilog, it will use [_opStr] as a
  /// String between the two input signal names (e.g. if [_opStr] was ">",
  /// generated SystemVerilog may look like "a > b").
  _TwoInputComparisonGate(
      this._op, this._svOpStr, this._circtOpStr, Logic in0, dynamic in1,
      {String name = 'cmp2'})
      : super(name: name) {
    if (in1 is Logic && in0.width != in1.width) {
      throw Exception('Input widths must match,'
          ' but found $in0 and $in1 with different widths.');
    }

    final in1Logic = in1 is Logic ? in1 : Const(in1, width: in0.width);

    _in0Name = Module.unpreferredName('in0_${in0.name}');
    _in1Name = Module.unpreferredName('in1_${in1Logic.name}');
    _outName = Module.unpreferredName('${in0.name}_${name}_${in1Logic.name}');

    addInput(_in0Name, in0, width: in0.width);
    addInput(_in1Name, in1Logic, width: in1Logic.width);
    addOutput(_outName);

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _in0.glitch.listen((args) {
      _execute();
    });
    _in1.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    out.put(_op(_in0.value, _in1.value));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) {
      throw Exception('Gate has exactly two inputs.');
    }
    final in0 = inputs[_in0Name]!;
    final in1 = inputs[_in1Name]!;
    return '$in0 $_svOpStr $in1';
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == 2, 'Expected 2 inputs');
    assert(outputs.length == 1, 'Expected 1 output');
    final in0 = inputs[_in0Name]!;
    final in1 = inputs[_in1Name]!;
    final outName = outputs[_outName]!;
    return [
      '// $instanceName',
      '%$outName = comb.icmp $_circtOpStr %$in0, %$in1 : i${_in0.width}'
    ].join('\n');
  }
}

/// A generic two-input shift gate [Module].
///
/// It always takes two inputs and has one output of equal width to the primary
/// of the input.
class _ShiftGate extends Module
    with InlineSystemVerilog, FullyCombinational, CustomCirct {
  /// Name for the main input port of this module.
  late final String _inName;

  /// Name for the shift amount input port of this module.
  late final String _shiftAmountName;

  /// Name for the output port of this module.
  late final String _outName;

  /// The primary input to this gate.
  Logic get _in => input(_inName);

  /// The shift amount for this gate.
  Logic get _shiftAmount => input(_shiftAmountName);

  /// The output of this gate.
  Logic get out => output(_outName);

  /// The functional operation to perform for this gate.
  final LogicValue Function(LogicValue in_, LogicValue shiftAmount) _op;

  /// The `String` representing the operation to perform in generated code.
  final String _svOpStr;
  final String _circtOpStr;

  /// Whether or not this gate operates on a signed number.
  final bool signed;

  /// Constructs a two-input shift gate for an abitrary custom functional
  /// implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When
  /// this [Module] is in-lined as SystemVerilog, it will use [_opStr] as a
  /// String between the two input signal names (e.g. if [_opStr] was ">>",
  /// generated SystemVerilog may look like "a >> b").
  _ShiftGate(
      this._op, this._svOpStr, this._circtOpStr, Logic in_, dynamic shiftAmount,
      {String name = 'gate2', this.signed = false})
      : super(name: name) {
    final shiftAmountLogic = shiftAmount is Logic
        ? shiftAmount
        : Const(shiftAmount, width: in_.width);

    _inName = Module.unpreferredName('in_${in_.name}');
    _shiftAmountName =
        Module.unpreferredName('shiftAmount_${shiftAmountLogic.name}');
    _outName =
        Module.unpreferredName('${in_.name}_${name}_${shiftAmountLogic.name}');

    addInput(_inName, in_, width: in_.width);
    addInput(_shiftAmountName, shiftAmountLogic, width: shiftAmountLogic.width);
    addOutput(_outName, width: in_.width);

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _in.glitch.listen((args) {
      _execute();
    });
    _shiftAmount.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    out.put(_op(_in.value, _shiftAmount.value));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) {
      throw Exception('Gate has exactly two inputs.');
    }
    final in_ = inputs[_inName]!;
    final shiftAmount = inputs[_shiftAmountName]!;
    final aStr = signed ? '\$signed($in_)' : in_;
    return '$aStr $_svOpStr $shiftAmount';
  }

  List<String> _paddingCirct(String newName, String originalName, Logic signal,
      int targetWidth, CirctSynthesizer synthesizer) {
    assert(signal.width <= targetWidth,
        'Cannot pad a signal if it is bigger than the desired width.');

    final lines = <String>[];
    final paddingVar = synthesizer.nextTempName(parent!);
    final paddingWidth = targetWidth - signal.width;

    if (signed) {
      final signVar = synthesizer.nextTempName(parent!);
      lines
        ..add('%$signVar = comb.extract %$originalName from ${signal.width - 1}'
            ' : (i${signal.width}) -> i1')
        ..add('%$paddingVar = comb.replicate %$signVar'
            ' : (i1) -> i$paddingWidth');
    } else {
      lines.add('%$paddingVar = hw.constant 0 : i$paddingWidth');
    }

    lines.add('%$newName = comb.concat %$paddingVar, %$originalName :'
        ' i$paddingWidth, i${signal.width}');
    return lines;
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == 2, 'Expected 2 inputs');
    assert(outputs.length == 1, 'Expected 1 output');

    final in_ = inputs[_inName]!;
    final shiftAmount = inputs[_shiftAmountName]!;
    final inputWidth = max(_in.width, _shiftAmount.width);
    final inputLines = <String>[];
    var inWName = in_;
    var shiftWName = shiftAmount;
    if (_in.width < inputWidth) {
      inWName = synthesizer.nextTempName(parent!);
      inputLines
          .addAll(_paddingCirct(inWName, in_, _in, inputWidth, synthesizer));
    }
    if (_shiftAmount.width < inputWidth) {
      shiftWName = synthesizer.nextTempName(parent!);
      inputLines.addAll(_paddingCirct(
          shiftWName, shiftAmount, _shiftAmount, inputWidth, synthesizer));
    }

    final yName = outputs[_outName]!;
    var outWName = yName;
    final outputLines = <String>[];
    if (out.width < inputWidth) {
      outWName = synthesizer.nextTempName(parent!);
      outputLines.add('%$yName = comb.extract %$outWName from 0 :'
          ' (i$inputWidth) -> i${out.width}');
    }

    return [
      '// $instanceName',
      ...inputLines,
      '%$outWName = comb.$_circtOpStr %$inWName, %$shiftWName : i$inputWidth',
      ...outputLines,
    ].join('\n');
  }
}

/// A two-input AND gate.
class And2Gate extends _TwoInputBitwiseGate {
  /// Calculates the AND of [in0] and [in1].
  And2Gate(Logic in0, Logic in1, {String name = 'and'})
      : super((a, b) => a & b, '&', 'and', in0, in1, name: name);
}

/// A two-input OR gate.
class Or2Gate extends _TwoInputBitwiseGate {
  /// Calculates the OR of [in0] and [in1].
  Or2Gate(Logic in0, Logic in1, {String name = 'or'})
      : super((a, b) => a | b, '|', 'or', in0, in1, name: name);
}

/// A two-input XOR gate.
class Xor2Gate extends _TwoInputBitwiseGate {
  /// Calculates the XOR of [in0] and [in1].
  Xor2Gate(Logic in0, Logic in1, {String name = 'xor'})
      : super((a, b) => a ^ b, '^', 'xor', in0, in1, name: name);
}

/// A two-input addition module.
class Add extends _TwoInputBitwiseGate {
  /// Calculates the sum of [in0] and [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  Add(Logic in0, dynamic in1, {String name = 'add'})
      : super((a, b) => a + b, '+', 'add', in0, in1, name: name);
}

/// A two-input subtraction module.
class Subtract extends _TwoInputBitwiseGate {
  /// Calculates the difference between [in0] and [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  Subtract(Logic in0, dynamic in1, {String name = 'subtract'})
      : super((a, b) => a - b, '-', 'sub', in0, in1, name: name);
}

/// A two-input multiplication module.
class Multiply extends _TwoInputBitwiseGate {
  /// Calculates the product of [in0] and [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  Multiply(Logic in0, dynamic in1, {String name = 'multiply'})
      : super((a, b) => a * b, '*', 'mul', in0, in1, name: name);
}

/// A two-input divison module.
class Divide extends _TwoInputBitwiseGate {
  /// Calculates [in0] divided by [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  Divide(Logic in0, dynamic in1, {String name = 'divide'})
      : super((a, b) => a / b, '/', 'divu', in0, in1, name: name);
}

/// A two-input modulo module.
class Modulo extends _TwoInputBitwiseGate {
  /// Calculates the module of [in0] % [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  Modulo(Logic in0, dynamic in1, {String name = 'modulo'})
      : super((a, b) => a % b, '%', 'modu', in0, in1, name: name);
}

/// A two-input equality comparison module.
class Equals extends _TwoInputComparisonGate {
  /// Calculates whether [in0] and [in1] are equal.
  ///
  /// [in1] can be either a [Logic] or [int].
  Equals(Logic in0, dynamic in1, {String name = 'equals'})
      : super((a, b) => a.eq(b), '==', 'eq', in0, in1, name: name);
}

/// A two-input comparison module for less-than.
class LessThan extends _TwoInputComparisonGate {
  /// Calculates whether [in0] is less than [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  LessThan(Logic in0, dynamic in1, {String name = 'lessthan'})
      : super((a, b) => a < b, '<', 'ult', in0, in1, name: name);
}

/// A two-input comparison module for greater-than.
class GreaterThan extends _TwoInputComparisonGate {
  /// Calculates whether [in0] is greater than [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  GreaterThan(Logic in0, dynamic in1, {String name = 'greaterThan'})
      : super((a, b) => a > b, '>', 'ugt', in0, in1, name: name);
}

/// A two-input comparison module for less-than-or-equal-to.
class LessThanOrEqual extends _TwoInputComparisonGate {
  /// Calculates whether [in0] is less than or equal to [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  LessThanOrEqual(Logic in0, dynamic in1, {String name = 'lessThanOrEqual'})
      : super((a, b) => a <= b, '<=', 'ule', in0, in1, name: name);
}

/// A two-input comparison module for greater-than-or-equal-to.
class GreaterThanOrEqual extends _TwoInputComparisonGate {
  /// Calculates whether [in0] is greater than or equal to [in1].
  ///
  /// [in1] can be either a [Logic] or [int].
  GreaterThanOrEqual(Logic in0, dynamic in1,
      {String name = 'greaterThanOrEqual'})
      : super((a, b) => a >= b, '>=', 'uge', in0, in1, name: name);
}

/// A unary AND gate.
class AndUnary extends _OneInputUnaryGate {
  /// Calculates whether all bits of [in_] are high.
  AndUnary(Logic in_, {String name = 'uand'})
      : super((a) => a.and(), '&', in_, name: name);

  @override
  String _generateCirct(
      String aName, String yName, CirctSynthesizer synthesizer) {
    final neg1 = synthesizer.nextTempName(parent!);
    return [
      '%$neg1 = hw.constant -1 : i${_in.width}',
      '%$yName = comb.icmp eq %$aName, %$neg1 : i${_in.width}'
    ].join('\n');
  }
}

/// A unary OR gate.
class OrUnary extends _OneInputUnaryGate {
  /// Calculates whether any bits of [in_] are high.
  OrUnary(Logic in_, {String name = 'uor'})
      : super((a) => a.or(), '|', in_, name: name);

  @override
  String _generateCirct(
      String aName, String yName, CirctSynthesizer synthesizer) {
    final zero = synthesizer.nextTempName(parent!);
    return [
      '%$zero = hw.constant 0 : i${_in.width}',
      '%$yName = comb.icmp ne %$aName, %$zero : i${_in.width}'
    ].join('\n');
  }
}

/// A unary XOR gate.
class XorUnary extends _OneInputUnaryGate {
  /// Calculates the parity of the bits of [in_].
  XorUnary(Logic in_, {String name = 'uxor'})
      : super((a) => a.xor(), '^', in_, name: name);

  @override
  String _generateCirct(
          String aName, String yName, CirctSynthesizer synthesizer) =>
      '%$yName = comb.parity %$aName : i${_in.width}';
}

/// A logical right-shift module.
class RShift extends _ShiftGate {
  /// Calculates the value of [in_] shifted right (logically) by [shiftAmount].
  RShift(Logic in_, dynamic shiftAmount, {String name = 'rshift'})
      : // Note: >>> vs >> is backwards for SystemVerilog and Dart
        super((a, shamt) => a >>> shamt, '>>', 'shru', in_, shiftAmount,
            name: name);
}

/// An arithmetic right-shift module.
class ARShift extends _ShiftGate {
  /// Calculates the value of [in_] shifted right (arithmetically) by
  /// [shiftAmount].
  ARShift(Logic in_, dynamic shiftAmount, {String name = 'arshift'})
      : // Note: >>> vs >> is backwards for SystemVerilog and Dart
        super((a, shamt) => a >> shamt, '>>>', 'shrs', in_, shiftAmount,
            name: name, signed: true);
}

/// A logical left-shift module.
class LShift extends _ShiftGate {
  /// Calculates the value of [in_] shifted left by [shiftAmount].
  LShift(Logic in_, dynamic shiftAmount, {String name = 'lshift'})
      : super((a, shamt) => a << shamt, '<<', 'shl', in_, shiftAmount,
            name: name);
}

/// Performs a multiplexer/ternary operation.
///
/// This is equivalent to something like:
/// ```
/// control ? d1 : d0
/// ```
Logic mux(Logic control, Logic d1, Logic d0) => Mux(control, d1, d0).out;

/// A mux (multiplexer) module.
///
/// If [_control] has value `1`, then [out] gets [_d1].
/// If [_control] has value `0`, then [out] gets [_d0].
class Mux extends Module
    with InlineSystemVerilog, FullyCombinational, CustomCirct {
  /// Name for the control signal of this mux.
  late final String _controlName;

  /// Name for the input selected when control is 0.
  late final String _d0Name;

  /// Name for the input selected when control is 1.
  late final String _d1Name;

  /// Name for the output port of this mux.
  late final String _outName;

  /// The control signal for this [Mux].
  Logic get _control => input(_controlName);

  /// [Mux] input propogated when [out] is `0`.
  Logic get _d0 => input(_d0Name);

  /// [Mux] input propogated when [out] is `1`.
  Logic get _d1 => input(_d1Name);

  /// Output port of the [Mux].
  Logic get out => output(_outName);

  /// Output port of the [Mux].
  ///
  /// Use [out] or  [mux] instead.
  @Deprecated('Use `out` or `mux` instead.')
  Logic get y => out;

  /// Constructs a multiplexer which passes [d0] or [d1] to [out] depending
  /// on if [control] is 0 or 1, respectively.
  Mux(Logic control, Logic d1, Logic d0, {super.name = 'mux'}) {
    if (control.width != 1) {
      throw Exception('Control must be single bit Logic, but found $control.');
    }
    if (d0.width != d1.width) {
      throw Exception('d0 ($d0) and d1 ($d1) must be same width');
    }

    _controlName = Module.unpreferredName('control_${control.name}');
    _d0Name = Module.unpreferredName('d0_${d0.name}');
    _d1Name = Module.unpreferredName('d1_${d1.name}');
    _outName = Module.unpreferredName('out');

    addInput(_controlName, control);
    addInput(_d0Name, d0, width: d0.width);
    addInput(_d1Name, d1, width: d1.width);
    addOutput(_outName, width: d0.width);

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values

    _d0.glitch.listen((args) {
      _execute();
    });
    _d1.glitch.listen((args) {
      _execute();
    });
    _control.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of the mux.
  void _execute() {
    if (!_control.value.isValid) {
      out.put(_control.value);
    } else if (_control.value == LogicValue.zero) {
      out.put(_d0.value);
    } else if (_control.value == LogicValue.one) {
      out.put(_d1.value);
    }
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 3) {
      throw Exception('Mux2 has exactly three inputs.');
    }
    final d0 = inputs[_d0Name]!;
    final d1 = inputs[_d1Name]!;
    final control = inputs[_controlName]!;
    return '$control ? $d1 : $d0';
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == 3, 'Expected 3 inputs');
    assert(outputs.length == 1, 'Expected 1 output');

    final controlName = inputs[_controlName]!;
    final d0Name = inputs[_d0Name]!;
    final d1Name = inputs[_d1Name]!;
    final yName = outputs[_outName]!;
    return [
      '// $instanceName',
      '%$yName = comb.mux %$controlName, %$d1Name, %$d0Name : i${out.width}'
    ].join('\n');
  }
}

/// A two-input bit index gate [Module].
///
/// It always takes two inputs and has one output of width 1.
class IndexGate extends Module
    with InlineSystemVerilog, FullyCombinational, CustomCirct {
  // TODO(mkorbel1): doc comments
  late final String _originalName;
  late final String _indexName;
  late final String _selectionName;

  /// The primary input to this gate.
  Logic get _original => input(_originalName);

  /// The bit index for this gate.
  Logic get _index => input(_indexName);

  /// The output of this gate.
  Logic get selection => output(_selectionName);

  /// Constructs a two-input bit index gate for an abitrary custom functional
  /// implementation.
  ///
  /// The signal will be indexed by [index] as an output.
  /// [Module] is in-lined as SystemVerilog, it will use original[index], where
  /// target is index's int value
  /// When, the [original] has width '1', [index] is ignored in the generated
  /// SystemVerilog.
  IndexGate(Logic original, Logic index) : super() {
    _originalName = 'original_${original.name}';
    _indexName = Module.unpreferredName('index_${index.name}');
    _selectionName =
        Module.unpreferredName('${original.name}_indexby_${index.name}');

    addInput(_originalName, original, width: original.width);
    addInput(_indexName, index, width: index.width);
    addOutput(_selectionName);

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _original.glitch.listen((args) {
      _execute();
    });
    _index.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    if (_index.value.isValid && _index.value.toInt() < _original.width) {
      final indexVal = _index.value.toInt();
      final outputValue = _original.value.getRange(indexVal, indexVal + 1);
      selection.put(outputValue);
    } else {
      selection.put(LogicValue.x);
    }
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) {
      throw Exception('Gate has exactly two inputs.');
    }

    final target = inputs[_originalName]!;

    if (_original.width == 1) {
      return target;
    }

    final idx = inputs[_indexName]!;
    return '$target[$idx]';
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == 2, 'Expected 2 inputs');
    assert(outputs.length == 1, 'Expected 1 output');
    final originalName = inputs[_originalName]!;
    final indexName = inputs[_indexName]!;
    final selectionName = outputs[_selectionName]!;

    final shifted = synthesizer.nextTempName(parent!);

    // pad the original with an X so that out of bounds gets X
    final paddedOriginal = synthesizer.nextTempName(parent!);
    final x1bit = synthesizer.nextTempName(parent!);
    final newWidth = _original.width + 1;
    final adjustedIndex = synthesizer.nextTempName(parent!);

    String indexAdjust;
    if (_index.width >= newWidth) {
      // truncate
      indexAdjust = '''
%$adjustedIndex = comb.extract %$indexName from 0 : (i${_index.width}) -> i$newWidth
''';
    } else {
      // pad
      final zeroPad = synthesizer.nextTempName(parent!);
      final padWidth = newWidth - _index.width;
      indexAdjust = '''
%$zeroPad = hw.constant 0 : i$padWidth
%$adjustedIndex = comb.concat %$zeroPad, %$indexName : i$padWidth, i${_index.width}
''';
    }

    // shift right then grab bit 0
    return '''
// $instanceName
$indexAdjust
%$x1bit = sv.constantX : i1
%$paddedOriginal = comb.concat %$x1bit, %$originalName : i1, i${_original.width}
%$shifted = comb.shrs %$paddedOriginal, %$adjustedIndex : i$newWidth
%$selectionName = comb.extract %$shifted from 0 : (i$newWidth) -> i1
''';
  }
}

/// A Replication Operator [Module].
///
/// It takes two inputs (bit and width) and outputs a [Logic] representing
/// the input bit repeated over the input width
class ReplicationOp extends Module
    with InlineSystemVerilog, FullyCombinational, CustomCirct {
  // input component name
  final String _inputName;
  // output component name
  final String _outputName;
  // Width of the output signal
  final int _multiplier;

  /// The primary input to this gate.
  Logic get _input => input(_inputName);

  /// The output of this gate.
  Logic get replicated => output(_outputName);

  /// Constructs a ReplicationOp
  ///
  /// The signal [original] will be repeated over the [_multiplier] times as an
  /// output.
  /// Input [_multiplier] cannot be negative or zero, an exception will be
  /// thrown, otherwise.
  /// [Module] is in-lined as SystemVerilog, it will use {width{bit}}
  ReplicationOp(Logic original, this._multiplier)
      : _inputName = Module.unpreferredName('input_${original.name}'),
        _outputName = Module.unpreferredName('output_${original.name}') {
    final newWidth = original.width * _multiplier;
    if (newWidth < 1) {
      throw InvalidMultiplierException(newWidth);
    }

    addInput(_inputName, original, width: original.width);
    addOutput(_outputName, width: original.width * _multiplier);
    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    _input.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    replicated.put(_input.value.replicate(_multiplier));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 1) {
      throw Exception('Gate has exactly one input.');
    }

    final target = inputs[_inputName]!;
    final width = _multiplier;
    return '{$width{$target}}';
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == 1, 'Expected 1 input');
    assert(outputs.length == 1, 'Expected 1 output');
    final inName = inputs[_inputName]!;
    final outName = outputs[_outputName]!;
    return '''
// $instanceName
%$outName = comb.replicate %$inName : (i${_input.width}) -> i${replicated.width}
''';
  }
}
