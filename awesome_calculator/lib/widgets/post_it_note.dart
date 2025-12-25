import 'package:flutter/material.dart';

class PostItNote extends StatelessWidget {
  const PostItNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.08,
      child: Stack(
        children: [
          // Main post-it body
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFF88),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 3,
                  offset: const Offset(1.5, 1.5),
                ),
              ],
            ),
          ),
          // Folded corner
          Positioned(
            top: 0,
            left: 0,
            child: ClipPath(
              clipper: _TriangleClipper(),
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [const Color(0xFFDDDD77), const Color(0xFFEEEE80)],
                  ),
                ),
              ),
            ),
          ),
          // Post-it content
          SizedBox(
            width: 64,
            height: 64,
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TODO:',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 7.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.black.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '- Fix bug\n- Add tests\n- Coffee!!!',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 6.75,
                      color: Colors.black.withValues(alpha: 0.65),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom clipper for post-it note folded corner
class _TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
