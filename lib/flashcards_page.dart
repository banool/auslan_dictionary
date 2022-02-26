import 'package:auslan_dictionary/flashcards_logic.dart';
import 'package:auslan_dictionary/word_page.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'types.dart';

class FlashcardsPage extends StatefulWidget {
  FlashcardsPage({
    Key? key,
    required this.di,
    required this.revisionStrategy,
    required this.existingReviews,
  });

  final DolphinInformation di;
  final RevisionStrategy revisionStrategy;
  final List<Review>? existingReviews;

  @override
  _FlashcardsPageState createState() => _FlashcardsPageState(
      this.di, this.revisionStrategy, this.existingReviews);
}

class _FlashcardsPageState extends State<FlashcardsPage> {
  _FlashcardsPageState(this.di, this.revisionStrategy, this.existingReviews);

  DolphinInformation di;
  final RevisionStrategy revisionStrategy;
  final List<Review>? existingReviews;

  Map<DRCard, Review> answers = Map();

  late int numCardsToReview;

  DRCard? currentCard;
  bool currentCardRevealed = false;

  bool forgotRatingWidgetActive = false;
  bool rememberedRatingWidgetActive = true;

  @override
  void initState() {
    super.initState();
    numCardsToReview = getNumDueCards(di.dolphin, revisionStrategy);
    nextCard();
  }

  // TODO: Explore how the algorithm actually works and consider using Good.
  // I suspect when calculating what cards need to be done, we should use Good
  // but make the number of cards due on a day be the current stuff minus the
  // number of reviews completed today (floor 0).

  // The actual dispose function cannot await async functions. Instead, we
  // ban users from swiping back to ensure that if they want to exit revision,
  // they do it by pressing one of our buttons, which ensures this function
  // gets called. TODO: Actually prevent swipe back.
  Future<void> beforePop() async {
    if (revisionStrategy == RevisionStrategy.SpacedRepetition) {
      await writeReviews(existingReviews!, answers.values.toList());
    }
  }

  void nextCard() {
    setState(() {
      currentCard = di.dolphin.nextCard();
    });
  }

  int getRemainingCardsToReview() {
    return numCardsToReview -
        answers.values.length +
        (currentCardRevealed ? 1 : 0);
  }

  void completeCard(DRCard card,
      {Rating rating = Rating.Easy, DateTime? when}) {
    DateTime ts;
    if (when != null) {
      ts = when;
    } else {
      ts = DateTime.now();
    }
    Review review = Review(
        master: card.master!,
        combination: card.combination!,
        ts: ts,
        rating: rating);
    setState(() {
      di.dolphin.addReviews([review]);
      answers[card] = review;
    });
    // TODO: If the answer hadn't been set before, don't navigte away.
    // If there was already an answer, calling this progresses to the next card.
  }

  Widget getRatingButton(Rating rating, bool active) {
    String textData;
    Color backgroundColor;
    Color overlayColor; // For tap animation, should be translucent.
    Color textColor;
    Color borderColor;
    switch (rating) {
      case Rating.Again:
        textData = "Forgot";
        overlayColor = Color.fromARGB(90, 211, 88, 79);
        break;
      case Rating.Easy:
        textData = "Got it!";
        overlayColor = Color.fromARGB(90, 72, 167, 77);
        break;
      default:
        throw "Rating $rating not supported yet";
    }
    if (active) {
      switch (rating) {
        case Rating.Again:
          backgroundColor = Color.fromARGB(118, 255, 104, 104);
          borderColor = Color.fromARGB(255, 189, 40, 29);
          textColor = Color.fromARGB(255, 179, 59, 50);
          break;
        case Rating.Easy:
          backgroundColor = Color.fromARGB(60, 88, 255, 124);
          borderColor = Color.fromARGB(255, 33, 102, 37);
          textColor = Color.fromARGB(255, 63, 156, 67);
          break;
        default:
          throw "Rating $rating not supported yet";
      }
    } else {
      backgroundColor = Color.fromARGB(0, 255, 255, 255);
      borderColor = Color.fromARGB(255, 116, 116, 116);
      textColor = Color.fromARGB(204, 0, 0, 0);
    }
    return TextButton(
        child: Text(
          textData,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: textColor),
        ),
        onPressed: () {
          switch (rating) {
            case Rating.Again:
              forgotRatingWidgetActive = true;
              rememberedRatingWidgetActive = false;
              break;
            case Rating.Easy:
              rememberedRatingWidgetActive = true;
              forgotRatingWidgetActive = false;
              break;
            default:
              throw "Rating $rating not supported yet";
          }
          completeCard(currentCard!, rating: rating);
        },
        style: ButtonStyle(
            backgroundColor: MaterialStateProperty.all(backgroundColor),
            overlayColor: MaterialStateProperty.all(overlayColor),
            padding: MaterialStateProperty.all(
                EdgeInsets.only(top: 14, bottom: 14, left: 40, right: 40)),
            side: MaterialStateProperty.all(
                BorderSide(color: borderColor, width: 1.5))));
  }

  Widget buildFlashcardWidget(bool revealed) {
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

    Widget topWidget;
    if (wordToSign) {
      if (revealed) {
        topWidget = videoPlayerScreen;
      } else {
        topWidget = Container(
            padding: EdgeInsets.only(top: 120, bottom: 70),
            child: Text("What is the sign for this word?",
                textAlign: TextAlign.center, style: TextStyle(fontSize: 20)));
      }
    } else {
      topWidget = videoPlayerScreen;
    }

    Widget bottomWidget;
    if (wordToSign) {
      bottomWidget = Text(word,
          textAlign: TextAlign.center, style: TextStyle(fontSize: 20));
    } else {
      if (!revealed) {
        bottomWidget = Text("What does this sign mean?",
            textAlign: TextAlign.center, style: TextStyle(fontSize: 20));
      } else {
        bottomWidget = Text(word,
            textAlign: TextAlign.center, style: TextStyle(fontSize: 20));
      }
    }

    Widget regionalInformationWidget =
        getRegionalInformationWidget(sw, shouldUseHorizontalDisplay);

    if (!shouldUseHorizontalDisplay) {
      List<Widget?> children = [];
      children.add(topWidget);
      children.add(Divider(
        height: 80,
        thickness: 2,
        indent: 20,
        endIndent: 20,
      ));
      children.add(bottomWidget);

      children.add(Expanded(child: Container()));
      /*
      children.add(Expanded(
          child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          currentCardRevealed = true;
        }),
        child: Container(
          constraints: BoxConstraints.expand(),
          color: Colors.red,
        ),
      )));
      */

      if (revealed) {
        children.add(Padding(padding: EdgeInsets.only(bottom: 10)));
        children.add(Row(
          children: [
            getRatingButton(Rating.Again, forgotRatingWidgetActive),
            Padding(
              padding: EdgeInsets.only(left: 15, right: 15),
            ),
            getRatingButton(Rating.Easy, rememberedRatingWidgetActive),
          ],
          mainAxisAlignment: MainAxisAlignment.center,
        ));
      }

      children.add(Padding(
        padding: EdgeInsets.only(bottom: 35),
      ));

      List<Widget> nonNullChildren = [];
      for (Widget? w in children) {
        if (w != null) {
          nonNullChildren.add(w);
        }
      }

      // Note: I put the Expanded inside a column to make the "Incorrect use
      // "of ParentDataWidget" error go away.
      return Stack(children: [
        Column(children: [
          Expanded(
              child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              completeCard(currentCard!, rating: Rating.Easy);
              currentCardRevealed = true;
            }),
            child: Container(
              constraints: BoxConstraints.expand(),
            ),
          ))
        ]),
        Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: nonNullChildren,
        )
      ]);
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
      body = buildFlashcardWidget(currentCardRevealed);
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
                onPressed: () async {
                  await beforePop();
                  Navigator.of(context).pop();
                })),
        body: Center(
          child: body,
        ));
  }
}
