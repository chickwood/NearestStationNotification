import 'package:material_ui/material_ui.dart';

class AppBarAction extends IconButton {
  const AppBarAction({
    super.key,
    required super.onPressed,
    required super.icon,
    super.tooltip,
    super.color = Colors.white,
    super.disabledColor = const Color(0xFFA0C0FF),
    super.constraints = const BoxConstraints(minWidth: 40, minHeight: 40),
    super.padding = EdgeInsets.zero,
    super.style = const ButtonStyle(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  });
}
