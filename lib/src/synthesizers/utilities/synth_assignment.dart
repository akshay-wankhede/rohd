import 'package:rohd/src/synthesizers/utilities/utilities.dart';

class SynthAssignment {
  final SynthLogic dst;
  final SynthLogic src;
  SynthAssignment(this.src, this.dst);

  @override
  String toString() {
    return '${dst.name} <= $src';
  }
}
