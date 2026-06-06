import 'package:flutter/material.dart';

/// Deterministic per-category colours so each playlist category gets its own
/// recognisable colour across the Channels grid and the Guide.
const _palette = <List<Color>>[
  [Color(0xFF1565C0), Color(0xFF42A5F5)], // blue
  [Color(0xFF6A1B9A), Color(0xFFAB47BC)], // purple
  [Color(0xFF2E7D32), Color(0xFF66BB6A)], // green
  [Color(0xFFC62828), Color(0xFFEF5350)], // red
  [Color(0xFFEF6C00), Color(0xFFFFA726)], // orange
  [Color(0xFF00838F), Color(0xFF26C6DA)], // teal
  [Color(0xFFAD1457), Color(0xFFEC407A)], // pink
  [Color(0xFF4527A0), Color(0xFF7E57C2)], // deep purple
  [Color(0xFF00695C), Color(0xFF26A69A)], // dark teal
  [Color(0xFF558B2F), Color(0xFF9CCC65)], // lime green
  [Color(0xFF283593), Color(0xFF5C6BC0)], // indigo
  [Color(0xFFD84315), Color(0xFFFF7043)], // deep orange
];

int _index(String name) => name.hashCode.abs() % _palette.length;

/// A stable gradient for a category, derived from its name.
LinearGradient categoryGradient(String name) {
  final c = _palette[_index(name)];
  return LinearGradient(
    colors: c,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// A stable solid colour for a category (e.g. Guide header).
Color categoryColor(String name) => _palette[_index(name)][0];
