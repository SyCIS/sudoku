// lib/models/sudoku_cell.dart

class SudokuCell {
  int value;
  bool isFixed;
  bool isError;

  SudokuCell(this.value, {this.isFixed = false, this.isError = false});
}