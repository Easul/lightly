import 'package:flutter/material.dart';
import '../game_2048/game_2048_engine.dart';
import '../widgets/app_drawer.dart';

class Game2048Page extends StatefulWidget {
  const Game2048Page({super.key});

  @override
  State<Game2048Page> createState() => _Game2048PageState();
}

class _Game2048PageState extends State<Game2048Page> {
  late Game2048Engine _engine;

  @override
  void initState() {
    super.initState();
    _engine = Game2048Engine();
  }

  void _newGame() {
    setState(() {
      _engine.newGame();
    });
  }

  void _handleMove(MoveDirection direction) {
    if (_engine.isGameOver) return;
    setState(() {
      _engine.move(direction);
    });
  }

  Color _tileColor(int value) {
    final colors = {
      2: const Color(0xFFEEE4DA),
      4: const Color(0xFFEDE0C8),
      8: const Color(0xFFF2B179),
      16: const Color(0xFFF59563),
      32: const Color(0xFFF67C5F),
      64: const Color(0xFFF65E3B),
      128: const Color(0xFFEDCF72),
      256: const Color(0xFFEDCC61),
      512: const Color(0xFFEDC850),
      1024: const Color(0xFFEDC53F),
      2048: const Color(0xFFEDC22E),
    };
    return colors[value] ?? const Color(0xFF3C3A32);
  }

  Color _tileTextColor(int value) {
    return value <= 4 ? const Color(0xFF776E65) : Colors.white;
  }

  double _tileFontSize(int value) {
    if (value >= 1000) return 20;
    if (value >= 100) return 24;
    return 28;
  }

  Widget _buildTile(int value) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _tileColor(value),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: value == 0
            ? const SizedBox.shrink()
            : Text(
                '$value',
                style: TextStyle(
                  color: _tileTextColor(value),
                  fontSize: _tileFontSize(value),
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildBoard() {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFBBADA0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity == null) return;
            if (details.primaryVelocity! > 150) {
              _handleMove(MoveDirection.right);
            } else if (details.primaryVelocity! < -150) {
              _handleMove(MoveDirection.left);
            }
          },
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity == null) return;
            if (details.primaryVelocity! > 150) {
              _handleMove(MoveDirection.down);
            } else if (details.primaryVelocity! < -150) {
              _handleMove(MoveDirection.up);
            }
          },
          child: GridView.count(
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            children: [
              for (var row = 0; row < 4; row++)
                for (var col = 0; col < 4; col++)
                  _buildTile(_engine.board[row][col]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('2048'),
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
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
                            '${_engine.score}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _newGame,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8F7A66),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                      child: const Text(
                        'New Game',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildBoard(),
                const SizedBox(height: 24),
                if (_engine.isGameOver)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
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
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Swipe to move tiles',
                  style: const TextStyle(
                    color: Color(0xFF776E65),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
