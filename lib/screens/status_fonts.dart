import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const statusFontNames = ['Classic', 'Serif', 'Bold', 'Script', 'Hand', 'Mono'];

/// Text status ka style. idx firestore mein 'fontIdx' ke taur par save hota hai.
TextStyle statusFontStyle(
    int idx, {
      required double size,
      Color color = Colors.white,
    }) {
  final base = TextStyle(color: color, fontSize: size, height: 1.3);
  switch (idx) {
    case 1:
      return GoogleFonts.playfairDisplay(
          textStyle: base, fontWeight: FontWeight.w700);
    case 2:
      return GoogleFonts.oswald(textStyle: base, fontWeight: FontWeight.w700);
    case 3:
      return GoogleFonts.pacifico(textStyle: base);
    case 4:
      return GoogleFonts.caveat(
          textStyle: base.copyWith(fontSize: size * 1.2),
          fontWeight: FontWeight.w700);
    case 5:
      return GoogleFonts.courierPrime(
          textStyle: base, fontWeight: FontWeight.w700);
    default:
      return base.copyWith(fontWeight: FontWeight.w700);
  }
}