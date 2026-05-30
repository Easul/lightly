import 'package:flutter/material.dart';

import 'game_2048_engine.dart';

class GameBoard extends StatelessWidget {
  const GameBoard({super.key, required this.board, required this.onMove});

  static const _swipeVelocityThreshold = 150.0;

  final List<List<int>> board;
  final ValueChanged<MoveDirection> onMove;

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity == null) return;
    if (velocity > _swipeVelocityThreshold) {
      onMove(MoveDirection.right);
    } else if (velocity < -_swipeVelocityThreshold) {
      onMove(MoveDirection.left);
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity == null) return;
    if (velocity > _swipeVelocityThreshold) {
      onMove(MoveDirection.down);
    } else if (velocity < -_swipeVelocityThreshold) {
      onMove(MoveDirection.up);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFBBADA0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: GestureDetector(
          onHorizontalDragEnd: _handleHorizontalDragEnd,
          onVerticalDragEnd: _handleVerticalDragEnd,
          child: GridView.count(
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            children: [
              for (var row = 0; row < 4; row++)
                for (var col = 0; col < 4; col++)
                  _GameTile(value: board[row][col]),
            ],
          ),
        ),
      ),
    );
  }
}

class ScoreCard extends StatelessWidget {
  const ScoreCard({super.key, required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFBBADA0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          const Text(
            'SCORE',
            style: TextStyle(
              color: Color(0xFFEEE4DA),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '$score',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class GameOverBanner extends StatelessWidget {
  const GameOverBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF8F7A66),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Game Over!',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.value});

  static const _tileColors = <int, Color>{
    2: Color(0xFFEEE4DA),
    4: Color(0xFFEDE0C8),
    8: Color(0xFFF2B179),
    16: Color(0xFFF59563),
    32: Color(0xFFF67C5F),
    64: Color(0xFFF65E3B),
    128: Color(0xFFEDCF72),
    256: Color(0xFFEDCC61),
    512: Color(0xFFEDC850),
    1024: Color(0xFFEDC53F),
    2048: Color(0xFFEDC22E),
  };

  final int value;

  Color get _backgroundColor => _tileColors[value] ?? const Color(0xFF3C3A32);

  Color get _textColor => value <= 4 ? const Color(0xFF776E65) : Colors.white;

  double get _fontSize {
    if (value >= 1000) return 20;
    if (value >= 100) return 24;
    return 28;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: value == 0
            ? const SizedBox.shrink()
            : Text(
                '$value',
                style: TextStyle(
                  color: _textColor,
                  fontSize: _fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
