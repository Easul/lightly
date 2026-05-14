import 'dart:math';

enum MoveDirection { up, down, left, right }

class Game2048Engine {
  Game2048Engine({Random? random, bool autoStart = true})
    : _random = random ?? Random() {
    board = _createEmptyBoard();

    if (autoStart) {
      newGame();
    }
  }

  static const int size = 4;

  final Random _random;

  late List<List<int>> board;
  int score = 0;
  bool isGameOver = false;

  void reset() {
    newGame();
  }

  void newGame() {
    board = _createEmptyBoard();
    score = 0;
    isGameOver = false;

    _addRandomTile();
    _addRandomTile();
    updateGameOverStatus();
  }

  void move(MoveDirection direction) {
    final previousBoard = _copyBoard(board);

    if (direction == MoveDirection.left) {
      _moveLeft();
    } else if (direction == MoveDirection.right) {
      _moveRight();
    } else if (direction == MoveDirection.up) {
      _moveUp();
    } else {
      _moveDown();
    }

    final hasChanged = !_boardsEqual(previousBoard, board);
    if (hasChanged) {
      _addRandomTile();
    }

    updateGameOverStatus();
  }

  void updateGameOverStatus() {
    if (_hasEmptyTile()) {
      isGameOver = false;
      return;
    }

    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        final current = board[row][col];

        if (row + 1 < size && board[row + 1][col] == current) {
          isGameOver = false;
          return;
        }

        if (col + 1 < size && board[row][col + 1] == current) {
          isGameOver = false;
          return;
        }
      }
    }

    isGameOver = true;
  }

  void _moveLeft() {
    for (var row = 0; row < size; row++) {
      board[row] = _processLine(board[row]);
    }
  }

  void _moveRight() {
    for (var row = 0; row < size; row++) {
      final reversedRow = board[row].reversed.toList();
      board[row] = _processLine(reversedRow).reversed.toList();
    }
  }

  void _moveUp() {
    for (var col = 0; col < size; col++) {
      final column = _getColumn(col);
      final updatedColumn = _processLine(column);
      _setColumn(col, updatedColumn);
    }
  }

  void _moveDown() {
    for (var col = 0; col < size; col++) {
      final reversedColumn = _getColumn(col).reversed.toList();
      final updatedColumn = _processLine(reversedColumn).reversed.toList();
      _setColumn(col, updatedColumn);
    }
  }

  List<int> _processLine(List<int> line) {
    final compressed = line.where((value) => value != 0).toList();
    final merged = <int>[];

    var index = 0;
    while (index < compressed.length) {
      final current = compressed[index];

      if (index + 1 < compressed.length && compressed[index + 1] == current) {
        final mergedValue = current * 2;
        merged.add(mergedValue);
        score += mergedValue;
        index += 2;
      } else {
        merged.add(current);
        index++;
      }
    }

    while (merged.length < size) {
      merged.add(0);
    }

    return merged;
  }

  void _addRandomTile() {
    final emptyPositions = <Point<int>>[];

    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        if (board[row][col] == 0) {
          emptyPositions.add(Point(row, col));
        }
      }
    }

    if (emptyPositions.isEmpty) {
      return;
    }

    final position = emptyPositions[_random.nextInt(emptyPositions.length)];
    board[position.x][position.y] = _random.nextDouble() < 0.9 ? 2 : 4;
  }

  bool _hasEmptyTile() {
    return board.any((row) => row.any((tile) => tile == 0));
  }

  List<int> _getColumn(int col) {
    return [for (var row = 0; row < size; row++) board[row][col]];
  }

  void _setColumn(int col, List<int> values) {
    for (var row = 0; row < size; row++) {
      board[row][col] = values[row];
    }
  }

  List<List<int>> _copyBoard(List<List<int>> source) {
    return [
      for (final row in source) [...row],
    ];
  }

  bool _boardsEqual(List<List<int>> a, List<List<int>> b) {
    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        if (a[row][col] != b[row][col]) {
          return false;
        }
      }
    }

    return true;
  }

  static List<List<int>> _createEmptyBoard() {
    return List.generate(size, (_) => List.filled(size, 0));
  }
}
