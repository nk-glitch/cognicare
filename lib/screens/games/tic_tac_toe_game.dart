import 'dart:math';
import 'package:flutter/material.dart';

class TicTacToeGame extends StatefulWidget {
  final String playerName;
  final bool vsBot;

  const TicTacToeGame({super.key, required this.playerName, this.vsBot = false});

  @override
  State<TicTacToeGame> createState() => _TicTacToeGameState();
}

class _TicTacToeGameState extends State<TicTacToeGame> {
  List<String> board = List.filled(9, '');
  bool isPlayerX = true;
  String winner = '';
  bool gameOver = false;
  int playerXScore = 0;
  int playerOScore = 0;
  bool _botThinking = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5E6E8),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildScoreBoard(),
                    const SizedBox(height: 24),
                    _buildCurrentPlayerIndicator(),
                    const SizedBox(height: 24),
                    _buildBoard(),
                    const SizedBox(height: 24),
                    _buildResetButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Color(0xFF3D2C31)),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.5),
              padding: const EdgeInsets.all(8),
            ),
          ),
          const Text(
            'Tic Tac Toe',
            style: TextStyle(
              fontSize: 20,
              color: Color(0xFF3D2C31),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildScoreBoard() {
    final xLabel = widget.vsBot ? 'You' : 'Player X';
    final oLabel = widget.vsBot ? 'Bot' : 'Player O';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildScoreItem(xLabel, playerXScore, const Color(0xFF8FA9C9)),
          Container(
            width: 2,
            height: 40,
            color: const Color(0xFFE8C4C8),
          ),
          _buildScoreItem(oLabel, playerOScore, const Color(0xFFD47A8A)),
        ],
      ),
    );
  }

  Widget _buildScoreItem(String label, int score, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          score.toString(),
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentPlayerIndicator() {
    if (_botThinking) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFD47A8A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Bot is thinking...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
    if (gameOver) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: winner == 'Draw'
              ? Colors.grey.shade300
              : (winner == 'X' ? const Color(0xFF8FA9C9) : const Color(0xFFD47A8A)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          winner == 'Draw' ? "It's a Draw!" : 'Player $winner Wins! 🎉',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: isPlayerX ? const Color(0xFF8FA9C9) : const Color(0xFFD47A8A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Player ${isPlayerX ? "X" : "O"}\'s Turn',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildBoard() {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFE8C4C8),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: 9,
          itemBuilder: (context, index) {
            return _buildCell(index);
          },
        ),
      ),
    );
  }

  Widget _buildCell(int index) {
    final isHumanTurn = widget.vsBot ? isPlayerX : true;
    return GestureDetector(
      onTap: (_botThinking || !isHumanTurn || gameOver) ? null : () => _makeMove(index),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            board[index],
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: board[index] == 'X'
                  ? const Color(0xFF8FA9C9)
                  : const Color(0xFFD47A8A),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return ElevatedButton(
      onPressed: _resetGame,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF8FA9C9),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 4,
      ),
      child: const Text(
        'New Game',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _makeMove(int index) {
    if (board[index] == '' && !gameOver && !_botThinking) {
      setState(() {
        board[index] = isPlayerX ? 'X' : 'O';
        isPlayerX = !isPlayerX;
        _checkWinner();
      });
      if (widget.vsBot && !gameOver && !isPlayerX) {
        _scheduleBotMove();
      }
    }
  }

  void _scheduleBotMove() {
    setState(() => _botThinking = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted || gameOver) return;
      final move = _getBotMove();
      if (move != null) {
        setState(() {
          board[move] = 'O';
          isPlayerX = true;
          _botThinking = false;
          _checkWinner();
        });
      } else {
        setState(() => _botThinking = false);
      }
    });
  }

  int? _getBotMove() {
    const winPatterns = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8],
      [0, 3, 6], [1, 4, 7], [2, 5, 8],
      [0, 4, 8], [2, 4, 6],
    ];
    final empty = <int>[];
    for (int i = 0; i < 9; i++) if (board[i] == '') empty.add(i);
    if (empty.isEmpty) return null;

    for (var p in winPatterns) {
      int oCount = 0, emptyIdx = -1;
      for (var i in p) {
        if (board[i] == 'O') oCount++;
        else if (board[i] == '') emptyIdx = i;
      }
      if (oCount == 2 && emptyIdx >= 0) return emptyIdx;
    }
    for (var p in winPatterns) {
      int xCount = 0, emptyIdx = -1;
      for (var i in p) {
        if (board[i] == 'X') xCount++;
        else if (board[i] == '') emptyIdx = i;
      }
      if (xCount == 2 && emptyIdx >= 0) return emptyIdx;
    }
    if (board[4] == '') return 4;
    const corners = [0, 2, 6, 8];
    final cornerEmpty = corners.where((i) => board[i] == '').toList();
    if (cornerEmpty.isNotEmpty) return cornerEmpty[Random().nextInt(cornerEmpty.length)];
    return empty[Random().nextInt(empty.length)];
  }

  void _checkWinner() {
    const winPatterns = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8],
      [0, 3, 6], [1, 4, 7], [2, 5, 8],
      [0, 4, 8], [2, 4, 6],
    ];

    for (var pattern in winPatterns) {
      if (board[pattern[0]] != '' &&
          board[pattern[0]] == board[pattern[1]] &&
          board[pattern[1]] == board[pattern[2]]) {
        setState(() {
          winner = board[pattern[0]];
          gameOver = true;
          if (winner == 'X') {
            playerXScore++;
          } else {
            playerOScore++;
          }
        });
        return;
      }
    }

    if (!board.contains('')) {
      setState(() {
        winner = 'Draw';
        gameOver = true;
      });
    }
  }

  void _resetGame() {
    setState(() {
      board = List.filled(9, '');
      isPlayerX = true;
      winner = '';
      gameOver = false;
      _botThinking = false;
    });
  }
}
