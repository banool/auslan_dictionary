import 'dart:async';

import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'flashcards_logic.dart';
import 'globals.dart';
import 'types.dart';
import 'video_player_screen.dart';
import 'word_page.dart';

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

  PlaybackSpeed playbackSpeed = PlaybackSpeed.One;

  Timer? nextCardTimer;

  @override
  void initState() {
    super.initState();
    numCardsToReview = getNumDueCards(di.dolphin, revisionStrategy);
    nextCard();
  }

  // The actual dispose function cannot await async functions. Instead, we
  // ban users from swiping back to ensure that if they want to exit revision,
  // they do it by pressing one of our buttons, which ensures this function
  // gets called.
  Future<void> beforePop() async {
    if (!reviewsWritten) {
      switch (revisionStrategy) {
        case RevisionStrategy.SpacedRepetition:
          await writeReviews(existingReviews!, answers.values.toList());
          break;
        case RevisionStrategy.Random:
          await bumpRandomReviewCounter(answers.length);
          break;
      }
      setState(() {
        reviewsWritten = true;
      });
    }
  }

  void nextCard() {
    setState(() {
      playbackSpeed = PlaybackSpeed.One;
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
      {Rating rating = Rating.Good,
      DateTime? when,
      bool forceUseTimer = false}) {
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
      if (forceUseTimer ||
          (previousRating != null && previousRating != review.rating)) {
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

  Widget getRatingButton(Rating rating, bool active, {bool isNext = false}) {
    String textData;
    Color backgroundColor;
    Color overlayColor; // For tap animation, should be translucent.
    Color textColor;
    Color borderColor;
    if (rating == Rating.Easy && isNext) {
      textData = "Next";
      overlayColor = Color.fromARGB(92, 30, 143, 250);
      backgroundColor = Color.fromARGB(0, 255, 255, 255);
      borderColor = Color.fromARGB(255, 116, 116, 116);
      textColor = Color.fromARGB(204, 0, 0, 0);
    } else {
      switch (rating) {
        case Rating.Hard:
          textData = "Forgot";
          overlayColor = Color.fromARGB(90, 211, 88, 79);
          break;
        case Rating.Good:
          textData = "Got it!";
          overlayColor = Color.fromARGB(90, 72, 167, 77);
          break;
        default:
          throw "Rating $rating not supported yet";
      }
      if (active) {
        switch (rating) {
          case Rating.Hard:
            backgroundColor = Color.fromARGB(118, 255, 104, 104);
            borderColor = Color.fromARGB(255, 189, 40, 29);
            textColor = Color.fromARGB(255, 179, 59, 50);
            break;
          case Rating.Good:
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
    }
    return TextButton(
        child: Text(
          textData,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: textColor),
        ),
        onPressed: () {
          switch (rating) {
            case Rating.Hard:
              forgotRatingWidgetActive = true;
              rememberedRatingWidgetActive = false;
              break;
            case Rating.Good:
              rememberedRatingWidgetActive = true;
              forgotRatingWidgetActive = false;
              break;
            case Rating.Easy:
              break;
            default:
              throw "Rating $rating not supported yet";
          }
          completeCard(currentCard!, rating: rating, forceUseTimer: isNext);
        },
        style: ButtonStyle(
            backgroundColor: MaterialStateProperty.all(backgroundColor),
            overlayColor: MaterialStateProperty.all(overlayColor),
            padding: MaterialStateProperty.all(
                EdgeInsets.only(top: 14, bottom: 14, left: 40, right: 40)),
            side: MaterialStateProperty.all(
                BorderSide(color: borderColor, width: 1.5))));
  }

  Widget buildFlashcardWidget(DRCard card, SubWord subWord, String word,
      bool wordToSign, bool revealed) {
    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);

    // See here for an explanation of why I pass in a key here:
    // https://stackoverflow.com/questions/55237188/flutter-is-not-rebuilding-same-widget-with-different-parameters
    var videoPlayerScreen = VideoPlayerScreen(
      videoLinks: subWord.videoLinks,
      key: Key(subWord.videoLinks[0]),
    );

    Widget topWidget;
    if (wordToSign) {
      if (revealed) {
        topWidget = videoPlayerScreen;
      } else {
        double top = shouldUseHorizontalDisplay ? 100 : 120;
        topWidget = Container(
            padding: EdgeInsets.only(top: top, bottom: 70),
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

    Widget regionalInformationWidget = getRegionalInformationWidget(
        subWord, shouldUseHorizontalDisplay,
        hide: !revealed);

    Widget? ratingButtonsRow;
    if (revealed) {
      switch (revisionStrategy) {
        case RevisionStrategy.SpacedRepetition:
          ratingButtonsRow = Row(
            children: [
              getRatingButton(Rating.Hard, forgotRatingWidgetActive),
              Padding(
                padding: EdgeInsets.only(left: 15, right: 15),
              ),
              getRatingButton(Rating.Good, rememberedRatingWidgetActive),
            ],
            mainAxisAlignment: MainAxisAlignment.center,
          );
          break;
        case RevisionStrategy.Random:
          ratingButtonsRow = Row(
            children: [
              getRatingButton(Rating.Easy, forgotRatingWidgetActive,
                  isNext: true),
            ],
            mainAxisAlignment: MainAxisAlignment.center,
          );
          break;
      }
    }

    List<Widget> openDictionaryEntryWidgets = [
      Padding(padding: EdgeInsets.only(top: 30)),
      TextButton(
          child: Text(
            "Open dictionary entry",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14),
          ),
          style: ButtonStyle(
            padding: MaterialStateProperty.all<EdgeInsets>(EdgeInsets.all(10)),
            backgroundColor: MaterialStateProperty.resolveWith(
              (states) {
                if (states.contains(MaterialState.disabled)) {
                  return Colors.grey;
                } else {
                  return MAIN_COLOR;
                }
              },
            ),
            foregroundColor: MaterialStateProperty.all<Color>(Colors.white),
          ),
          onPressed: () async {
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => WordPage(
                          word: keyedWordsGlobal[word]!,
                          showFavouritesButton: false,
                        )));
          })
    ];

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

      if (revealed) {
        children += openDictionaryEntryWidgets;
      }

      children.add(Expanded(child: Container()));

      if (revealed) {
        children.add(Padding(padding: EdgeInsets.only(bottom: 10)));
        children.add(ratingButtonsRow);
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
              completeCard(currentCard!, rating: Rating.Good);
            }),
            child: Container(
              key: ValueKey("revealTapArea"),
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
      MainAxisAlignment firstColumnMainAxisAlignment;
      if (wordToSign && !revealed) {
        firstColumnMainAxisAlignment = MainAxisAlignment.start;
      } else {
        firstColumnMainAxisAlignment = MainAxisAlignment.center;
      }
      List<Widget> children = [
        Padding(padding: EdgeInsets.only(top: 100)),
        bottomWidget,
      ];
      if (revealed) {
        children += openDictionaryEntryWidgets;
      }
      children.add(Expanded(
        child: Container(),
      ));
      if (revealed) {
        children.add(ratingButtonsRow!);
      }
      children.add(Padding(padding: EdgeInsets.only(bottom: 80)));
      var secondColumn = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children);
      return Stack(children: [
        Column(children: [
          Expanded(
              child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              completeCard(currentCard!, rating: Rating.Good);
            }),
            child: Container(
              key: ValueKey("revealTapArea"),
              constraints: BoxConstraints.expand(),
            ),
          ))
        ]),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
                flex: 1,
                child: Column(
                  children: [topWidget, regionalInformationWidget],
                  mainAxisAlignment: firstColumnMainAxisAlignment,
                )),
            Expanded(flex: 1, child: secondColumn),
          ],
        )
      ]);
    }
  }

  Widget buildSummaryWidget() {
    int numCardsRemembered = answers.values
        .where(
          (element) => element.rating == Rating.Good,
        )
        .length;
    int numCardsForgotten = answers.values
        .where(
          (element) => element.rating == Rating.Hard,
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

    return Column(
      children: [
        Row(children: [
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
        ], mainAxisAlignment: MainAxisAlignment.center),
        Padding(padding: EdgeInsets.only(bottom: 250))
      ],
      mainAxisAlignment: MainAxisAlignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    String appBarTitle;
    List<Widget> actions = [];
    if (currentCard != null) {
      DRCard card = currentCard!;

      SubWordWrapper subWordWrapper = di.keyToSubWordMap[card.master]!;

      String word;
      bool wordToSign = card.back![0] == VIDEO_LINKS_MARKER;
      if (wordToSign) {
        // Word on front, video on back.
        word = card.front![0];
      } else {
        word = card.back![0];
      }

      bool videoIsShowing = currentCardRevealed || !wordToSign;

      body = Center(
          child: InheritedPlaybackSpeed(
              playbackSpeed: playbackSpeed,
              child: buildFlashcardWidget(card, subWordWrapper.subWord, word,
                  wordToSign, currentCardRevealed)));
      int progressString = getCardsReviewed() + 1;
      if (currentCardRevealed) {
        progressString -= 1;
      }
      appBarTitle = "$progressString / $numCardsToReview";
      actions.add(getAuslanSignbankLaunchAppBarActionWidget(
        context,
        word,
        subWordWrapper.index,
        enabled: currentCardRevealed,
      ));
      actions.add(getPlaybackSpeedDropdownWidget((p) {
        setState(() {
          playbackSpeed = p!;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Set playback speed to ${getPlaybackSpeedString(playbackSpeed)}"),
            backgroundColor: MAIN_COLOR,
            duration: Duration(milliseconds: 1000)));
      }, enabled: videoIsShowing));
    } else {
      body = buildSummaryWidget();
      appBarTitle = "Revision Summary";
    }

    // Disable swipe back with WillPopScope.
    return WillPopScope(
        onWillPop: () async => false,
        child: Scaffold(
          appBar: AppBar(
              centerTitle: true,
              title: Text(
                appBarTitle,
                textAlign: TextAlign.center,
              ),
              actions: buildActionButtons(actions),
              leading: IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () async {
                    await beforePop();
                    Navigator.of(context).pop();
                  })),
          body: body,
        ));
  }
}
