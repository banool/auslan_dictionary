import 'dart:async';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/hearth.dart';
import 'package:dictionarylib/revision.dart';
import 'package:dictionarylib/video_player_screen.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

import 'entries_types.dart';
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

  @override
  void dispose() {
    nextCardTimer?.cancel();
    super.dispose();
  }

  // The actual dispose function cannot await async functions. Instead, we
  // ban users from swiping back to ensure that if they want to exit revision,
  // they do it by pressing one of our buttons, which ensures this function
  // gets called.
  Future<void> beforePop() async {
    // Single-shot + re-entrancy guard: set the flag before the first await so a
    // concurrent caller — the session-end nextCard() and the user tapping close
    // — doesn't write the reviews twice. Reset on failure so an explicit close
    // can retry.
    if (reviewsWritten) return;
    reviewsWritten = true;
    try {
      switch (widget.revisionStrategy) {
        case RevisionStrategy.SpacedRepetition:
          await writeReviews(widget.existingReviews, answers.values.toList());
          break;
        case RevisionStrategy.Random:
          await bumpRandomReviewCounter(answers.length);
          break;
      }
    } catch (e) {
      reviewsWritten = false;
      printAndLog("Failed to write reviews on exit: $e");
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
            if (mounted) {
              setState(() {
                nextCard();
                nextCardTimer = null;
              });
            }
          });
        });
      } else {
        nextCard();
      }
    } else {
      currentCardRevealed = true;
    }
  }

  // A rating button. The positive/negative meaning is carried by icon + label
  // + colour together (never colour alone) so it stays accessible.
  Widget getRatingButton(Rating rating, bool active, {bool isNext = false}) {
    final cs = Theme.of(context).colorScheme;
    final l = DictLibLocalizations.of(context)!;

    void onPressed() {
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
          throw UnsupportedError("Rating $rating not supported yet");
      }
      completeCard(currentCard!, rating: rating, forceUseTimer: isNext);
    }

    if (rating == Rating.Easy && isNext) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
        icon: const Icon(Icons.arrow_forward, size: 20),
        label: Text(l.ratingNext),
      );
    }
    // Forgot / Got it! fill when active and outline otherwise, so tapping one
    // visibly selects it (for the brief moment before the next card).
    if (rating == Rating.Hard) {
      return active
          ? FilledButton.icon(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                minimumSize: const Size(0, 54),
              ),
              icon: const Icon(Icons.close, size: 20),
              label: Text(l.ratingForgot),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error, width: 1.5),
                minimumSize: const Size(0, 54),
              ),
              icon: const Icon(Icons.close, size: 20),
              label: Text(l.ratingForgot),
            );
    }
    // Rating.Good — the positive action.
    return active
        ? FilledButton.icon(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: cs.tertiary,
              foregroundColor: cs.onTertiary,
              minimumSize: const Size(0, 54),
            ),
            icon: const Icon(Icons.check, size: 20),
            label: Text(l.ratingGotIt),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.tertiary,
              side: BorderSide(color: cs.tertiary, width: 1.5),
              minimumSize: const Size(0, 54),
            ),
            icon: const Icon(Icons.check, size: 20),
            label: Text(l.ratingGotIt),
          );
  }

  /// The single "reveal the answer" call to action shown before a card is
  /// flipped. Shared by the vertical and horizontal layouts.
  Widget _revealButton() {
    final l = DictLibLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey("revealButton"),
          onPressed: () => completeCard(currentCard!, rating: Rating.Good),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
          icon: const Icon(Icons.visibility_outlined, size: 20),
          label: Text(l.tapToReveal),
        ),
      ),
    );
  }

  Widget buildFlashcardWidget(DRCard card, ResolvedSavedVideo resolved,
      String word,
      {required bool wordToSign, required bool revealed}) {
    final l = DictLibLocalizations.of(context)!;
    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);

    // Render exactly the saved video the master represents — not every
    // video of the sub-entry. The per-video-revision model means each
    // card is one specific video the user chose to save.
    var videoPlayerScreen = VideoPlayerScreen(
      mediaLinks: [resolved.videoUrl],
      fallbackAspectRatio: 16 / 9,
      key: Key(resolved.videoUrl),
    );

    final subEntry = resolved.subEntry;

    Widget topWidget;
    if (wordToSign) {
      if (revealed) {
        topWidget = videoPlayerScreen;
      } else {
        double top = shouldUseHorizontalDisplay ? 100 : 120;
        topWidget = Container(
            padding: EdgeInsets.only(top: top, bottom: 70),
            child: Text(l.studyPromptWordToSign,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20)));
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
        bottomWidget = Text(l.studyPromptSignToWord,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20));
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
          ratingButtonsRow = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                    child: getRatingButton(
                        Rating.Hard, forgotRatingWidgetActive)),
                const SizedBox(width: 12),
                Expanded(
                    child: getRatingButton(
                        Rating.Good, rememberedRatingWidgetActive)),
              ],
            ),
          );
          break;
        case RevisionStrategy.Random:
          ratingButtonsRow = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                    child: getRatingButton(Rating.Easy,
                        forgotRatingWidgetActive,
                        isNext: true)),
              ],
            ),
          );
          break;
      }
    }

    List<Widget> openDictionaryEntryWidgets = [
      const Padding(padding: EdgeInsets.only(top: 24)),
      TextButton(
          onPressed: () async {
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => EntryPage(
                          // Use the entry already resolved for this card rather
                          // than re-looking-it-up by phrase (which would be a
                          // force-unwrap and wouldn't work for non-English
                          // revision locales).
                          entry: resolved.entry,
                          showFavouritesButton: false,
                        )));
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.openDictionaryEntry,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward, size: 16),
            ],
          ))
    ];

    if (!shouldUseHorizontalDisplay) {
      List<Widget?> children = [];
      children.add(topWidget);
      children.add(const SizedBox(height: 28));
      children.add(bottomWidget);

      if (revealed) {
        children += openDictionaryEntryWidgets;
      }

      children.add(Expanded(child: Container()));

      if (revealed) {
        children.add(const Padding(padding: EdgeInsets.only(bottom: 10)));
        children.add(ratingButtonsRow);
        children.add(regionalInformationWidget);
      } else {
        // A single, clear reveal affordance pinned at the bottom. Tapping
        // anywhere on the card also reveals (the full-bleed GestureDetector
        // below), but this explicit button is the discoverable, screen-reader
        // labelled action.
        children.add(_revealButton());
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
      } else {
        // Same explicit reveal CTA as the vertical layout, so tablets/TVs get a
        // discoverable affordance rather than relying on tap-anywhere alone.
        children.add(_revealButton());
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l = DictLibLocalizations.of(context)!;
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
    double rememberRate =
        totalAnswers == 0 ? 0 : numCardsRemembered / totalAnswers;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      children: [
        Text(
          l.sessionComplete.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: cs.primary),
        ),
        const SizedBox(height: 8),
        Text(
          l.sessionCompleteHeadline(totalAnswers),
          textAlign: TextAlign.center,
          style: tt.displaySmall?.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 26),
        Center(
          child: HearthRing(
              percent: rememberRate, size: 140, centerLabel: l.summarySuccess),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
                child: HearthStatTile(
                    value: "$totalAnswers", label: l.summaryCards)),
            const SizedBox(width: 12),
            Expanded(
                child: HearthStatTile(
                    value: "$numCardsRemembered",
                    label: l.summaryGotIt,
                    valueColor: cs.tertiary)),
            const SizedBox(width: 12),
            Expanded(
                child: HearthStatTile(
                    value: "$numCardsForgotten",
                    label: l.summaryForgot,
                    valueColor: cs.error)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = DictLibLocalizations.of(context)!;
    Widget body;
    String appBarTitle;
    List<Widget> actions = [];
    if (currentCard != null) {
      DRCard card = currentCard!;

      final resolved = widget.di.masterToVideoMap[card.master];
      if (resolved == null) {
        // Defensive: we couldn't resolve the saved video for this card (e.g.
        // the dictionary data changed mid-session). Skip to the next card
        // rather than crash.
        printAndLog("No resolved video for master ${card.master}; skipping card");
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) nextCard();
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final subEntry = resolved.subEntry as MySubEntry;

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
              child: buildFlashcardWidget(card, resolved, word,
                  wordToSign: wordToSign, revealed: currentCardRevealed)));
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
                "${DictLibLocalizations.of(context)!.setPlaybackSpeedTo} ${getPlaybackSpeedString(playbackSpeed)}"),
            duration: const Duration(milliseconds: 1000)));
      }, enabled: videoIsShowing, current: playbackSpeed));
    } else {
      body = buildSummaryWidget();
      appBarTitle = l.revisionSummaryTitle;
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
              }),
          bottom: currentCard == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  // Cards whose rating is finalised. Revealing a card adds it to
                  // `answers` (as the default rating) before it's been rated, so
                  // exclude the in-progress revealed card — otherwise the bar
                  // would jump forward on reveal, ahead of the "x / N" counter.
                  child: Builder(builder: (context) {
                    final cardsCompleted =
                        getCardsReviewed() - (currentCardRevealed ? 1 : 0);
                    return LinearProgressIndicator(
                      value: numCardsToReview > 0
                          ? (cardsCompleted / numCardsToReview).clamp(0.0, 1.0)
                          : null,
                      minHeight: 3,
                      backgroundColor: cs.surfaceContainerHighest,
                    );
                  }),
                )),
      body: body,
    ));
  }
}
