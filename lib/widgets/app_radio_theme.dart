import 'package:flutter/material.dart';

// Helper widget for RadioGroup if needed, or just use standard Column
// Helper widget for RadioTheme if needed
class AppRadioTheme extends StatelessWidget {
  final Widget child;

  const AppRadioTheme({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return Theme.of(context).primaryColor;
            }
            return Colors.grey.shade600;
          }),
        ),
      ),
      child: child,
    );
  }
}
