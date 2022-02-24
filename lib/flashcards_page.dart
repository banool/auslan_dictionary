import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';

import 'types.dart';

class FlashcardsPage extends StatefulWidget {
  FlashcardsPage(
      {Key? key, required this.dolphin, required this.revisionStrategy});

  final DolphinSR dolphin;
  final RevisionStrategy revisionStrategy;

  @override
  _FlashcardsPageState createState() =>
      _FlashcardsPageState(this.dolphin, this.revisionStrategy);
}

class _FlashcardsPageState extends State<FlashcardsPage> {
  _FlashcardsPageState(this.dolphin, this.revisionStrategy);

  DolphinSR dolphin;
  final RevisionStrategy revisionStrategy;

  @override
  void initState() {
    super.initState();
  }

  void completeCard(DRCard card) {
    switch (revisionStrategy) {
      case RevisionStrategy.Random:
        dolphin.removeFromMaster(card.master!);
        break;
      case RevisionStrategy.SpacedRepetition:
        throw "todo";
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> blah = [];
    while (true) {
      var c = dolphin.nextCard();
      print("$c");
      if (c == null) {
        break;
      }
      blah.add(Text("$c"));
      dolphin.removeFromMaster(c.master!);
    }
    return Scaffold(
        appBar: AppBar(
          title: Text("hey"),
        ),
        body: Center(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: blah,
        )));
  }
}
