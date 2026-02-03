import 'package:flutter/material.dart';
import 'games/tic_tac_toe_game.dart';
import 'games/checkers_game.dart';
import 'games/connect_four_game.dart';
import 'games/uno_game.dart';

class GamesHubPage extends StatefulWidget {
  final String playerName;
  final bool isCaretaker;

  const GamesHubPage({
    Key? key,
    required this.playerName,
    this.isCaretaker = false,
  }) : super(key: key);

  @override
  State<GamesHubPage> createState() => _GamesHubPageState();
}

class _GamesHubPageState extends State<GamesHubPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeSection(),
                    const SizedBox(height: 24),
                    const Text(
                      'Choose a Game',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3D2C31),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildGamesGrid(),
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
            'Games Hub',
            style: TextStyle(
              fontSize: 20,
              color: Color(0xFF3D2C31),
              fontWeight: FontWeight.bold,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.games,
              color: Color(0xFF8FA9C9),
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF8FA9C9).withOpacity(0.3),
            const Color(0xFFD47A8A).withOpacity(0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE8C4C8),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.gamepad,
              size: 32,
              color: Color(0xFF8FA9C9),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${widget.playerName}!',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3D2C31),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Play games and stay connected',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF5A4046),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGamesGrid() {
    final games = [
      GameInfo(
        name: 'Tic Tac Toe',
        icon: Icons.grid_3x3,
        color: const Color(0xFF8FA9C9),
        difficulty: 'Easy',
        players: '2 Players',
        onTap: () => _navigateToGame(
          context,
          TicTacToeGame(playerName: widget.playerName),
        ),
      ),
      GameInfo(
        name: 'Connect Four',
        icon: Icons.grid_4x4,
        color: const Color(0xFFFFB347),
        difficulty: 'Easy',
        players: '2 Players',
        onTap: () => _navigateToGame(
          context,
          ConnectFourGame(playerName: widget.playerName),
        ),
      ),
      GameInfo(
        name: 'Checkers',
        icon: Icons.casino,
        color: const Color(0xFFD47A8A),
        difficulty: 'Medium',
        players: '2 Players',
        onTap: () => _navigateToGame(
          context,
          CheckersGame(playerName: widget.playerName),
        ),
      ),
      GameInfo(
        name: 'Uno Cards',
        icon: Icons.style,
        color: const Color(0xFF9B59B6),
        difficulty: 'Medium',
        players: '2-4 Players',
        onTap: () => _navigateToGame(
          context,
          UnoGame(playerName: widget.playerName),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.90,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: games.length,
      itemBuilder: (context, index) {
        return _buildGameCard(games[index], index);
      },
    );
  }

  Widget _buildGameCard(GameInfo game, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 100)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: game.color.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: game.onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: game.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      game.icon,
                      size: 40,
                      color: game.color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    game.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3D2C31),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: game.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      game.difficulty,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: game.color,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    game.players,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A6A70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToGame(BuildContext context, Widget game) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => game),
    );
  }
}

class GameInfo {
  final String name;
  final IconData icon;
  final Color color;
  final String difficulty;
  final String players;
  final VoidCallback onTap;

  GameInfo({
    required this.name,
    required this.icon,
    required this.color,
    required this.difficulty,
    required this.players,
    required this.onTap,
  });
}