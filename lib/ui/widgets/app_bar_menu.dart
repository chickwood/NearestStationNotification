import 'package:material_ui/material_ui.dart';

class AppBarMenu<T> extends PopupMenuButton<T> {
  const AppBarMenu({
    super.key,
    required super.itemBuilder,
    super.elevation,
    super.enabled,
    super.position,
    super.tooltip,
    super.icon,
    super.iconColor = Colors.white,
    super.constraints,
    super.padding = EdgeInsets.zero,
    super.style = const ButtonStyle(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: WidgetStatePropertyAll(Size(40, 40)),
      maximumSize: WidgetStatePropertyAll(Size(40, 40)),
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
      foregroundColor: WidgetStateProperty<Color?>.fromMap(
        <WidgetStatesConstraint, Color?>{
          WidgetState.disabled: Color(0xFFA0C0FF),
          WidgetState.any: Colors.white,
        },
      ),
    ),
    super.shape,
    super.onSelected,
  });
}
