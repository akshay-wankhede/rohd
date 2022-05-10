/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// bus.dart
/// Definition for modules related to bus operations
///
/// 2021 August 2
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';

/// A [Module] which gives access to a subset range of signals of the input.
///
/// The returned signal is inclusive of both the [startIndex] and [endIndex].
/// The output [subset] will have width equal to `|endIndex - startIndex| + 1`.
class BusSubset extends Module with InlineSystemVerilog, CustomCirct {
  /// Name for a port of this module.
  late final String _original, _subset;

  /// The input to get a subset of.
  Logic get original => input(_original);

  /// The output, a subset of [original].
  Logic get subset => output(_subset);

  /// Index of the subset.
  final int startIndex, endIndex;

  BusSubset(Logic bus, this.startIndex, this.endIndex,
      {String name = 'bussubset'})
      : super(name: name) {
    if (startIndex < 0 || endIndex < 0) {
      throw Exception('Cannot access negative indices!'
          '  Indices $startIndex and/or $endIndex are invalid.');
    }
    if (endIndex > bus.width - 1 || startIndex > bus.width - 1) {
      throw Exception(
          'Index out of bounds, indices $startIndex and $endIndex must be less than width-1');
    }

    _original = Module.unpreferredName('original_' + bus.name);
    _subset =
        Module.unpreferredName('subset_${endIndex}_${startIndex}_' + bus.name);

    addInput(_original, bus, width: bus.width);
    var newWidth = (endIndex - startIndex).abs() + 1;
    addOutput(_subset, width: newWidth);
    subset
        .makeUnassignable(); // so that people can't do a slice assign, not (yet?) implemented

    _setup();
  }

  /// Performs setup steps for custom functional behavior.
  void _setup() {
    _execute(); // for initial values
    original.glitch.listen((args) {
      _execute();
    });
  }

  /// Executes the functional behavior of this gate.
  void _execute() {
    if (endIndex < startIndex) {
      subset.put(original.value.getRange(endIndex, startIndex + 1).reversed);
    } else {
      subset.put(original.value.getRange(startIndex, endIndex + 1));
    }
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != 1) {
      throw Exception('BusSubset has exactly one input, but saw $inputs.');
    }
    var a = inputs[_original]!;

    // SystemVerilog doesn't allow reverse-order select to reverse a bus, so do it manually
    if (startIndex > endIndex) {
      return '{' +
          List.generate(startIndex - endIndex + 1, (i) => '$a[${endIndex + i}]')
              .join(', ') +
          '}';
    }

    var sliceString =
        startIndex == endIndex ? '[$startIndex]' : '[$endIndex:$startIndex]';
    return '$a$sliceString';
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
    var originalName = inputs[_original];
    var subsetName = outputs[_subset];

    var lines = <String>['// $instanceName'];

    if (startIndex < endIndex) {
      lines.add('%$subsetName = comb.extract %$originalName from $startIndex :'
          ' (i${original.width}) -> i${subset.width}');
    } else {
      var bitNames = <String>[];
      for (var i = endIndex; i <= startIndex; i++) {
        var bitName = synthesizer.nextTempName();
        lines.add('%$bitName = comb.extract %$originalName from $i :'
            '(i${original.width}) -> i1');
        bitNames.add(bitName);
      }
      var bitsString = bitNames.map((e) => '%$e').join(', ');
      var widthsString = bitNames.map((e) => 'i1').join(', ');
      lines.add('%$subsetName = comb.concat $bitsString : $widthsString');
    }

    return lines.join('\n');
  }
}

/// A [Module] that performs concatenation of signals into one bigger [Logic].
///
/// The concatenation occurs such that index 0 of [signals] is the *most* significant bit(s).
///
/// You can use convenience functions [LogicSwizzle.swizzle] or [LogicSwizzle.rswizzle] to
/// more easily use this [Module].
class Swizzle extends Module with InlineSystemVerilog, CustomCirct {
  final String _out = Module.unpreferredName('swizzled');

  /// The output port containing concatenated signals.
  Logic get out => output(_out);

  final List<Logic> _swizzleInputs = [];

  Swizzle(List<Logic> signals, {String name = 'swizzle'}) : super(name: name) {
    var idx = 0;
    var outputWidth = 0;
    for (var signal in signals.reversed) {
      //reverse so bit 0 is the last thing in the input list
      var inputName = Module.unpreferredName('in${idx++}');
      addInput(inputName, signal, width: signal.width);
      _swizzleInputs.add(input(inputName));
      outputWidth += signal.width;
    }
    addOutput(_out, width: outputWidth);

    for (var swizzleInput in _swizzleInputs) {
      // var startIdx = _swizzleInputs.getRange(0, _swizzleInputs.indexOf(swizzleInput)).map((e) => e.width).reduce((a, b) => a+b);
      var startIdx = 0;
      for (var xsi in _swizzleInputs) {
        if (xsi == swizzleInput) break;
        startIdx += xsi.width;
      }
      _execute(startIdx, swizzleInput, null); // for initial values
      swizzleInput.glitch.listen((args) {
        _execute(startIdx, swizzleInput, args);
      });
    }
  }

  /// Executes the functional behavior of this gate.
  void _execute(int startIdx, Logic swizzleInput, LogicValueChanged? args) {
    var updatedVal = out.value.withSet(startIdx, swizzleInput.value);
    out.put(updatedVal);
  }

  @override
  String inlineVerilog(Map<String, String> inputs) {
    if (inputs.length != _swizzleInputs.length) {
      throw Exception('This swizzle has ${_swizzleInputs.length} inputs,'
          ' but saw $inputs with ${inputs.length} values.');
    }
    var inputStr = _swizzleInputs.reversed
        .where((e) => e.width > 0)
        .map((e) => inputs[e.name])
        .join(', ');
    return '{$inputStr}';
  }

  @override
  String instantiationCirct(
      String instanceType,
      String instanceName,
      Map<String, String> inputs,
      Map<String, String> outputs,
      CirctSynthesizer synthesizer) {
    assert(inputs.length == _swizzleInputs.length);
    assert(outputs.length == 1);

    var outputName = outputs[_out];

    var nonZeroSwizzleInputs =
        _swizzleInputs.reversed.where((e) => e.width > 0);

    var bitsString =
        nonZeroSwizzleInputs.map((e) => '%${inputs[e.name]}').join(', ');
    var widthsString =
        nonZeroSwizzleInputs.map((e) => 'i${e.width}').join(', ');

    return [
      '// $instanceName',
      '%$outputName = comb.concat $bitsString : $widthsString'
    ].join('\n');
  }
}
