import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 220});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/logo.png',
      width: width,
      semanticLabel: 'Bravura logo',
    );
  }
}
