import 'dart:async';

import 'package:auslan_dictionary/flashcards_logic.dart';
import 'package:auslan_dictionary/word_page.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'types.dart';

// TODO: Consider prefetching the videos as the user goes through, for speed.
// TODO: Add forwards and backwards button, to go back and fogrth and see / change your answers.

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

  bool reviewsWritten = false;

  Timer? nextCardTimer;

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
  // gets called.
  Future<void> beforePop() async {
    if (revisionStrategy == RevisionStrategy.SpacedRepetition) {
      if (!reviewsWritten) {
        await writeReviews(existingReviews!, answers.values.toList());
      }
      setState(() {
        reviewsWritten = true;
      });
    }
  }

  void nextCard() {
    setState(() {
      if (getCardsReviewed() >= numCardsToReview) {
        // From here the only cards Dolphin will return are cards that were
        // failed as part of the revision session. We choose to cut the user
        // off here, they can start a new session to review these if they wish.
        // Accordingly set currentCard to null and store the results.
        currentCard = null;
        beforePop();
      } else {
        currentCard = di.dolphin.nextCard();
      }
      currentCardRevealed = false;
      forgotRatingWidgetActive = false;
      rememberedRatingWidgetActive = true;
    });
  }

  int getCardsReviewed() {
    return answers.values.length;
  }

  void completeCard(DRCard card,
      {Rating rating = Rating.Easy, DateTime? when}) {
    // Don't ack second taps if a timer is running.
    if (nextCardTimer != null) {
      return;
    }
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
    Rating? previousRating = answers[card]?.rating;
    bool shouldNavigate = answers.containsKey(card);
    setState(() {
      di.dolphin.addReviews([review]);
      answers[card] = review;
    });
    if (shouldNavigate) {
      if (previousRating != null && previousRating != review.rating) {
        // If we're navigating to the next card because the user changed the
        // rating from the default ("remembered") to something else ("forgot"),
        // start a timer for nextCard, so they can see the feedback for hitting
        // forgot momentarily.
        setState(() {
          nextCardTimer = Timer(Duration(milliseconds: 750), () {
            setState(() {
              nextCard();
              nextCardTimer = null;
            });
          });
        });
      } else {
        nextCard();
      }
    } else {
      currentCardRevealed = true;
    }
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

  Widget buildFlashcardWidget(DRCard card, bool revealed) {
    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);

    SubWord sw = di.keyToSubWordMap[card.master]!;

    String word;
    bool wordToSign = card.back![0] == VIDEO_LINKS_MARKER;
    if (wordToSign) {
      // Word on front, video on back.
      word = card.front![0];
    } else {
      word = card.back![0];
    }

    // See here for an explanation of why I pass in a key here:
    // https://stackoverflow.com/questions/55237188/flutter-is-not-rebuilding-same-widget-with-different-parameters
    var videoPlayerScreen = VideoPlayerScreen(
        videoLinks: sw.videoLinks, key: Key(sw.videoLinks[0]));

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

    Widget regionalInformationWidget;
    if (revealed) {
      regionalInformationWidget =
          getRegionalInformationWidget(sw, shouldUseHorizontalDisplay);
    } else {
      regionalInformationWidget = Container(
        padding: EdgeInsets.only(top: 25),
      );
    }

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
        children.add(regionalInformationWidget);
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
      return Stack(children: [
        Column(children: [
          Expanded(
              child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              completeCard(currentCard!, rating: Rating.Easy);
            }),
            child: Container(
              constraints: BoxConstraints.expand(),
            ),
          ))
        ]),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Column(
              children: [topWidget, regionalInformationWidget],
              mainAxisAlignment: MainAxisAlignment.center,
            ),
            Padding(padding: EdgeInsets.only(left: 50)),
            LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
              List<Widget> children = [
                ConstrainedBox(
                    constraints: BoxConstraints(minHeight: 190, minWidth: 300),
                    child: Container(
                      padding: EdgeInsets.only(top: 120, bottom: 95),
                      child: bottomWidget,
                    ))
              ];
              if (revealed) {
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
              return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: children);
            }),
          ],
        )
      ]);
    }
  }

  Widget buildSummaryWidget() {
    int numCardsRemembered = answers.values
        .where(
          (element) => element.rating == Rating.Easy,
        )
        .length;
    int numCardsForgotten = answers.values
        .where(
          (element) => element.rating == Rating.Again,
        )
        .length;
    int totalAnswers = answers.length;
    double rememberRate = numCardsRemembered / totalAnswers;

    Widget getText(String s, {bool bold = false}) {
      FontWeight? weight;
      if (bold) {
        weight = FontWeight.w600;
      }
      return Padding(
        child: Text(s, style: TextStyle(fontSize: 16, fontWeight: weight)),
        padding: EdgeInsets.only(top: 30),
      );
    }

    // TODO: Center the Row better in the middle of the screen.
    return Column(children: [
      Spacer(),
      Row(
        children: [
          Padding(
            padding: EdgeInsets.only(left: 60),
          ),
          Column(
            children: [
              getText("Success Rate:", bold: true),
              getText("Total Cards:", bold: true),
              getText("Successful Cards:", bold: true),
              getText("Incorrect Cards:", bold: true)
            ],
            crossAxisAlignment: CrossAxisAlignment.start,
          ),
          Spacer(),
          Column(
            children: [
              getText("${(rememberRate * 100).toStringAsFixed(1)}%"),
              getText("$totalAnswers"),
              getText("$numCardsRemembered"),
              getText("$numCardsForgotten"),
            ],
            crossAxisAlignment: CrossAxisAlignment.end,
          ),
          Padding(
            padding: EdgeInsets.only(left: 60),
          ),
        ],
        mainAxisAlignment: MainAxisAlignment.center,
      ),
      Padding(
        padding: EdgeInsets.only(bottom: 100),
      ),
      Spacer(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    String appBarTitle;
    if (currentCard != null) {
      body = buildFlashcardWidget(currentCard!, currentCardRevealed);
      int progressString = getCardsReviewed() + 1;
      if (currentCardRevealed) {
        progressString -= 1;
      }
      appBarTitle = "$progressString / $numCardsToReview";
    } else {
      body = buildSummaryWidget();
      appBarTitle = "Revision Summary";
    }

    // Disable swipe back with WillPopScope.
    return WillPopScope(
        onWillPop: () async => false,
        child: Scaffold(
            appBar: AppBar(
                title: Text(appBarTitle),
                leading: IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () async {
                      await beforePop();
                      Navigator.of(context).pop();
                    })),
            body: Center(
              child: body,
            )));
  }
}
