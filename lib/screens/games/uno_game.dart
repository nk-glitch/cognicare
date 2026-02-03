import 'package:flutter/material.dart';
import 'dart:math';

class UnoGame extends StatefulWidget {
  final String playerName;

  const UnoGame({Key? key, required this.playerName}) : super(key: key);

  @override
  State<UnoGame> createState() => _UnoGameState();
}

class _UnoGameState extends State<UnoGame> {
  List<UnoCard> deck = [];
  List<UnoCard> playerHand = [];
  List<UnoCard> aiHand = [];
  UnoCard? currentCard;
  bool isPlayerTurn = true;
  String winner = '';
  bool gameOver = false;
  int playerScore = 0;
  int aiScore = 0;
  String message = '';

  @override
  void initState() {
    super.initState();
    _initializeGame();
  }

  void _initializeGame() {
    _createDeck();
    _shuffleDeck();

    // Deal cards
    for (int i = 0; i < 7; i++) {
      playerHand.add(deck.removeLast());
      aiHand.add(deck.removeLast());
    }

    // Set first card
    currentCard = deck.removeLast();

    setState(() {
      message = "Match the color or number!";
    });
  }

  void _createDeck() {
    const colors = [Colors.red, Colors.blue, Colors.green, Colors.yellow];
    const values = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

    // Create number cards
    for (var color in colors) {
      for (var value in values) {
        deck.add(UnoCard(color: color, value: value));
        if (value != '0') {
          deck.add(UnoCard(color: color, value: value));
        }
      }
    }

    // Add some special cards
    for (var color in colors) {
      deck.add(UnoCard(color: color, value: 'Skip', isSpecial: true));
      deck.add(UnoCard(color: color, value: '+2', isSpecial: true));
    }
  }

  void _shuffleDeck() {
    deck.shuffle(Random());
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      _buildScoreBoard(),
                      const SizedBox(height: 16),
                      _buildMessageBanner(),
                      const SizedBox(height: 20),
                      _buildAIHand(),
                      const SizedBox(height: 24),
                      _buildCurrentCard(),
                      const SizedBox(height: 20),
                      if (isPlayerTurn && !gameOver) _buildDrawButton(),
                      const SizedBox(height: 20),
                      _buildPlayerHand(),
                      const SizedBox(height: 16),
                    ],
                  ),
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
            'Uno Cards',
            style: TextStyle(
              fontSize: 20,
              color: Color(0xFF3D2C31),
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            onPressed: _resetGame,
            icon: const Icon(Icons.refresh, color: Color(0xFF3D2C31)),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.5),
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBoard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildScoreItem('You', playerScore, const Color(0xFF8FA9C9)),
            Container(width: 2, height: 30, color: const Color(0xFFE8C4C8)),
            _buildScoreItem('AI', aiScore, const Color(0xFFD47A8A)),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreItem(String label, int score, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          score.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBanner() {
    if (gameOver) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: winner == 'player'
              ? const Color(0xFF8FA9C9)
              : const Color(0xFFD47A8A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          winner == 'player' ? 'You Win! 🎉' : 'AI Wins!',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isPlayerTurn
            ? const Color(0xFF8FA9C9)
            : const Color(0xFFD47A8A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        isPlayerTurn ? 'Your Turn - Tap a card or draw' : 'AI\'s Turn',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildAIHand() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'AI Hand: ',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF7A6A70),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${aiHand.length} cards',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFFD47A8A),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: aiHand.length,
              itemBuilder: (context, index) {
                return Container(
                  width: 45,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8FA9C9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Center(
                    child: Icon(Icons.question_mark, color: Colors.white, size: 20),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentCard() {
    if (currentCard == null) return const SizedBox();

    return Column(
      children: [
        const Text(
          'Current Card',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF7A6A70),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _buildCardWidget(currentCard!, isLarge: true),
      ],
    );
  }

  Widget _buildDrawButton() {
    return ElevatedButton.icon(
      onPressed: _drawCard,
      icon: const Icon(Icons.add_card),
      label: const Text('Draw Card'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF8FA9C9),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 4,
      ),
    );
  }

  Widget _buildPlayerHand() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Your Hand: ',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF7A6A70),
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${playerHand.length} cards',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF8FA9C9),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: playerHand.isEmpty
              ? const Center(
            child: Text(
              'No cards!',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF7A6A70),
                fontStyle: FontStyle.italic,
              ),
            ),
          )
              : ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: playerHand.length,
            itemBuilder: (context, index) {
              final canPlay = _canPlayCard(playerHand[index]);
              return GestureDetector(
                onTap: isPlayerTurn && !gameOver && canPlay
                    ? () => _playCard(index)
                    : null,
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: canPlay && isPlayerTurn && !gameOver
                        ? Border.all(color: Colors.green, width: 3)
                        : null,
                  ),
                  child: Opacity(
                    opacity: (!canPlay || !isPlayerTurn || gameOver) ? 0.5 : 1.0,
                    child: _buildCardWidget(playerHand[index]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCardWidget(UnoCard card, {bool isLarge = false}) {
    return Container(
      width: isLarge ? 80 : 60,
      height: isLarge ? 120 : 90,
      decoration: BoxDecoration(
        color: card.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          card.value,
          style: TextStyle(
            fontSize: isLarge ? 28 : 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  void _drawCard() {
    if (!isPlayerTurn || gameOver || deck.isEmpty) return;

    setState(() {
      playerHand.add(deck.removeLast());
      message = 'Drew a card!';
      isPlayerTurn = false;
      Future.delayed(const Duration(milliseconds: 500), _aiTurn);
    });
  }

  void _playCard(int index) {
    UnoCard card = playerHand[index];

    if (_canPlayCard(card)) {
      setState(() {
        currentCard = card;
        playerHand.removeAt(index);

        // Handle +2 card
        if (card.value == '+2') {
          message = 'AI draws 2 cards!';
          // Make AI draw 2 cards
          if (deck.length >= 2) {
            aiHand.add(deck.removeLast());
            aiHand.add(deck.removeLast());
          } else if (deck.length == 1) {
            aiHand.add(deck.removeLast());
            _reshuffleDeck();
            if (deck.isNotEmpty) aiHand.add(deck.removeLast());
          } else {
            _reshuffleDeck();
            if (deck.length >= 2) {
              aiHand.add(deck.removeLast());
              aiHand.add(deck.removeLast());
            }
          }
        } else {
          message = 'Good move!';
        }

        if (playerHand.isEmpty) {
          _endGame('player');
        } else {
          isPlayerTurn = false;
          Future.delayed(const Duration(milliseconds: 800), _aiTurn);
        }
      });
    }
  }

  bool _canPlayCard(UnoCard card) {
    if (currentCard == null) return false;
    return card.color == currentCard!.color ||
        card.value == currentCard!.value;
  }

  void _aiTurn() {
    if (gameOver) return;

    List<int> playableIndices = [];
    for (int i = 0; i < aiHand.length; i++) {
      if (_canPlayCard(aiHand[i])) {
        playableIndices.add(i);
      }
    }

    if (playableIndices.isNotEmpty) {
      int index = playableIndices[Random().nextInt(playableIndices.length)];
      UnoCard playedCard = aiHand[index];

      setState(() {
        currentCard = playedCard;
        aiHand.removeAt(index);

        // Handle +2 card
        if (playedCard.value == '+2') {
          message = 'AI played +2! You draw 2 cards';
          // Make player draw 2 cards
          if (deck.length >= 2) {
            playerHand.add(deck.removeLast());
            playerHand.add(deck.removeLast());
          } else if (deck.length == 1) {
            playerHand.add(deck.removeLast());
            _reshuffleDeck();
            if (deck.isNotEmpty) playerHand.add(deck.removeLast());
          } else {
            _reshuffleDeck();
            if (deck.length >= 2) {
              playerHand.add(deck.removeLast());
              playerHand.add(deck.removeLast());
            }
          }
        } else {
          message = 'Your turn!';
        }

        if (aiHand.isEmpty) {
          _endGame('ai');
        } else {
          isPlayerTurn = true;
        }
      });
    } else {
      if (deck.isNotEmpty) {
        setState(() {
          aiHand.add(deck.removeLast());
          isPlayerTurn = true;
          message = 'AI drew a card';
        });
      } else {
        _reshuffleDeck();
        setState(() {
          aiHand.add(deck.removeLast());
          isPlayerTurn = true;
          message = 'Deck reshuffled!';
        });
      }
    }
  }

  void _reshuffleDeck() {
    const colors = [Colors.red, Colors.blue, Colors.green, Colors.yellow];
    const values = ['1', '2', '3', '4', '5'];

    deck.clear();
    for (var color in colors) {
      for (var value in values) {
        deck.add(UnoCard(color: color, value: value));
      }
    }
    _shuffleDeck();
  }

  void _endGame(String winnerPlayer) {
    setState(() {
      winner = winnerPlayer;
      gameOver = true;
      if (winner == 'player') {
        playerScore++;
      } else {
        aiScore++;
      }
    });
  }

  void _resetGame() {
    setState(() {
      deck = [];
      playerHand = [];
      aiHand = [];
      currentCard = null;
      isPlayerTurn = true;
      winner = '';
      gameOver = false;
      _initializeGame();
    });
  }
}

class UnoCard {
  final Color color;
  final String value;
  final bool isSpecial;

  UnoCard({
    required this.color,
    required this.value,
    this.isSpecial = false,
  });
}