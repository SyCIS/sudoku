// lib/game_logic/sudoku_generator.dart

import 'dart:math';
import '../models/sudoku_cell.dart';
import 'difficulty.dart';

class SudokuGenerator {
  // A pre-solved board. For more variety, this should be generated or transformed.
  static final List<List<int>> _solvedBoard = () {
    return [
      [5, 3, 4, 6, 7, 8, 9, 1, 2],
      [6, 7, 2, 1, 9, 5, 3, 4, 8],
      [1, 9, 8, 3, 4, 2, 5, 6, 7],
      [8, 5, 9, 7, 6, 1, 4, 2, 3],
      [4, 2, 6, 8, 5, 3, 7, 9, 1],
      [7, 1, 3, 9, 2, 4, 8, 5, 6],
      [9, 6, 1, 5, 3, 7, 2, 8, 4],
      [2, 8, 7, 4, 1, 9, 6, 3, 5],
      [3, 4, 5, 2, 8, 6, 1, 7, 9],
    ];
  }();

  static List<List<SudokuCell>> generatePuzzle(Difficulty difficulty) {
    // Create a deep copy of the solved board to work with
    List<List<SudokuCell>> puzzle = List.generate(
        9,
        (r) => List.generate(
            9, (c) => SudokuCell(_solvedBoard[r][c], isFixed: false)));

    int numbersToRemove;
    switch (difficulty) {
      case Difficulty.superEasy:
        numbersToRemove = 1; // Note: This makes a very easy puzzle (only 1 empty cell)
        break;
      case Difficulty.easy:
        numbersToRemove = 35;
        break;
      case Difficulty.medium:
        numbersToRemove = 45;
        break;
      case Difficulty.hard:
        numbersToRemove = 50;
        break;
      case Difficulty.expert:
        numbersToRemove = 55;
        break;
      case Difficulty.insane:
        numbersToRemove = 60;
        break;
    }

    Random random = Random();
    numbersToRemove = min(numbersToRemove, 81); // Cap removal

    List<Point<int>> allCells = [];
    for (int r = 0; r < 9; r++) {
      for (int c = 0; c < 9; c++) {
        allCells.add(Point(r, c));
      }
    }
    allCells.shuffle(random);

    // Special handling for superEasy to ensure only one cell is cleared if numbersToRemove is 1
    // This specific logic for superEasy might need review based on desired difficulty.
    // If numbersToRemove is 1 for superEasy, it will clear exactly one random cell.
    if (difficulty == Difficulty.superEasy && numbersToRemove == 1 && allCells.isNotEmpty) {
        // The original logic picked one random cell to empty.
        // Let's stick to the original intent for now.
        int r = random.nextInt(9);
        int c = random.nextInt(9);
        puzzle[r][c].value = 0;
    } else {
      // General case for removing cells
      for (int i = 0; i < numbersToRemove && i < allCells.length; i++) {
        puzzle[allCells[i].x][allCells[i].y].value = 0;
      }
    }


    // Mark the remaining non-zero cells as fixed
    for (int r = 0; r < 9; r++) {
      for (int c = 0; c < 9; c++) {
        if (puzzle[r][c].value != 0) {
          puzzle[r][c].isFixed = true;
        }
      }
    }
    return puzzle;
  }
}