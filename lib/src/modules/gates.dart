/// Copyright (C) 2021 Intel Corporation
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

/// A gate [Module] that performs bit-wise inversion.
class NotGate extends Module with InlineSystemVerilog, CustomCirct {
  /// Name for a port of this module.
  late final String _a, _out;

  /// The input to this [NotGate].
  Logic get a => input(_a);

  /// The output of this [NotGate].
  Logic get out => output(_out);

  /// Constructs a [NotGate] with [a] as its input.
  ///
  /// You can optionally set [name] to name this [Module].
  NotGate(Logic a, {String name = 'not'}) : super(name: name) {
    _a = Module.unpreferredName(a.name);
    _out = Module.unpreferredName('${a.name}_b');
    addInput(_a, a, width: a.width);
    addOutput(_out, width: a.width);
    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    a.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    out.put(~a.value);
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 1) throw Exception('Gate has exactly one input.');
    var a = inputs[_a]!;
    return '~$a';
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == 1);
    assert(outputs.length == 1);
    var aName = inputs[_a]!;
    var outName = outputs[_out]!;
    var neg1 = synthesizer.nextTempName();
    return [
      '// $instanceName',
      '%$neg1 = hw.constant -1 : i${a.width}',
      '%$outName = comb.xor %$aName, %$neg1 : i${out.width}'
    ].join('\n');
  }
}

/// A generic unary gate [Module].
///
/// It always takes one input, and the output width is always 1.
abstract class _OneInputUnaryGate extends Module
    with InlineSystemVerilog, CustomCirct {
  /// Name for a port of this module.
  late final String _a, _y;

  /// The input to this gate.
  Logic get a => input(_a);

  /// The output of this gate (width is always 1).
  Logic get y => output(_y);

  final LogicValue Function(LogicValues a) _op;
  final String _svOpStr;

  /// Constructs a unary gate for an abitrary custom functional implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When this
  /// [Module] is in-lined as SystemVerilog, it will use [_svOpStr] as the prefix to the
  /// input signal name (e.g. if [_svOpStr] was "&", generated SystemVerilog may look like "&a").
  _OneInputUnaryGate(this._op, this._svOpStr, Logic a, {String name = 'ugate'})
      : super(name: name) {
    _a = Module.unpreferredName(a.name);
    _y = Module.unpreferredName(name + '_' + a.name);
    addInput(_a, a, width: a.width);
    addOutput(_y);
    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    a.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    y.put(_op(a.value));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 1) throw Exception('Gate has exactly one input.');
    var a = inputs[_a]!;
    return '$_svOpStr$a';
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == 1);
    assert(outputs.length == 1);
    var aName = inputs[_a]!;
    var yName = outputs[_y]!;
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
/// It always takes two inputs and has one output.  All ports have the same width.
abstract class _TwoInputBitwiseGate extends Module
    with InlineSystemVerilog, CustomCirct {
  /// Name for a port of this module.
  late final String _a, _b, _y;

  /// An input to this gate.
  Logic get a => input(_a);

  /// An input to this gate.
  Logic get b => input(_b);

  /// The output of this gate.
  Logic get y => output(_y);

  final LogicValues Function(LogicValues a, LogicValues b) _op;
  final String _svOpStr;
  final String _circtOpStr;

  /// Constructs a two-input bitwise gate for an abitrary custom functional implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When this
  /// [Module] is in-lined as SystemVerilog, it will use [_svOpStr] as a String between the two input
  /// signal names (e.g. if [_svOpStr] was "&", generated SystemVerilog may look like "a & b").
  _TwoInputBitwiseGate(
      this._op, this._svOpStr, this._circtOpStr, Logic a, dynamic b,
      {String name = 'gate2'})
      : super(name: name) {
    if (b is Logic && a.width != b.width) {
      throw Exception(
          'Input widths must match, but found $a and $b with different widths.');
    }

    var bLogic = b is Logic ? b : Const(b, width: a.width);

    _a = Module.unpreferredName('a_' + a.name);
    _b = Module.unpreferredName('b_' + bLogic.name);
    _y = Module.unpreferredName('${a.name}_${name}_${bLogic.name}');

    addInput(_a, a, width: a.width);
    addInput(_b, bLogic, width: bLogic.width);
    addOutput(_y, width: a.width);

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    a.glitch.listen((args) {
      _execute();
    });
    b.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    dynamic toPut;
    try {
      toPut = _op(a.value, b.value);
    } catch (e) {
      // in case of things like divide by 0
      toPut = LogicValue.x;
    }
    y.put(toPut);
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) throw Exception('Gate has exactly two inputs.');
    var a = inputs[_a]!;
    var b = inputs[_b]!;
    return '$a $_svOpStr $b';
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == 2);
    assert(outputs.length == 1);
    var aName = inputs[_a]!;
    var bName = inputs[_b]!;
    var yName = outputs[_y]!;
    return [
      '// $instanceName',
      '%$yName = comb.$_circtOpStr %$aName, %$bName : i${y.width}'
    ].join('\n');
  }
}

/// A generic two-input comparison gate [Module].
///
/// It always takes two inputs of the same width and has one 1-bit output.
abstract class _TwoInputComparisonGate extends Module
    with InlineSystemVerilog, CustomCirct {
  late final String _a, _b, _y;

  /// An input to this gate.
  Logic get a => input(_a);

  /// An input to this gate.
  Logic get b => input(_b);

  /// The output of this gate.
  Logic get y => output(_y);

  final LogicValue Function(LogicValues a, LogicValues b) _op;
  final String _svOpStr;
  final String _circtOpStr;

  /// Constructs a two-input comparison gate for an abitrary custom functional implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When this
  /// [Module] is in-lined as SystemVerilog, it will use [_svOpStr] as a String between the two input
  /// signal names (e.g. if [_svOpStr] was ">", generated SystemVerilog may look like "a > b").
  _TwoInputComparisonGate(
      this._op, this._svOpStr, this._circtOpStr, Logic a, dynamic b,
      {String name = 'cmp2'})
      : super(name: name) {
    if (b is Logic && a.width != b.width) {
      throw Exception(
          'Input widths must match, but found $a and $b with different widths.');
    }

    var bLogic = b is Logic ? b : Const(b, width: a.width);

    _a = Module.unpreferredName('a_' + a.name);
    _b = Module.unpreferredName('b_' + bLogic.name);
    _y = Module.unpreferredName('${a.name}_${name}_${bLogic.name}');

    addInput(_a, a, width: a.width);
    addInput(_b, bLogic, width: bLogic.width);
    addOutput(_y);

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    a.glitch.listen((args) {
      _execute();
    });
    b.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    y.put(_op(a.value, b.value));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) throw Exception('Gate has exactly two inputs.');
    var a = inputs[_a]!;
    var b = inputs[_b]!;
    return '$a $_svOpStr $b';
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == 2);
    assert(outputs.length == 1);
    var aName = inputs[_a]!;
    var bName = inputs[_b]!;
    var yName = outputs[_y]!;
    return [
      '// $instanceName',
      '%$yName = comb.icmp $_circtOpStr %$aName, %$bName : i${a.width}'
    ].join('\n');
  }
}

/// A generic two-input shift gate [Module].
///
/// It always takes two inputs and has one output of equal width to the primary of the input.
class _ShiftGate extends Module with InlineSystemVerilog, CustomCirct {
  late final String _a, _b, _y;

  /// The primary input to this gate.
  Logic get a => input(_a);

  /// The shift amount for this gate.
  Logic get b => input(_b);

  /// The output of this gate.
  Logic get y => output(_y);

  final LogicValues Function(LogicValues a, LogicValues b) _op;
  final String _svOpStr;
  final String _circtOpStr;

  /// Whether or not this gate operates on a signed number.
  final bool signed;

  /// Constructs a two-input shift gate for an abitrary custom functional implementation.
  ///
  /// The function [_op] is executed as the custom functional behavior.  When this
  /// [Module] is in-lined as SystemVerilog, it will use [_svOpStr] as a String between the two input
  /// signal names (e.g. if [_svOpStr] was ">>", generated SystemVerilog may look like "a >> b").
  _ShiftGate(this._op, this._svOpStr, this._circtOpStr, Logic a, dynamic b,
      {String name = 'gate2', this.signed = false})
      : super(name: name) {
    var bLogic = b is Logic ? b : Const(b, width: a.width);

    _a = Module.unpreferredName('a_' + a.name);
    _b = Module.unpreferredName('b_' + b.name);
    _y = Module.unpreferredName('${a.name}_${name}_${bLogic.name}');

    addInput(_a, a, width: a.width);
    addInput(_b, bLogic, width: bLogic.width);
    addOutput(_y, width: a.width);

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    a.glitch.listen((args) {
      _execute();
    });
    b.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    y.put(_op(a.value, b.value));
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 2) throw Exception('Gate has exactly two inputs.');
    var a = inputs[_a]!;
    var b = inputs[_b]!;
    var aStr = signed ? '\$signed($a)' : a;
    return '$aStr $_svOpStr $b';
  }

  List<String> _paddingCirct(String newName, String originalName, Logic signal,
      int targetWidth, CirctSynthesizer synthesizer) {
    assert(signal.width <= targetWidth);

    var lines = <String>[];
    var paddingVar = synthesizer.nextTempName();
    var paddingWidth = targetWidth - signal.width;

    if (signed) {
      var signVar = synthesizer.nextTempName();
      lines.add(
          '%$signVar = comb.extract %$originalName from ${signal.width - 1} :'
          '(i${signal.width}) -> i1');
      lines.add('%$paddingVar = comb.replicate %$signVar : '
          '(i1) -> i$paddingWidth');
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
    assert(inputs.length == 2);
    assert(outputs.length == 1);

    var aName = inputs[_a]!;
    var bName = inputs[_b]!;
    var inputWidth = max(a.width, b.width);
    var inputLines = <String>[];
    var aWideName = aName, bWideName = bName;
    if (a.width < inputWidth) {
      aWideName = synthesizer.nextTempName();
      inputLines
          .addAll(_paddingCirct(aWideName, aName, a, inputWidth, synthesizer));
    }
    if (b.width < inputWidth) {
      bWideName = synthesizer.nextTempName();
      inputLines
          .addAll(_paddingCirct(bWideName, bName, b, inputWidth, synthesizer));
    }

    var yName = outputs[_y]!;
    var yWideName = yName;
    var outputLines = <String>[];
    if (y.width < inputWidth) {
      yWideName = synthesizer.nextTempName();
      outputLines.add('%$yName = comb.extract %$yWideName from 0 :'
          ' (i$inputWidth) -> i${y.width}');
    }

    return [
      '// $instanceName',
      ...inputLines,
      '%$yWideName = comb.$_circtOpStr %$aWideName, %$bWideName : i$inputWidth',
      ...outputLines,
    ].join('\n');
  }
}

/// A two-input AND gate.
class And2Gate extends _TwoInputBitwiseGate {
  And2Gate(Logic a, Logic b, {String name = 'and'})
      : super((a, b) => a & b, '&', 'and', a, b, name: name);
}

/// A two-input OR gate.
class Or2Gate extends _TwoInputBitwiseGate {
  Or2Gate(Logic a, Logic b, {String name = 'or'})
      : super((a, b) => a | b, '|', 'or', a, b, name: name);
}

/// A two-input XOR gate.
class Xor2Gate extends _TwoInputBitwiseGate {
  Xor2Gate(Logic a, Logic b, {String name = 'xor'})
      : super((a, b) => a ^ b, '^', 'xor', a, b, name: name);
}

//TODO: allow math operations on different sized Logics, with optional overrideable output size

/// A two-input addition module.
class Add extends _TwoInputBitwiseGate {
  Add(Logic a, dynamic b, {String name = 'add'})
      : super((a, b) => a + b, '+', 'add', a, b, name: name);
}

/// A two-input subtraction module.
class Subtract extends _TwoInputBitwiseGate {
  Subtract(Logic a, dynamic b, {String name = 'subtract'})
      : super((a, b) => a - b, '-', 'sub', a, b, name: name);
}

/// A two-input multiplication module.
class Multiply extends _TwoInputBitwiseGate {
  Multiply(Logic a, dynamic b, {String name = 'multiply'})
      : super((a, b) => a * b, '*', 'mul', a, b, name: name);
}

/// A two-input divison module.
class Divide extends _TwoInputBitwiseGate {
  Divide(Logic a, dynamic b, {String name = 'divide'})
      : super((a, b) => a / b, '/', 'divu', a, b, name: name);
}

/// A two-input equality comparison module.
class Equals extends _TwoInputComparisonGate {
  Equals(Logic a, dynamic b, {String name = 'equals'})
      : super((a, b) => a.eq(b), '==', 'eq', a, b, name: name);
}

/// A two-input comparison module for less-than.
class LessThan extends _TwoInputComparisonGate {
  LessThan(Logic a, dynamic b, {String name = 'lessthan'})
      : super((a, b) => a < b, '<', 'ult', a, b, name: name);
}

/// A two-input comparison module for greater-than.
class GreaterThan extends _TwoInputComparisonGate {
  GreaterThan(Logic a, dynamic b, {String name = 'greaterthan'})
      : super((a, b) => a > b, '>', 'ugt', a, b, name: name);
}

/// A two-input comparison module for less-than-or-equal-to.
class LessThanOrEqual extends _TwoInputComparisonGate {
  LessThanOrEqual(Logic a, dynamic b, {String name = 'lessthanorequal'})
      : super((a, b) => a <= b, '<=', 'ule', a, b, name: name);
}

/// A two-input comparison module for greater-than-or-equal-to.
class GreaterThanOrEqual extends _TwoInputComparisonGate {
  GreaterThanOrEqual(Logic a, dynamic b, {String name = 'greaterthanorequal'})
      : super((a, b) => a >= b, '>=', 'uge', a, b, name: name);
}

/// A unary AND gate.
class AndUnary extends _OneInputUnaryGate {
  AndUnary(Logic a, {String name = 'uand'})
      : super((a) => a.and(), '&', a, name: name);

  @override
  String _generateCirct(
      String aName, String yName, CirctSynthesizer synthesizer) {
    var neg1 = synthesizer.nextTempName();
    return [
      '%$neg1 = hw.constant -1 : i${a.width}',
      '%$yName = comb.icmp eq %$aName, %$neg1 : i${a.width}'
    ].join('\n');
  }
}

/// A unary OR gate.
class OrUnary extends _OneInputUnaryGate {
  OrUnary(Logic a, {String name = 'uor'})
      : super((a) => a.or(), '|', a, name: name);

  @override
  String _generateCirct(
      String aName, String yName, CirctSynthesizer synthesizer) {
    var zero = synthesizer.nextTempName();
    return [
      '%$zero = hw.constant 0 : i${a.width}',
      '%$yName = comb.icmp ne %$aName, %$zero : i${a.width}'
    ].join('\n');
  }
}

/// A unary XOR gate.
class XorUnary extends _OneInputUnaryGate {
  XorUnary(Logic a, {String name = 'uxor'})
      : super((a) => a.xor(), '^', a, name: name);

  @override
  String _generateCirct(
      String aName, String yName, CirctSynthesizer synthesizer) {
    return '%$yName = comb.parity %$aName : i${a.width}';
  }
}

/// A logical right-shift module.
class RShift extends _ShiftGate {
  RShift(Logic a, Logic shamt, {String name = 'rshift'})
      :
        // Note: >>> vs >> is backwards for SystemVerilog and Dart
        super((a, shamt) => a >>> shamt, '>>', 'shru', a, shamt, name: name);
}

/// An arithmetic right-shift module.
class ARShift extends _ShiftGate {
  ARShift(Logic a, Logic shamt, {String name = 'arshift'})
      :
        // Note: >>> vs >> is backwards for SystemVerilog and Dart
        super((a, shamt) => a >> shamt, '>>>', 'shrs', a, shamt,
            name: name, signed: true);
}

/// A logical left-shift module.
class LShift extends _ShiftGate {
  LShift(Logic a, Logic shamt, {String name = 'lshift'})
      : super((a, shamt) => a << shamt, '<<', 'shl', a, shamt, name: name);
}

/// A mux (multiplexer) module.
///
/// If [control] has value `1`, then [y] gets [d1].
/// If [control] has value `0`, then [y] gets [d0].
class Mux extends Module with InlineSystemVerilog, CustomCirct {
  late final String _control, _d0, _d1, _y;

  /// The control signal for this [Mux].
  Logic get control => input(_control);

  /// [Mux] input propogated when [y] is `0`.
  Logic get d0 => input(_d0);

  /// [Mux] input propogated when [y] is `1`.
  Logic get d1 => input(_d1);

  /// Output port of the [Mux].
  Logic get y => output(_y);

  Mux(Logic control, Logic d1, Logic d0, {String name = 'mux'})
      : super(name: name) {
    if (control.width != 1) {
      throw Exception('Control must be single bit Logic, but found $control.');
    }
    if (d0.width != d1.width) {
      throw Exception('d0 ($d0) and d1 ($d1) must be same width');
    }

    _control = Module.unpreferredName('control_' + control.name);
    _d0 = Module.unpreferredName('d0_' + d0.name);
    _d1 = Module.unpreferredName('d1_' + d1.name);
    _y = Module.unpreferredName('y'); //TODO: something better here?

    addInput(_control, control);
    addInput(_d0, d0, width: d0.width);
    addInput(_d1, d1, width: d1.width);
    addOutput(_y, width: d0.width);

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values

    d0.glitch.listen((args) {
      _execute();
    });
    d1.glitch.listen((args) {
      _execute();
    });
    control.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of the mux.
  void _execute() {
    if (!control.bit.isValid) {
      y.put(control.bit);
    } else if (control.bit == LogicValue.zero) {
      y.put(d0.value);
    } else if (control.bit == LogicValue.one) {
      y.put(d1.value);
    }
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 3) throw Exception('Mux2 has exactly three inputs.');
    var d0 = inputs[_d0]!;
    var d1 = inputs[_d1]!;
    var control = inputs[_control]!;
    return '$control ? $d1 : $d0';
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == 3);
    assert(outputs.length == 1);
    var controlName = inputs[_control]!;
    var d0Name = inputs[_d0]!;
    var d1Name = inputs[_d1]!;
    var yName = outputs[_y]!;
    return [
      '// $instanceName',
      '%$yName = comb.mux %$controlName, %$d1Name, %$d0Name : i${y.width}'
    ].join('\n');
  }
}
