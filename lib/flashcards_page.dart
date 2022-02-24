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

  List<Review> reviews = [];

  @override
  void initState() {
    super.initState();
  }

  void completeCard(DRCard card,
      {Rating rating = Rating.Easy, DateTime? when}) {
    DateTime ts;
    if (when != null) {
      ts = when;
    } else {
      ts = DateTime.now();
    }
    Review review;
    switch (revisionStrategy) {
      case RevisionStrategy.Random:
        review = Review(
            master: card.master!,
            combination: card.combination!,
            ts: ts,
            rating: rating);
        break;
      case RevisionStrategy.SpacedRepetition:
        throw "todo";
    }
    dolphin.addReviews([review]);
    reviews.add(review);
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> blah = [];
    while (true) {
      print("Cards remaining: ${dolphin.summary().learning ?? 0}");
      var c = dolphin.nextCard();
      if (c == null) {
        break;
      }
      blah.add(Text("$c"));
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
