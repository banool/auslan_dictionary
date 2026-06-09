import 'dart:async';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/flashcards_logic.dart';
import 'package:dictionarylib/globals.dart';
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

  /// The cards shown so far this session, in order, and our position within
  /// them. Tracking the sequence ourselves (rather than only ever asking
  /// Dolphin for the next card) lets a back gesture revisit the previous card
  /// and then move forward again to exactly where the user was. Fresh cards are
  /// only drawn from Dolphin when we step forward past the end of this list.
  final List<DRCard> _shownCards = [];
  int _pos = -1;

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
    // Apply the optional session-size cap the user set on the landing page.
    // 0 means no limit. The landing page caps its displayed count the same way.
    final cardLimit = sharedPreferences.getInt(KEY_REVISION_CARD_LIMIT) ?? 0;
    if (cardLimit > 0 && numCardsToReview > cardLimit) {
      numCardsToReview = cardLimit;
    }
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

  /// Sync the reveal / rating-widget flags to [currentCard]. A card that's
  /// already in [answers] (one we've revealed before, e.g. when stepping
  /// back/forward through the session) reappears revealed with its prior
  /// rating selected; a fresh card starts unrevealed with the default rating.
  /// Keeping this in one place means forward- and back-navigation can't drift
  /// into showing an already-answered card as if it were new (which would make
  /// the reveal tap skip it).
  void _syncRevealStateToCurrentCard() {
    final prior = currentCard == null ? null : answers[currentCard]?.rating;
    currentCardRevealed = prior != null;
    forgotRatingWidgetActive = prior == Rating.Hard;
    rememberedRatingWidgetActive = prior != Rating.Hard;
  }

  void nextCard() {
    setState(() {
      playbackSpeed = PlaybackSpeed.One;
      if (_pos < _shownCards.length - 1) {
        // We'd stepped back earlier — move forward through the cards already
        // shown rather than drawing a new one, so back-then-forward returns to
        // exactly where the user was.
        _pos++;
        currentCard = _shownCards[_pos];
      } else if (getCardsReviewed() >= numCardsToReview) {
        // From here the only cards Dolphin will return are cards that were
        // failed as part of the revision session. We choose to cut the user
        // off here, they can start a new session to review these if they wish.
        // Accordingly set currentCard to null and store the results.
        currentCard = null;
        beforePop();
      } else {
        final next = widget.di.dolphin.nextCard();
        currentCard = next;
        if (next != null) {
          _shownCards.add(next);
          _pos = _shownCards.length - 1;
        } else {
          // Nothing left to draw — end the session.
          beforePop();
        }
      }
      _syncRevealStateToCurrentCard();
    });
  }

  /// Step back to the card shown before the current one. Wired to the system
  /// back gesture (see [PopScope] in [build]) so an accidental swipe revisits
  /// the previous card instead of dumping the user out of the session. The card
  /// reappears with its earlier answer revealed (if it had one) so they can
  /// review or change it; re-rating overwrites the stored answer.
  void previousCard() {
    if (_pos <= 0) return;
    nextCardTimer?.cancel();
    nextCardTimer = null;
    setState(() {
      playbackSpeed = PlaybackSpeed.One;
      _pos--;
      currentCard = _shownCards[_pos];
      _syncRevealStateToCurrentCard();
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
    final cs = Theme.of(context).colorScheme;
    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);

    // Render exactly the saved video the master represents — not every video of
    // the sub-entry. The per-video-revision model means each card is one
    // specific video the user chose to save.
    //
    // Tapping the video expands it over a dimmed backdrop — even while it's the
    // unrevealed "what does this sign mean?" video. Handled inside
    // VideoPlayerScreen (expandOnTap), so the inline tile pauses + hides while
    // expanded rather than a second player running. It's a nested gesture
    // target, so a tap on the video expands it while a tap elsewhere on the
    // card reveals; .jpg recordings are skipped automatically.
    final Widget tappableVideo = VideoPlayerScreen(
      mediaLinks: [resolved.videoUrl],
      fallbackAspectRatio: 16 / 9,
      key: Key(resolved.videoUrl),
      expandOnTap: true,
    );

    final subEntry = resolved.subEntry as MySubEntry;

    Widget topWidget;
    if (wordToSign) {
      if (revealed) {
        topWidget = tappableVideo;
      } else {
        double top = shouldUseHorizontalDisplay ? 100 : 120;
        topWidget = Container(
            padding: EdgeInsets.only(top: top, bottom: 70),
            child: Text(l.studyPromptWordToSign,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20)));
      }
    } else {
      topWidget = tappableVideo;
    }

    Widget bottomWidget = Text(
        wordToSign || revealed ? word : l.studyPromptSignToWord,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 20));

    Widget? ratingButtonsRow;
    if (revealed) {
      switch (widget.revisionStrategy) {
        case RevisionStrategy.SpacedRepetition:
          ratingButtonsRow = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                    child: KeyedSubtree(
                        key: const ValueKey("ratingButton.forgot"),
                        child: getRatingButton(
                            Rating.Hard, forgotRatingWidgetActive))),
                const SizedBox(width: 12),
                Expanded(
                    child: KeyedSubtree(
                        key: const ValueKey("ratingButton.gotIt"),
                        child: getRatingButton(
                            Rating.Good, rememberedRatingWidgetActive))),
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
                    child: KeyedSubtree(
                        key: const ValueKey("ratingButton.next"),
                        child: getRatingButton(Rating.Easy,
                            forgotRatingWidgetActive,
                            isNext: true))),
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
                          // Show the per-video save UI so the user can add the
                          // sign to (or remove it from) their lists straight
                          // from a card they're revising.
                          showFavouritesButton: true,
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

    // The region line, flanked by plain (no-fill) back/forward arrows that are
    // absolutely positioned on either side. Back goes to the previous card;
    // forward only lights up once you've stepped back and there's a later card
    // to return to. Shown in both states so navigation is always available.
    final regionsText = revealed ? subEntry.getRegionsString() : "";
    Widget navArrow(bool forward) {
      final enabled = forward ? _pos < _shownCards.length - 1 : _pos > 0;
      // A single opaque GestureDetector (rather than an IconButton) so the tap
      // is ALWAYS consumed here — nav when enabled, a no-op when disabled —
      // and never falls through to the card's reveal/proceed gesture. The
      // padding gives a comfortable hit area around the small chevron.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? (forward ? nextCard : previousCard) : () {},
        child: Tooltip(
          message: forward ? l.revisionNextCard : l.revisionPreviousCard,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(forward ? Icons.chevron_right : Icons.chevron_left,
                size: 30,
                color: enabled
                    ? cs.onSurfaceVariant
                    : cs.onSurfaceVariant.withValues(alpha: 0.25)),
          ),
        ),
      );
    }

    Widget regionWithArrows = SizedBox(
      height: 48,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 52),
                child: Text(regionsText, textAlign: TextAlign.center),
              ),
            ),
          ),
          Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(child: navArrow(false))),
          Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(child: navArrow(true))),
        ],
      ),
    );

    // Before the answer is shown, a tap anywhere reveals it; afterwards a tap
    // anywhere proceeds to the next card, keeping whatever rating is recorded
    // (the default "got it", or a previous answer when revisiting — it doesn't
    // override it). The video and the nav arrows are nested gesture targets, so
    // they keep their own behaviour. A pending "forgot" feedback timer
    // suppresses taps so we don't double-advance.
    void onCardTap() {
      if (nextCardTimer != null) return;
      if (!revealed) {
        completeCard(currentCard!, rating: Rating.Good);
      } else {
        nextCard();
      }
    }

    if (!shouldUseHorizontalDisplay) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCardTap,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              topWidget,
              const SizedBox(height: 28),
              bottomWidget,
              if (revealed) ...openDictionaryEntryWidgets,
              Expanded(child: Container()),
              const Padding(padding: EdgeInsets.only(bottom: 10)),
              if (revealed) ratingButtonsRow! else _revealButton(),
              regionWithArrows,
              const Padding(padding: EdgeInsets.only(bottom: 28)),
            ],
          ),
        ),
      );
    } else {
      // Mirror the word page's (verified) horizontal layout: give the video a
      // bounded half via Expanded + Center — Expanded hands the player a
      // definite width instead of letting it fight its own landscape sizing,
      // which is what left the right side blank and the frame missing while the
      // video loaded — and put the prompt, controls and nav arrows in the other
      // half.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCardTap,
        child: SafeArea(
          child: Row(
            children: [
              Expanded(flex: 5, child: Center(child: topWidget)),
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    bottomWidget,
                    if (revealed) ...openDictionaryEntryWidgets,
                    const SizedBox(height: 22),
                    if (revealed) ratingButtonsRow! else _revealButton(),
                    regionWithArrows,
                  ],
                ),
              ),
            ],
          ),
        ),
      );
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
          if (!mounted) return;
          showSnack(context, l.flashcardsCardUnavailable);
          nextCard();
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
      // 1-based position of the current card in the session sequence. Using the
      // position (rather than the answered-count) keeps the counter correct when
      // the user steps back to revisit an earlier card.
      appBarTitle = "${_pos + 1} / $numCardsToReview";
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
        showSnack(
            context,
            "${DictLibLocalizations.of(context)!.setPlaybackSpeedTo} ${getPlaybackSpeedString(playbackSpeed)}",
            duration: const Duration(milliseconds: 1000));
      }, enabled: videoIsShowing, current: playbackSpeed));
    } else {
      body = buildSummaryWidget();
      appBarTitle = l.revisionSummaryTitle;
    }

    // Swiping back does nothing: card navigation is via the on-screen arrows,
    // and leaving revision is via the close (×) button (which writes the
    // reviews). Disabling the gesture avoids an accidental swipe dumping the
    // user out mid-session. The × button uses Navigator.pop() directly, which
    // isn't gated by canPop.
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {},
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
                  // Track the current card's position so the bar matches the
                  // "x / N" counter and doesn't jump on reveal (revealing adds a
                  // default answer, which the position is immune to) or when the
                  // user steps back to an earlier card.
                  child: Builder(builder: (context) {
                    final cardsCompleted = _pos;
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
