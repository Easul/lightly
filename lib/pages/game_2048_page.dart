import 'package:flutter/material.dart';
import '../game_2048/game_2048_engine.dart';
import '../game_2048/game_2048_widgets.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('2048'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ScoreCard(score: _engine.score),
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
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                GameBoard(board: _engine.board, onMove: _handleMove),
                const SizedBox(height: 24),
                if (_engine.isGameOver) const GameOverBanner(),
                const SizedBox(height: 16),
                const Text(
                  'Swipe to move tiles',
                  style: TextStyle(color: Color(0xFF776E65), fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
