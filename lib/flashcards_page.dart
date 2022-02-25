import 'package:auslan_dictionary/flashcards_logic.dart';
import 'package:auslan_dictionary/word_page.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'types.dart';

class FlashcardsPage extends StatefulWidget {
  FlashcardsPage({Key? key, required this.di, required this.revisionStrategy});

  final DolphinInformation di;
  final RevisionStrategy revisionStrategy;

  @override
  _FlashcardsPageState createState() =>
      _FlashcardsPageState(this.di, this.revisionStrategy);
}

class _FlashcardsPageState extends State<FlashcardsPage> {
  _FlashcardsPageState(this.di, this.revisionStrategy);

  DolphinInformation di;
  final RevisionStrategy revisionStrategy;

  Map<DRCard, Review> answers = Map();

  late int numCardsToReview;

  DRCard? currentCard;
  bool currentCardAnswered = false;

  @override
  void initState() {
    super.initState();
    numCardsToReview = di.dolphin.summary().learning!;
    nextCard();
  }

  void nextCard() {
    setState(() {
      currentCard = di.dolphin.nextCard();
    });
  }

  int getRemainingCardsToReview() {
    return numCardsToReview - answers.values.length;
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
    setState(() {
      di.dolphin.addReviews([review]);
      answers[card] = review;
    });
  }

  Widget buildFlashcardWidget(bool answered) {
    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);

    DRCard card = currentCard!;
    SubWord sw = di.keyToSubWordMap[card.master]!;

    String word;
    bool wordToSign = card.combination! == Combination(front: [0], back: [1]);
    if (wordToSign) {
      // Word on front, video on back.
      word = card.front![0];
    } else {
      word = card.back![0];
    }

    var videoPlayerScreen = VideoPlayerScreen(videoLinks: sw.videoLinks);

    Widget regionalInformationWidget =
        getRegionalInformationWidget(sw, shouldUseHorizontalDisplay);

    if (!shouldUseHorizontalDisplay) {
      List<Widget> children = [];
      children.add(videoPlayerScreen);
      children.add(Divider(
        height: 80,
        thickness: 2,
        indent: 20,
        endIndent: 20,
      ));
      String prompt;
      if (!answered) {
        prompt = "What does this sign mean?";
      } else {
        prompt = word;
      }
      children.add(Text(prompt,
          textAlign: TextAlign.center, style: TextStyle(fontSize: 20)));
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      );
    } else {
      var size = MediaQuery.of(context).size;
      var screenWidth = size.width;
      var screenHeight = size.height;
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            videoPlayerScreen,
            regionalInformationWidget,
          ]),
          new LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
            // TODO Make this less janky and hardcoded.
            // The issue is the parent has infinite width and height
            // and Expanded doesn't seem to be working.
            List<Widget> children = [];
            return ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: screenWidth * 0.4, maxHeight: screenHeight * 0.7),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: children));
          })
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    /*
    List<Widget> blah = [];
    while (true) {
      print("Cards remaining: ${di.dolphin.summary().learning ?? 0}");
      var c = di.dolphin.nextCard();
      if (c == null) {
        break;
      }
      completeCard(c);
      blah.add(Text("$c"));
    }
    */

    Widget body;
    String appBarTitle;
    if (currentCard != null) {
      body = buildFlashcardWidget(currentCardAnswered);
      appBarTitle =
          "${numCardsToReview - getRemainingCardsToReview() + 1} / $numCardsToReview";
    } else {
      body = Text("todo post revision summary page");
      appBarTitle = "todo";
    }

    return Scaffold(
        appBar: AppBar(
            title: Text(appBarTitle),
            leading: IconButton(
              icon: Icon(Icons.close),
              // TODO: Show dialog here to confirm they want to stop revising.
              onPressed: () => Navigator.of(context).pop(),
            )),
        body: Center(
          child: body,
        ));
  }
}
