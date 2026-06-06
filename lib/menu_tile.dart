import 'package:flutter/material.dart';

class MenuTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final LinearGradient color;
  final VoidCallback onTap;
  final bool autofocus;
  // Optional category icon image (assets/categories/*.png). When set, it is
  // shown instead of [icon].
  final String? imageAsset;

  const MenuTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.autofocus = false,
    this.imageAsset,
  });

  @override
  State<MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<MenuTile> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool isActive = _isFocused || _isHovered;
    final double scale = isActive ? 1.1 : 1.0;
    final Color borderColor = isActive ? Colors.white : Colors.transparent;
    final double shadowOpacity = isActive ? 0.5 : 0.2;

    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scale(scale),
        transformAlignment: Alignment.center,
        width: 200,
        height: 150,
        decoration: BoxDecoration(
          gradient: widget.color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: shadowOpacity),
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            autofocus: widget.autofocus,
            onTap: widget.onTap,
            onFocusChange: (value) => setState(() => _isFocused = value),
            onHover: (value) => setState(() => _isHovered = value),
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.imageAsset != null)
                  Image.asset(
                    widget.imageAsset!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) =>
                        Icon(widget.icon, color: Colors.white, size: 50),
                  )
                else
                  Icon(widget.icon, color: Colors.white, size: 50),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    widget.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      // Smaller, bounded label for image (category) tiles so long
                      // names don't overflow the tile.
                      fontSize: widget.imageAsset != null
                          ? Theme.of(context).textTheme.titleMedium?.fontSize
                          : Theme.of(context).textTheme.headlineSmall?.fontSize,
                      fontWeight: FontWeight.w600,
                      shadows: const [
                        Shadow(
                          color: Colors.black45,
                          offset: Offset(0, 2),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
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
