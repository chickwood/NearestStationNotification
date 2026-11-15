import 'package:material_ui/material_ui.dart';

abstract class ResetableState<T extends StatefulWidget> extends State<T> {
  void _noop() {}

  void resetState() {
    if (!mounted) return;
    setState(_noop);
  }
}
