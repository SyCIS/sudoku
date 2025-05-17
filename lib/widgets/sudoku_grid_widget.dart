// lib/widgets/sudoku_grid_widget.dart

import 'dart:math'; // For Point
import 'package:flutter/material.dart';
import '../models/sudoku_cell.dart'; // Path to your SudokuCell model

class SudokuGridWidget extends StatelessWidget {
  final double gridSize;
  final List<List<SudokuCell>> board;
  final int? selectedRow;
  final int? selectedCol;
  final ThemeData theme;
  final Function(int r, int c) onCellSelected;

  const SudokuGridWidget({
    super.key,
    required this.gridSize,
    required this.board,
    this.selectedRow,
    this.selectedCol,
    required this.theme,
    required this.onCellSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (gridSize <= 0) {
      return Container(
          color: Colors.red,
          child: const Center(child: Text("Error: Grid size too small")));
    }
    if (board.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    double cellSize = gridSize / 9;
    Color borderColor = theme.colorScheme.outlineVariant;
    double thinWidth = 0.7;
    double thickWidth = 2.0;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 9),
      itemCount: 81, // 9x9 grid
      itemBuilder: (context, index) {
        int r = index ~/ 9;
        int c = index % 9;

        if (r >= board.length || c >= board[r].length) {
          return Container(color: Colors.orange, child: Text("E:$r,$c"));
        }

        SudokuCell cell = board[r][c];
        bool isSelectedCell = r == selectedRow && c == selectedCol;

        BorderSide topSide = BorderSide(
            width: (r % 3 == 0) ? thickWidth : thinWidth, color: borderColor);
        BorderSide leftSide = BorderSide(
            width: (c % 3 == 0) ? thickWidth : thinWidth, color: borderColor);
        BorderSide rightSide = BorderSide(
            width: ((c + 1) % 3 == 0 || c == 8) ? thickWidth : thinWidth,
            color: borderColor);
        BorderSide bottomSide = BorderSide(
            width: ((r + 1) % 3 == 0 || r == 8) ? thickWidth : thinWidth,
            color: borderColor);

        Border border =
            Border(top: topSide, left: leftSide, right: rightSide, bottom: bottomSide);

        Color cellColor;
        if (isSelectedCell) {
          cellColor = theme.colorScheme.primaryContainer.withOpacity(0.5);
        } else if (cell.isFixed) {
          cellColor = theme.colorScheme.surfaceContainerHighest;
        } else {
          cellColor = theme.colorScheme.surfaceContainer;
        }

        Color textColor;
        if (cell.isError && !cell.isFixed) {
          textColor = theme.colorScheme.error;
        } else if (cell.isFixed) {
          textColor = theme.colorScheme.onSurfaceVariant;
        } else {
          textColor = theme.colorScheme.primary;
        }

        return GestureDetector(
          onTap: () => onCellSelected(r, c),
          child: Container(
            width: cellSize,
            height: cellSize,
            decoration: BoxDecoration(color: cellColor, border: border),
            alignment: Alignment.center,
            child: Text(
              cell.value == 0 ? '' : cell.value.toString(),
              style: TextStyle(
                fontSize: cellSize * 0.55,
                fontWeight: cell.isFixed ? FontWeight.bold : FontWeight.normal,
                color: textColor,
              ),
            ),
          ),
        );
      },
    );
  }
}