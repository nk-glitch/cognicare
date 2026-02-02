import 'dart:math';
import 'package:flutter/material.dart';

class ConnectFourGame extends StatefulWidget {
  final String playerName;
  final bool vsBot;

  const ConnectFourGame({super.key, required this.playerName, this.vsBot = false});

  @override
  State<ConnectFourGame> createState() => _ConnectFourGameState();
}

class _ConnectFourGameState extends State<ConnectFourGame> {
  static const int rows = 6;
  static const int cols = 7;
  List<List<String>> board = List.generate(rows, (_) => List.filled(cols, ''));
  bool isRedPlayer = true;
  String winner = '';
  bool gameOver = false;
  int redScore = 0;
  int yellowScore = 0;
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildScoreBoard(),
                    const SizedBox(height: 16),
                    _buildCurrentPlayerIndicator(),
                    const SizedBox(height: 16),
                    _buildBoard(),
                    const SizedBox(height: 16),
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
            'Connect Four',
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
    final redLabel = widget.vsBot ? 'You' : 'Red';
    final yellowLabel = widget.vsBot ? 'Bot' : 'Yellow';
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
          _buildScoreItem(redLabel, redScore, Colors.red.shade400),
          Container(
            width: 2,
            height: 40,
            color: const Color(0xFFE8C4C8),
          ),
          _buildScoreItem(yellowLabel, yellowScore, Colors.amber.shade600),
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
          color: Colors.amber.shade600,
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
              : (winner == 'R' ? Colors.red.shade400 : Colors.amber.shade600),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          winner == 'Draw' ? "It's a Draw!" : '${winner == 'R' ? 'Red' : 'Yellow'} Wins! 🎉',
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
        color: isRedPlayer ? Colors.red.shade400 : Colors.amber.shade600,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${isRedPlayer ? "Red" : "Yellow"}\'s Turn',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final cellSize = (maxWidth - 32) / cols;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF8FA9C9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(cols, (col) {
                  return SizedBox(
                    width: cellSize,
                    height: 40,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: (gameOver || _botThinking || (widget.vsBot && !isRedPlayer)) ? null : () => _dropPiece(col),
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: gameOver
                            ? Colors.grey
                            : (isRedPlayer ? Colors.red.shade400 : Colors.amber.shade600),
                        size: 32,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              ...List.generate(rows, (row) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(cols, (col) {
                      return _buildCell(row, col, cellSize);
                    }),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCell(int row, int col, double size) {
    Color cellColor;
    if (board[row][col] == 'R') {
      cellColor = Colors.red.shade400;
    } else if (board[row][col] == 'Y') {
      cellColor = Colors.amber.shade600;
    } else {
      cellColor = Colors.white;
    }

    return Container(
      width: size - 8,
      height: size - 8,
      decoration: BoxDecoration(
        color: cellColor,
        shape: BoxShape.circle,
        boxShadow: board[row][col] != ''
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
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

  void _dropPiece(int col) {
    if (gameOver || _botThinking) return;

    for (int row = rows - 1; row >= 0; row--) {
      if (board[row][col] == '') {
        setState(() {
          board[row][col] = isRedPlayer ? 'R' : 'Y';
          _checkWinner(row, col);
          if (!gameOver) {
            isRedPlayer = !isRedPlayer;
          }
        });
        if (widget.vsBot && !gameOver && !isRedPlayer) {
          _scheduleBotDrop();
        }
        return;
      }
    }
  }

  void _scheduleBotDrop() {
    setState(() => _botThinking = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted || gameOver) {
        if (mounted) setState(() => _botThinking = false);
        return;
      }
      final col = _getBotColumn();
      if (col != null) {
        for (int row = rows - 1; row >= 0; row--) {
          if (board[row][col] == '') {
            setState(() {
              board[row][col] = 'Y';
              _checkWinner(row, col);
              if (!gameOver) isRedPlayer = true;
              _botThinking = false;
            });
            return;
          }
        }
      }
      setState(() => _botThinking = false);
    });
  }

  int? _getBotColumn() {
    final validCols = <int>[];
    for (int c = 0; c < cols; c++) {
      if (board[0][c] == '') validCols.add(c);
    }
    if (validCols.isEmpty) return null;

    for (int c in validCols) {
      final r = _getDropRow(c);
      if (r != null && _wouldWin(r, c, 'Y')) return c;
    }
    for (int c in validCols) {
      final r = _getDropRow(c);
      if (r != null && _wouldWin(r, c, 'R')) return c;
    }
    final centerOrder = [3, 2, 4, 1, 5, 0, 6];
    for (int c in centerOrder) {
      if (validCols.contains(c)) return c;
    }
    return validCols[Random().nextInt(validCols.length)];
  }

  int? _getDropRow(int col) {
    for (int r = rows - 1; r >= 0; r--) {
      if (board[r][col] == '') return r;
    }
    return null;
  }

  bool _wouldWin(int row, int col, String player) {
    final boardCopy = board.map((r) => r.toList()).toList();
    boardCopy[row][col] = player;
    return _countInDirection(row, col, 0, 1, player, boardCopy) >= 4 ||
        _countInDirection(row, col, 1, 0, player, boardCopy) >= 4 ||
        _countInDirection(row, col, 1, 1, player, boardCopy) >= 4 ||
        _countInDirection(row, col, 1, -1, player, boardCopy) >= 4;
  }

  int _countInDirection(int row, int col, int dRow, int dCol, String player, List<List<String>> b) {
    int count = 1;
    int r = row + dRow, c = col + dCol;
    while (r >= 0 && r < rows && c >= 0 && c < cols && b[r][c] == player) {
      count++;
      r += dRow;
      c += dCol;
    }
    r = row - dRow;
    c = col - dCol;
    while (r >= 0 && r < rows && c >= 0 && c < cols && b[r][c] == player) {
      count++;
    r -= dRow;
    c -= dCol;
    }
    return count;
  }

  void _checkWinner(int row, int col) {
    String player = board[row][col];

    if (_checkDirection(row, col, 0, 1, player) ||
        _checkDirection(row, col, 1, 0, player) ||
        _checkDirection(row, col, 1, 1, player) ||
        _checkDirection(row, col, 1, -1, player)) {
      setState(() {
        winner = player;
        gameOver = true;
        if (winner == 'R') {
          redScore++;
        } else {
          yellowScore++;
        }
      });
      return;
    }

    bool isFull = true;
    for (var row in board) {
      if (row.contains('')) {
        isFull = false;
        break;
      }
    }

    if (isFull) {
      setState(() {
        winner = 'Draw';
        gameOver = true;
      });
    }
  }

  bool _checkDirection(int row, int col, int dRow, int dCol, String player) {
    int count = 1;

    int r = row + dRow;
    int c = col + dCol;
    while (r >= 0 && r < rows && c >= 0 && c < cols && board[r][c] == player) {
      count++;
      r += dRow;
      c += dCol;
    }

    r = row - dRow;
    c = col - dCol;
    while (r >= 0 && r < rows && c >= 0 && c < cols && board[r][c] == player) {
      count++;
      r -= dRow;
      c -= dCol;
    }

    return count >= 4;
  }

  void _resetGame() {
    setState(() {
      board = List.generate(rows, (_) => List.filled(cols, ''));
      isRedPlayer = true;
      winner = '';
      gameOver = false;
      _botThinking = false;
    });
  }
}
