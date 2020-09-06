import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WordPage extends StatelessWidget {
  WordPage({this.word});

  final String word;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(word),
      ),
    );
  }
}
