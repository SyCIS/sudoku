// lib/widgets/circular_number_picker.dart

import 'dart:math';
import 'package:flutter/material.dart';

class CircularNumberPicker extends StatelessWidget {
  final double size;
  final Function(int?) onNumberSelected;
  final ThemeData theme;

  const CircularNumberPicker({
    super.key,
    required this.size,
    required this.onNumberSelected,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final double radius = size / 2;
    final double numCircRad = radius * 0.70; // Radius for the number circle
    final double numWSize = radius * 0.40; // Size of individual number 'buttons'
    final double centerBtnSize = radius * 0.5; // Size of the clear button

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withOpacity(0.95),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 8,
            spreadRadius: 1,
          )
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Clear button (center)
          GestureDetector(
            onTap: () => onNumberSelected(null), // Pass null for clear
            child: Container(
              width: centerBtnSize,
              height: centerBtnSize,
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withOpacity(0.8),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.clear,
                color: theme.colorScheme.onErrorContainer,
                size: centerBtnSize * 0.6,
              ),
            ),
          ),
          // Number buttons
          for (int i = 1; i <= 9; i++)
            _buildNumBtn(i, numCircRad, numWSize),
        ],
      ),
    );
  }

  Widget _buildNumBtn(int num, double circleRadius, double widgetSize) {
    // Calculate angle for each number.
    // (2 * pi * (num - 1) / 9) distributes numbers around the circle.
    // - (pi / 2) adjusts the starting point to the top.
    // + (pi / 9) // Small offset to center numbers visually if needed, can adjust
    final double angle = (2 * pi * (num - 1) / 9) - (pi / 2) + (pi / 9); // Adjusted for 9 items

    final double x = circleRadius * cos(angle);
    final double y = circleRadius * sin(angle);

    return Positioned(
      // Center of the picker (size / 2) + calculated offset - half widget size (to center the widget)
      left: (size / 2) + x - (widgetSize / 2),
      top: (size / 2) + y - (widgetSize / 2),
      child: GestureDetector(
        onTap: () => onNumberSelected(num),
        child: Container(
          width: widgetSize,
          height: widgetSize,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            num.toString(),
            style: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: widgetSize * 0.55, // Adjust font size relative to button size
            ),
          ),
        ),
      ),
    );
  }
}