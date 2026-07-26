import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/game_2048/game_2048_engine.dart';

void main() {
  group('Game2048Engine', () {
    test('initializes with a 4x4 board, score 0, and 2 starting tiles', () {
      final engine = Game2048Engine(random: Random(0));

      expect(engine.board, hasLength(4));
      for (final row in engine.board) {
        expect(row, hasLength(4));
      }

      expect(engine.score, 0);
      expect(engine.isGameOver, isFalse);

      final nonZeroTiles = engine.board
          .expand((row) => row)
          .where((tile) => tile != 0)
          .toList();
      expect(nonZeroTiles, hasLength(2));
      expect(nonZeroTiles.every((tile) => tile == 2 || tile == 4), isTrue);
    });

    test('move left compresses, merges once per tile, and adds score', () {
      final engine =
          Game2048Engine(random: _SequenceRandom(ints: [9]), autoStart: false)
            ..board = [
              [2, 0, 2, 2],
              [2, 2, 2, 0],
              [2, 2, 4, 4],
              [0, 0, 0, 0],
            ];

      engine.move(MoveDirection.left);

      expect(engine.board[0], [4, 2, 0, 0]);
      expect(engine.board[1], [4, 2, 0, 0]);
      expect(engine.board[2], [4, 8, 0, 0]);
      expect(engine.board[3], [0, 0, 0, 2]);
      expect(engine.score, 20);
      expect(_countNonZeroTiles(engine.board), 7);
    });

    test('move right works correctly', () {
      final engine =
          Game2048Engine(random: _SequenceRandom(ints: [9]), autoStart: false)
            ..board = [
              [2, 0, 2, 2],
              [0, 4, 4, 0],
              [2, 2, 2, 2],
              [0, 0, 0, 0],
            ];

      engine.move(MoveDirection.right);

      expect(engine.board[0], [0, 0, 2, 4]);
      expect(engine.board[1], [0, 0, 0, 8]);
      expect(engine.board[2], [0, 0, 4, 4]);
      expect(engine.board[3], [0, 0, 2, 0]);
      expect(engine.score, 20);
    });

    test('move up works correctly', () {
      final engine =
          Game2048Engine(random: _SequenceRandom(ints: [10]), autoStart: false)
            ..board = [
              [2, 0, 2, 0],
              [2, 2, 0, 0],
              [0, 2, 2, 0],
              [0, 0, 2, 0],
            ];

      engine.move(MoveDirection.up);

      expect(_column(engine.board, 0), [4, 0, 0, 0]);
      expect(_column(engine.board, 1), [4, 0, 0, 0]);
      expect(_column(engine.board, 2), [4, 2, 0, 2]);
      expect(_column(engine.board, 3), [0, 0, 0, 0]);
      expect(engine.score, 12);
    });

    test('move down works correctly', () {
      final engine =
          Game2048Engine(random: _SequenceRandom(ints: [8]), autoStart: false)
            ..board = [
              [2, 0, 2, 0],
              [2, 2, 0, 0],
              [0, 2, 2, 0],
              [0, 0, 2, 0],
            ];

      engine.move(MoveDirection.down);

      expect(_column(engine.board, 0), [0, 0, 2, 4]);
      expect(_column(engine.board, 1), [0, 0, 0, 4]);
      expect(_column(engine.board, 2), [0, 0, 2, 4]);
      expect(_column(engine.board, 3), [0, 0, 0, 0]);
      expect(engine.score, 12);
    });

    test('invalid move does not add a new tile or change score', () {
      final engine = Game2048Engine(random: Random(4), autoStart: false)
        ..board = [
          [2, 4, 8, 16],
          [32, 64, 128, 256],
          [512, 1024, 2, 4],
          [8, 16, 32, 64],
        ];

      final beforeBoard = _copyBoard(engine.board);

      engine.move(MoveDirection.left);

      expect(engine.board, beforeBoard);
      expect(engine.score, 0);
      expect(engine.isGameOver, isTrue);
    });

    test(
      'detects game over when no spaces and no adjacent equal tiles exist',
      () {
        final engine = Game2048Engine(random: Random(5), autoStart: false)
          ..board = [
            [2, 4, 2, 4],
            [4, 2, 4, 2],
            [2, 4, 2, 4],
            [4, 2, 4, 2],
          ];

        engine.updateGameOverStatus();

        expect(engine.isGameOver, isTrue);
      },
    );

    test('is not game over when a merge is still possible', () {
      final engine = Game2048Engine(random: Random(6), autoStart: false)
        ..board = [
          [2, 4, 2, 4],
          [4, 2, 4, 2],
          [2, 4, 2, 4],
          [4, 2, 4, 4],
        ];

      engine.updateGameOverStatus();

      expect(engine.isGameOver, isFalse);
    });

    test(
      'newGame resets score, game over status, and creates 2 starting tiles',
      () {
        final engine = Game2048Engine(random: Random(7), autoStart: false)
          ..board = [
            [2, 4, 8, 16],
            [32, 64, 128, 256],
            [512, 1024, 2, 4],
            [8, 16, 32, 64],
          ]
          ..score = 100
          ..isGameOver = true;

        engine.newGame();

        expect(engine.score, 0);
        expect(engine.isGameOver, isFalse);
        expect(_countNonZeroTiles(engine.board), 2);
        expect(
          engine.board
              .expand((row) => row)
              .where((tile) => tile != 0)
              .every((tile) => tile == 2 || tile == 4),
          isTrue,
        );
      },
    );

    test('reset delegates to newGame behavior', () {
      final engine = Game2048Engine(random: Random(8), autoStart: false)
        ..board = [
          [2, 4, 8, 16],
          [32, 64, 128, 256],
          [512, 1024, 2, 4],
          [8, 16, 32, 64],
        ]
        ..score = 200
        ..isGameOver = true;

      engine.reset();

      expect(engine.score, 0);
      expect(engine.isGameOver, isFalse);
      expect(_countNonZeroTiles(engine.board), 2);
    });
  });
}

int _countNonZeroTiles(List<List<int>> board) {
  return board.expand((row) => row).where((tile) => tile != 0).length;
}

List<int> _column(List<List<int>> board, int index) {
  return [for (final row in board) row[index]];
}

List<List<int>> _copyBoard(List<List<int>> board) {
  return [
    for (final row in board) [...row],
  ];
}

class _SequenceRandom implements Random {
  _SequenceRandom({List<int>? ints, List<double>? doubles})
    : _ints = ints ?? const [0],
      _doubles = doubles ?? const [0.0];

  final List<int> _ints;
  final List<double> _doubles;

  int _intIndex = 0;
  int _doubleIndex = 0;

  @override
  bool nextBool() => nextDouble() >= 0.5;

  @override
  double nextDouble() {
    final value = _doubles[_doubleIndex % _doubles.length];
    _doubleIndex++;
    return value;
  }

  @override
  int nextInt(int max) {
    final value = _ints[_intIndex % _ints.length];
    _intIndex++;
    return value % max;
  }
}
