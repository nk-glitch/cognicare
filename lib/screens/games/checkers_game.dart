import 'package:flutter/material.dart';

class CheckersGame extends StatefulWidget {
  final String playerName;
  final bool vsBot;

  const CheckersGame({
    Key? key,
    required this.playerName,
    this.vsBot = false,
  }) : super(key: key);

  @override
  State<CheckersGame> createState() => _CheckersGameState();
}

class _CheckersGameState extends State<CheckersGame> {
  static const int boardSize = 8;
  List<List<String>> board = List.generate(boardSize, (_) => List.filled(boardSize, ''));
  bool isRedPlayer = true;
  int? selectedRow;
  int? selectedCol;
  String winner = '';
  bool gameOver = false;
  int redScore = 0;
  int blackScore = 0;
  List<List<int>> validMoves = [];

  @override
  void initState() {
    super.initState();
    _initializeBoard();
  }

  void _initializeBoard() {
    // Place red pieces (top 3 rows)
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < boardSize; col++) {
        if ((row + col) % 2 == 1) {
          board[row][col] = 'R';
        }
      }
    }

    // Place black pieces (bottom 3 rows)
    for (int row = 5; row < boardSize; row++) {
      for (int col = 0; col < boardSize; col++) {
        if ((row + col) % 2 == 1) {
          board[row][col] = 'B';
        }
      }
    }
  }

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
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _buildScoreBoard(),
                    const SizedBox(height: 12),
                    _buildCurrentPlayerIndicator(),
                    const SizedBox(height: 12),
                    _buildBoard(),
                    const SizedBox(height: 12),
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
            'Checkers',
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
          _buildScoreItem('Red', redScore, Colors.red.shade400),
          Container(
            width: 2,
            height: 40,
            color: const Color(0xFFE8C4C8),
          ),
          _buildScoreItem('Black', blackScore, Colors.grey.shade800),
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
    if (gameOver) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: winner == 'R' ? Colors.red.shade400 : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '${winner == 'R' ? 'Red' : 'Black'} Wins! 🎉',
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
        color: isRedPlayer ? Colors.red.shade400 : Colors.grey.shade800,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${isRedPlayer ? "Red" : "Black"}\'s Turn - Tap a piece',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildBoard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;
        final cellSize = size / boardSize;

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: boardSize,
              ),
              itemCount: boardSize * boardSize,
              itemBuilder: (context, index) {
                int row = index ~/ boardSize;
                int col = index % boardSize;
                return _buildCell(row, col, cellSize);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildCell(int row, int col, double cellSize) {
    bool isDark = (row + col) % 2 == 1;
    bool isSelected = selectedRow == row && selectedCol == col;
    bool isValidMove = validMoves.any((move) => move[0] == row && move[1] == col);
    String piece = board[row][col];

    return GestureDetector(
      onTap: () => _handleTap(row, col),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? (isSelected ? const Color(0xFFFFD700) : const Color(0xFF8B4513))
              : const Color(0xFFFFF8DC),
          border: isSelected
              ? Border.all(color: Colors.yellow, width: 3)
              : null,
        ),
        child: Stack(
          children: [
            if (isValidMove)
              Center(
                child: Container(
                  width: cellSize * 0.3,
                  height: cellSize * 0.3,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            if (piece != '')
              Center(child: _buildPiece(piece, cellSize)),
          ],
        ),
      ),
    );
  }

  Widget _buildPiece(String piece, double cellSize) {
    Color color;
    if (piece == 'R' || piece == 'RK') {
      color = Colors.red.shade400;
    } else {
      color = Colors.grey.shade800;
    }

    bool isKing = piece.endsWith('K');

    return Container(
      width: cellSize * 0.7,
      height: cellSize * 0.7,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isKing
          ? Icon(Icons.star, color: Colors.white, size: cellSize * 0.4)
          : null,
    );
  }

  Widget _buildResetButton() {
    return ElevatedButton(
      onPressed: _resetGame,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFD47A8A),
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

  void _handleTap(int row, int col) {
    if (gameOver) return;

    String piece = board[row][col];
    String currentPlayer = isRedPlayer ? 'R' : 'B';

    // If this is a valid move destination
    if (validMoves.any((move) => move[0] == row && move[1] == col)) {
      _makeMove(row, col);
      return;
    }

    // If selecting a piece
    if (piece.startsWith(currentPlayer)) {
      setState(() {
        selectedRow = row;
        selectedCol = col;
        validMoves = _getValidMoves(row, col);
      });
    } else {
      setState(() {
        selectedRow = null;
        selectedCol = null;
        validMoves = [];
      });
    }
  }

  List<List<int>> _getValidMoves(int row, int col) {
    List<List<int>> moves = [];
    String piece = board[row][col];

    // Regular moves
    List<List<int>> directions = [];
    if (piece.endsWith('K')) {
      directions = [[-1, -1], [-1, 1], [1, -1], [1, 1]]; // Kings move all directions
    } else if (piece.startsWith('R')) {
      directions = [[1, -1], [1, 1]]; // Red moves down
    } else {
      directions = [[-1, -1], [-1, 1]]; // Black moves up
    }

    for (var dir in directions) {
      int newRow = row + dir[0];
      int newCol = col + dir[1];

      // Regular move
      if (_isValidPosition(newRow, newCol) && board[newRow][newCol] == '') {
        moves.add([newRow, newCol]);
      }

      // Jump move
      int jumpRow = row + (dir[0] * 2);
      int jumpCol = col + (dir[1] * 2);
      int midRow = row + dir[0];
      int midCol = col + dir[1];

      if (_isValidPosition(jumpRow, jumpCol) &&
          board[jumpRow][jumpCol] == '' &&
          _isValidPosition(midRow, midCol) &&
          board[midRow][midCol] != '' &&
          !board[midRow][midCol].startsWith(piece[0])) {
        moves.add([jumpRow, jumpCol]);
      }
    }

    return moves;
  }

  bool _isValidPosition(int row, int col) {
    return row >= 0 && row < boardSize && col >= 0 && col < boardSize;
  }

  void _makeMove(int toRow, int toCol) {
    if (selectedRow == null || selectedCol == null) return;

    setState(() {
      String movingPiece = board[selectedRow!][selectedCol!];
      board[toRow][toCol] = movingPiece;
      board[selectedRow!][selectedCol!] = '';

      // Check for king promotion
      if ((toRow == 0 && movingPiece == 'B') ||
          (toRow == boardSize - 1 && movingPiece == 'R')) {
        board[toRow][toCol] = '${movingPiece}K';
      }

      // Check for capture
      if ((toRow - selectedRow!).abs() == 2) {
        int jumpRow = (toRow + selectedRow!) ~/ 2;
        int jumpCol = (toCol + selectedCol!) ~/ 2;
        board[jumpRow][jumpCol] = '';
      }

      selectedRow = null;
      selectedCol = null;
      validMoves = [];
      isRedPlayer = !isRedPlayer;
      _checkGameOver();

      // Bot's turn if vsBot mode
      if (widget.vsBot && !isRedPlayer && !gameOver) {
        Future.delayed(const Duration(milliseconds: 800), _botMove);
      }
    });
  }

  void _botMove() {
    if (gameOver) return;

    // Simple AI: find all black pieces and their valid moves
    for (int row = 0; row < boardSize; row++) {
      for (int col = 0; col < boardSize; col++) {
        if (board[row][col].startsWith('B')) {
          var moves = _getValidMoves(row, col);
          if (moves.isNotEmpty) {
            setState(() {
              selectedRow = row;
              selectedCol = col;
              validMoves = moves;
            });
            var move = moves[DateTime.now().millisecond % moves.length];
            _makeMove(move[0], move[1]);
            return;
          }
        }
      }
    }
  }

  void _checkGameOver() {
    int redPieces = 0;
    int blackPieces = 0;

    for (var row in board) {
      for (var cell in row) {
        if (cell.startsWith('R')) redPieces++;
        if (cell.startsWith('B')) blackPieces++;
      }
    }

    if (redPieces == 0) {
      setState(() {
        winner = 'B';
        gameOver = true;
        blackScore++;
      });
    } else if (blackPieces == 0) {
      setState(() {
        winner = 'R';
        gameOver = true;
        redScore++;
      });
    }
  }

  void _resetGame() {
    setState(() {
      board = List.generate(boardSize, (_) => List.filled(boardSize, ''));
      _initializeBoard();
      isRedPlayer = true;
      selectedRow = null;
      selectedCol = null;
      validMoves = [];
      winner = '';
      gameOver = false;
    });
  }
}