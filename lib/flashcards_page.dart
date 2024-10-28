import 'dart:async';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/revision.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';

import 'entries_types.dart';
import 'video_player_screen.dart';
import 'word_page.dart';

class FlashcardsPage extends StatefulWidget {
  const FlashcardsPage({
    super.key,
    required this.di,
    required this.revisionStrategy,
    required this.existingReviews,
  });

  final DolphinInformation di;
  final RevisionStrategy revisionStrategy;
  final List<Review> existingReviews;

  @override
  FlashcardsPageState createState() => FlashcardsPageState();
}

class FlashcardsPageState extends State<FlashcardsPage> {
  Map<DRCard, Review> answers = {};

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
    numCardsToReview =
        getNumDueCards(widget.di.dolphin, widget.revisionStrategy);
    nextCard();
  }

  // The actual dispose function cannot await async functions. Instead, we
  // ban users from swiping back to ensure that if they want to exit revision,
  // they do it by pressing one of our buttons, which ensures this function
  // gets called.
  Future<void> beforePop() async {
    if (!reviewsWritten) {
      switch (widget.revisionStrategy) {
        case RevisionStrategy.SpacedRepetition:
          await writeReviews(widget.existingReviews, answers.values.toList());
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
        currentCard = widget.di.dolphin.nextCard();
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
      widget.di.dolphin.addReviews([review]);
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
          nextCardTimer = Timer(const Duration(milliseconds: 750), () {
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
    Color borderColor;
    if (rating == Rating.Easy && isNext) {
      textData = "Next";
      overlayColor = const Color.fromARGB(92, 30, 143, 250);
      backgroundColor = const Color.fromARGB(0, 255, 255, 255);
      borderColor = const Color.fromARGB(255, 116, 116, 116);
    } else {
      switch (rating) {
        case Rating.Hard:
          textData = "Forgot";
          overlayColor = const Color.fromARGB(90, 211, 88, 79);
          break;
        case Rating.Good:
          textData = "Got it!";
          overlayColor = const Color.fromARGB(90, 72, 167, 77);
          break;
        default:
          throw "Rating $rating not supported yet";
      }
      if (active) {
        switch (rating) {
          case Rating.Hard:
            backgroundColor = const Color.fromARGB(118, 255, 104, 104);
            borderColor = const Color.fromARGB(255, 189, 40, 29);
            break;
          case Rating.Good:
            backgroundColor = const Color.fromARGB(60, 88, 255, 124);
            borderColor = const Color.fromARGB(255, 33, 102, 37);
            break;
          default:
            throw "Rating $rating not supported yet";
        }
      } else {
        backgroundColor = const Color.fromARGB(0, 255, 255, 255);
        borderColor = const Color.fromARGB(255, 116, 116, 116);
      }
    }
    return TextButton(
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
            backgroundColor: WidgetStateProperty.all(backgroundColor),
            overlayColor: WidgetStateProperty.all(overlayColor),
            padding: WidgetStateProperty.all(const EdgeInsets.only(
                top: 14, bottom: 14, left: 40, right: 40)),
            side: WidgetStateProperty.all(
                BorderSide(color: borderColor, width: 1.5))),
        child: Text(
          textData,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ));
  }

  Widget buildFlashcardWidget(DRCard card, SubEntry subEntry, String word,
      bool wordToSign, bool revealed) {
    ColorScheme currentTheme = Theme.of(context).colorScheme;
    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);

    // See here for an explanation of why I pass in a key here:
    // https://stackoverflow.com/questions/55237188/flutter-is-not-rebuilding-same-widget-with-different-parameters
    var videoPlayerScreen = VideoPlayerScreen(
      videoLinks: subEntry.getMedia(),
      key: Key(subEntry.getMedia()[0]),
    );

    Widget topWidget;
    if (wordToSign) {
      if (revealed) {
        topWidget = videoPlayerScreen;
      } else {
        double top = shouldUseHorizontalDisplay ? 100 : 120;
        topWidget = Container(
            padding: EdgeInsets.only(top: top, bottom: 70),
            child: const Text("What is the sign for this word?",
                textAlign: TextAlign.center, style: TextStyle(fontSize: 20)));
      }
    } else {
      topWidget = videoPlayerScreen;
    }

    Widget bottomWidget;
    if (wordToSign) {
      bottomWidget = Text(word,
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 20));
    } else {
      if (!revealed) {
        bottomWidget = const Text("What does this sign mean?",
            textAlign: TextAlign.center, style: TextStyle(fontSize: 20));
      } else {
        bottomWidget = Text(word,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 20));
      }
    }

    Widget regionalInformationWidget = getRegionalInformationWidget(
        subEntry as MySubEntry, shouldUseHorizontalDisplay,
        hide: !revealed);

    Widget? ratingButtonsRow;
    if (revealed) {
      switch (widget.revisionStrategy) {
        case RevisionStrategy.SpacedRepetition:
          ratingButtonsRow = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              getRatingButton(Rating.Hard, forgotRatingWidgetActive),
              const Padding(
                padding: EdgeInsets.only(left: 15, right: 15),
              ),
              getRatingButton(Rating.Good, rememberedRatingWidgetActive),
            ],
          );
          break;
        case RevisionStrategy.Random:
          ratingButtonsRow = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              getRatingButton(Rating.Easy, forgotRatingWidgetActive,
                  isNext: true),
            ],
          );
          break;
      }
    }

    List<Widget> openDictionaryEntryWidgets = [
      const Padding(padding: EdgeInsets.only(top: 30)),
      TextButton(
          style: ButtonStyle(
            padding:
                WidgetStateProperty.all<EdgeInsets>(const EdgeInsets.all(10)),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) {
                if (states.contains(WidgetState.disabled)) {
                  return Colors.grey;
                } else {
                  return currentTheme.primary;
                }
              },
            ),
            foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
          ),
          onPressed: () async {
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => EntryPage(
                          entry: keyedByEnglishEntriesGlobal[word]!,
                          showFavouritesButton: false,
                        )));
          },
          child: const Text(
            "Open dictionary entry",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14),
          ))
    ];

    if (!shouldUseHorizontalDisplay) {
      List<Widget?> children = [];
      children.add(topWidget);
      children.add(const Divider(
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
        children.add(const Padding(padding: EdgeInsets.only(bottom: 10)));
        children.add(ratingButtonsRow);
        children.add(regionalInformationWidget);
      }

      children.add(const Padding(
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
              key: const ValueKey("revealTapArea"),
              constraints: const BoxConstraints.expand(),
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
        const Padding(padding: EdgeInsets.only(top: 100)),
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
      children.add(const Padding(padding: EdgeInsets.only(bottom: 80)));
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
              key: const ValueKey("revealTapArea"),
              constraints: const BoxConstraints.expand(),
            ),
          ))
        ]),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
                flex: 1,
                child: Column(
                  mainAxisAlignment: firstColumnMainAxisAlignment,
                  children: [topWidget, regionalInformationWidget],
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
        padding: const EdgeInsets.only(top: 30),
        child: Text(s, style: TextStyle(fontSize: 16, fontWeight: weight)),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Padding(
            padding: EdgeInsets.only(left: 60),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              getText("Success Rate:", bold: true),
              getText("Total Cards:", bold: true),
              getText("Successful Cards:", bold: true),
              getText("Incorrect Cards:", bold: true)
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              getText("${(rememberRate * 100).toStringAsFixed(1)}%"),
              getText("$totalAnswers"),
              getText("$numCardsRemembered"),
              getText("$numCardsForgotten"),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 60),
          ),
        ]),
        const Padding(padding: EdgeInsets.only(bottom: 250))
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    String appBarTitle;
    List<Widget> actions = [];
    if (currentCard != null) {
      DRCard card = currentCard!;

      MySubEntry subEntry =
          widget.di.keyToSubEntryMap[card.master]! as MySubEntry;

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
              child: buildFlashcardWidget(
                  card, subEntry, word, wordToSign, currentCardRevealed)));
      int progressString = getCardsReviewed() + 1;
      if (currentCardRevealed) {
        progressString -= 1;
      }
      appBarTitle = "$progressString / $numCardsToReview";
      actions.add(getAuslanSignbankLaunchAppBarActionWidget(
        context,
        word,
        subEntry.index,
        enabled: currentCardRevealed,
      ));
      actions.add(getPlaybackSpeedDropdownWidget((p) {
        setState(() {
          playbackSpeed = p!;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Set playback speed to ${getPlaybackSpeedString(playbackSpeed)}"),
            duration: const Duration(milliseconds: 1000)));
      }, enabled: videoIsShowing));
    } else {
      body = buildSummaryWidget();
      appBarTitle = "Revision Summary";
    }

    // Disable swipe back with WillPopScope.
    return PopScope(
        child: Scaffold(
      appBar: AppBar(
          centerTitle: true,
          title: Text(
            appBarTitle,
            textAlign: TextAlign.center,
          ),
          actions: buildActionButtons(actions),
          leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () async {
                await beforePop();
                Navigator.of(context).pop();
              })),
      body: body,
    ));
  }
}
