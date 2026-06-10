import 'package:auslan_dictionary/entries_types.dart';
import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/hearth.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/save_video_sheet.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/video_player_screen.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';

Widget getAuslanSignbankLaunchAppBarActionWidget(
    BuildContext context, String word, int currentPage,
    {bool enabled = true}) {
  return buildActionButton(
    context,
    const Icon(Icons.public, semanticLabel: "Link to sign in Auslan Signbank"),
    () async {
      var url =
          'http://www.auslan.org.au/dictionary/words/$word-${currentPage + 1}.html';
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    },
    enabled: enabled,
  );
}

class EntryPage extends StatefulWidget {
  const EntryPage({
    super.key,
    required this.entry,
    required this.showFavouritesButton,
    this.focusVideo,
    this.saveToList,
  });

  final Entry entry;

  /// Whether to render the per-video save UI. Named `showFavouritesButton`
  /// for source-compat with the pre-per-video-saves codebase — the
  /// button is no longer specifically a favourites star; it's a
  /// per-video bookmark that opens the all-lists picker.
  final bool showFavouritesButton;

  /// If supplied, the page lands on the sub-entry containing this
  /// video and starts the sub-entry's video carousel on that video.
  /// Used by the list view's tap-to-jump flow.
  final SavedVideo? focusVideo;

  /// If supplied, the per-video save button adds the video straight to this
  /// list (toggling membership) instead of opening the all-lists picker. Set
  /// by the list-edit "add videos from this entry" flow.
  final EntryList? saveToList;

  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  int currentPage = 0;

  /// Within-sub-entry video index used when first building the focused
  /// sub-entry. Null when [EntryPage.focusVideo] is unset or its URL
  /// isn't in the entry's data. After first build, per-sub-entry video
  /// position is owned by [SubEntryPage]'s own state — kept alive
  /// across sub-entry swipes by [AutomaticKeepAliveClientMixin].
  int? _focusedVideoInitialIndex;

  PlaybackSpeed playbackSpeed = PlaybackSpeed.One;

  /// Pages between the entry's sub-entries (variations). Created once in
  /// [initState] (not per build) so it isn't leaked/recreated on every
  /// rebuild and an in-progress swipe isn't interrupted.
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _applyFocusVideo();
    _pageController = PageController(initialPage: currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _applyFocusVideo() {
    final focus = widget.focusVideo;
    if (focus == null) return;
    final subEntries = widget.entry.getSubEntries();
    for (var i = 0; i < subEntries.length; i++) {
      final idx = subEntries[i].getMedia().indexOf(focus.videoUrl);
      if (idx >= 0) {
        currentPage = i;
        _focusedVideoInitialIndex = idx;
        return;
      }
    }
  }

  void onPageChanged(int index) {
    // Don't reset the playback speed here: a user-chosen speed should survive
    // swiping between sub-entries. Updating currentPage flips each SubEntryPage's
    // isActive flag, which pauses the now-offscreen sub-entry's videos and
    // resumes the newly-visible one (see SubEntryPage / VideoPlayerScreen).
    setState(() {
      currentPage = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final subEntries = widget.entry.getSubEntries() as List<MySubEntry>;
    final word = widget.entry.getPhrase(LOCALE_ENGLISH)!;

    final actions = <Widget>[
      getAuslanSignbankLaunchAppBarActionWidget(context, word, currentPage),
      getPlaybackSpeedDropdownWidget(
        (p) {
          setState(() {
            playbackSpeed = p!;
          });
          showSnack(
              context,
              "${DictLibLocalizations.of(context)!.setPlaybackSpeedTo} ${getPlaybackSpeedString(p!)}",
              duration: const Duration(milliseconds: 1000));
        },
        current: playbackSpeed,
      )
    ];

    return InheritedPlaybackSpeed(
        playbackSpeed: playbackSpeed,
        child: Scaffold(
          appBar:
              AppBar(title: Text(word), actions: buildActionButtons(actions)),
          body: PageView.builder(
            controller: _pageController,
            itemCount: subEntries.length,
            itemBuilder: (context, index) => SubEntryPage(
              word: widget.entry,
              subEntry: subEntries[index],
              subEntryIndex: index,
              subEntryCount: subEntries.length,
              initialVideoIndex:
                  index == currentPage ? _focusedVideoInitialIndex : null,
              showSaveButton: widget.showFavouritesButton,
              saveToList: widget.saveToList,
              // Only the on-screen sub-entry's videos should play; kept-alive
              // off-screen pages pause via this flag (see VideoPlayerScreen).
              isActive: index == currentPage,
            ),
            onPageChanged: onPageChanged,
          ),
        ));
  }
}

Widget? getRelatedEntriesWidget(BuildContext context, MySubEntry subEntry,
    bool shouldUseHorizontalDisplay) {
  return getInnerRelatedEntriesWidget(
      context: context,
      subEntry: subEntry,
      shouldUseHorizontalDisplay: shouldUseHorizontalDisplay,
      getRelatedEntry: (keyword) =>
          keyedByEnglishEntriesGlobal.containsKey(keyword)
              ? keyedByEnglishEntriesGlobal[keyword]
              : null,
      // Tapping a related word goes to a *different* entry, so it never
      // carries the save-to-list context — saveToList stays null here.
      navigateToEntryPage: (context, entry, showFavouritesButton,
              {SavedVideo? focusVideo, EntryList? saveToList}) =>
          navigateToEntryPage(context, entry, showFavouritesButton,
              focusVideo: focusVideo));
}

Widget getRegionalInformationWidget(
    MySubEntry subEntry, bool shouldUseHorizontalDisplay,
    {bool hide = false}) {
  String regionsStr = subEntry.getRegionsString();
  if (hide) {
    regionsStr = "";
  }
  if (shouldUseHorizontalDisplay) {
    return Padding(
        padding: const EdgeInsets.only(top: 15.0),
        child: Text(
          regionsStr,
          textAlign: TextAlign.center,
        ));
  } else {
    return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
            padding: const EdgeInsets.only(top: 15.0),
            child: Text(
              regionsStr,
              textAlign: TextAlign.center,
            )));
  }
}

/// A quiet footer under the definitions: a demoted "See also" related-words
/// line first, then a globe + region line beneath it.
Widget buildWordFooter(
    BuildContext context, MySubEntry subEntry, Widget? keywordsWidget) {
  final cs = Theme.of(context).colorScheme;
  final region = subEntry.getRegionsString();
  final hasRegion = region.trim().isNotEmpty;
  if (!hasRegion && keywordsWidget == null) return const SizedBox.shrink();
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: cs.outlineVariant)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (keywordsWidget != null) keywordsWidget,
        if (hasRegion)
          Padding(
            padding: EdgeInsets.only(top: keywordsWidget != null ? 8 : 0),
            child: Row(children: [
              Icon(Icons.public, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Flexible(
                child: Text(region,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ]),
          ),
      ],
    ),
  );
}

class SubEntryPage extends StatefulWidget {
  const SubEntryPage({
    super.key,
    required this.word,
    required this.subEntry,
    this.subEntryIndex = 0,
    this.subEntryCount = 1,
    this.initialVideoIndex,
    this.showSaveButton = true,
    this.saveToList,
    this.isActive = true,
  });

  final Entry word;
  final MySubEntry subEntry;

  /// When set, the bookmark button saves straight to this list (toggling
  /// membership) instead of opening the all-lists picker.
  final EntryList? saveToList;

  /// This sub-entry's position among the entry's variations, for the dots.
  final int subEntryIndex;
  final int subEntryCount;

  /// Within-sub-entry video index to land on. Used only on first build
  /// (via [SubEntryPageState.initState]); subsequent swipes update the
  /// internal `_currentVideo` directly.
  final int? initialVideoIndex;

  /// Whether to render the per-video bookmark button. Hidden in
  /// flashcards review surfaces where bookmarking from the summary
  /// page isn't the user's intent.
  final bool showSaveButton;

  /// Whether this sub-entry is the one currently on screen. Forwarded to
  /// [VideoPlayerScreen] so off-screen kept-alive pages pause their videos
  /// instead of looping in the background.
  final bool isActive;

  @override
  SubEntryPageState createState() => SubEntryPageState();
}

class SubEntryPageState extends State<SubEntryPage>
    with AutomaticKeepAliveClientMixin {
  late int _currentVideo;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentVideo = widget.initialVideoIndex ?? 0;
  }

  void _onVideoChanged(int index) {
    if (index == _currentVideo) return;
    setState(() => _currentVideo = index);
  }

  /// Inner tier: which video *within* this variation you're on. Subdued, muted
  /// dots directly under the video. Null when there's only one recording.
  /// Shared by the vertical and horizontal layouts so tablets/TVs get it too.
  Widget? _videoIndicator(BuildContext context) {
    final videoCount = widget.subEntry.videoLinks.length;
    if (videoCount <= 1) return null;
    final cs = Theme.of(context).colorScheme;
    final l = DictLibLocalizations.of(context)!;
    final currentVideo = _currentVideo.clamp(0, videoCount - 1);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HearthDots(
              count: videoCount,
              index: currentVideo,
              size: 5,
              activeColor: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 5),
            Text(
              l.videoIndicator(currentVideo + 1, videoCount),
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// Outer tier: which variation of the word you're on. Prominent clay dots +
  /// a "Variation n of m · swipe to compare" label.
  Widget? _variationIndicator(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = DictLibLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 18),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HearthDots(
                count: widget.subEntryCount, index: widget.subEntryIndex),
            const SizedBox(height: 8),
            Text(
              l.wordVariationWithHint(
                  widget.subEntryIndex + 1, widget.subEntryCount),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Tapping a video expands it over a dimmed backdrop (handled inside
    // VideoPlayerScreen so the inline tile pauses + hides while expanded —
    // no second player). Image recordings (.jpg) are skipped automatically.
    final Widget tappableVideo = VideoPlayerScreen(
      mediaLinks: widget.subEntry.videoLinks,
      fallbackAspectRatio: 16 / 9,
      initialPage: _currentVideo,
      onPageChanged: _onVideoChanged,
      expandOnTap: true,
      isActive: widget.isActive,
    );

    Widget? bookmarkRow;
    if (widget.showSaveButton && widget.subEntry.videoLinks.isNotEmpty) {
      final urls = widget.subEntry.videoLinks;
      final url = urls[_currentVideo.clamp(0, urls.length - 1)];
      bookmarkRow = _BookmarkButton(
          key: const ValueKey('wordPage.saveButton'),
          entry: widget.word,
          videoUrl: url,
          saveToList: widget.saveToList);
    }

    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);

    Widget? keywordsWidget = getRelatedEntriesWidget(
        context, widget.subEntry, shouldUseHorizontalDisplay);

    // The within-variation video dots and the variation dots — shared by both
    // layouts (each null when there's only one video / one variation).
    final videoIndicator = _videoIndicator(context);
    final variationIndicator = _variationIndicator(context);

    if (!shouldUseHorizontalDisplay) {
      List<Widget> children = [];
      children.add(tappableVideo);
      // Inner tier: which video within this variation (only if >1 recording).
      if (bookmarkRow != null) children.add(bookmarkRow);
      if (videoIndicator != null) children.add(videoIndicator);
      children.add(Expanded(
        child: definitions(context, widget.subEntry.definitions),
      ));
      // Quiet footer: a demoted "See also" line, then the region info.
      children.add(buildWordFooter(context, widget.subEntry, keywordsWidget));
      // Outer tier: which variation of the word, anchored at the bottom.
      if (variationIndicator != null) children.add(variationIndicator);
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    } else {
      // Landscape / wide: the video sits on the left, and everything else —
      // the indicators, save button, definitions, "see also" and region — goes
      // in a scrollable panel on the right so nothing is ever clipped. SafeArea
      // keeps it clear of the notch / rounded corners.
      return SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: Center(child: tappableVideo),
            ),
            Expanded(
              flex: 4,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  if (videoIndicator != null) Center(child: videoIndicator),
                  if (bookmarkRow != null) bookmarkRow,
                  ...widget.subEntry.definitions
                      .map((d) => definition(context, d)),
                  buildWordFooter(context, widget.subEntry, keywordsWidget),
                  if (variationIndicator != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Center(child: variationIndicator),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }
}

Widget definitions(BuildContext context, List<Definition> definitions) {
  return ListView.builder(
    itemCount: definitions.length,
    itemBuilder: (context, index) {
      return definition(context, definitions[index]);
    },
  );
}

Widget definition(BuildContext context, Definition definition) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // A small primary marker + the heading set as an uppercase eyebrow.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              definition.heading!.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: cs.primary,
              ),
            ),
          ),
        ]),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: definition.subdefinitions!
              .map((s) => Padding(
                  padding: const EdgeInsets.only(left: 14.0, top: 8.0),
                  child: Text(s,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(height: 1.45))))
              .toList(),
        )
      ]));
}

/// Per-video save toggle rendered beneath the video player. Owns its
/// own state so a swipe to a new video — or the user toggling the
/// list-picker sheet — repaints just this button rather than the
/// whole entry page.
class _BookmarkButton extends StatefulWidget {
  final Entry entry;
  final String videoUrl;

  /// When set, the button toggles this video's membership in [saveToList]
  /// directly (the user arrived here to add to a specific list). When null,
  /// it opens the all-lists picker sheet.
  final EntryList? saveToList;

  const _BookmarkButton({
    super.key,
    required this.entry,
    required this.videoUrl,
    this.saveToList,
  });

  @override
  State<_BookmarkButton> createState() => _BookmarkButtonState();
}

class _BookmarkButtonState extends State<_BookmarkButton> {
  @override
  Widget build(BuildContext context) {
    final v =
        SavedVideo(entryKey: widget.entry.getKey(), videoUrl: widget.videoUrl);
    final l = DictLibLocalizations.of(context)!;

    // Direct mode: we came from a specific list, so the button just adds (or
    // removes) this video to/from that one list — no picker.
    final target = widget.saveToList;
    if (target != null) {
      final saved = target.containsVideo(v);
      // Capture before the await so we don't touch BuildContext across the gap.
      final messenger = ScaffoldMessenger.of(context);
      Future<void> toggle() async {
        try {
          if (saved) {
            await target.removeVideo(v);
          } else {
            await target.addVideo(v);
          }
        } catch (e) {
          printAndLog("Failed to toggle video in list ${target.key}: $e");
          if (mounted) {
            showSnackVia(messenger, l.saveVideoFailed);
          }
        }
        if (mounted) setState(() {});
      }

      final name = target.getName(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: SizedBox(
          width: double.infinity,
          child: saved
              ? FilledButton.icon(
                  onPressed: toggle,
                  icon: const Icon(Icons.bookmark, size: 20),
                  label: Text(l.savedToNamedList(name)),
                )
              : OutlinedButton.icon(
                  onPressed: toggle,
                  icon: const Icon(Icons.bookmark_border, size: 20),
                  label: Text(l.saveToNamedList(name)),
                ),
        ),
      );
    }

    // Count against the same set the save sheet shows (local lists routed
    // through owner wrappers + editor lists), so the label and the sheet
    // never disagree — e.g. an editor list the old myLists-only count
    // missed, leaving "saved to N lists" stuck after an unsave.
    var savedCount = 0;
    for (final list in listsService.writableLists) {
      if (list.containsVideo(v)) savedCount++;
    }
    final saved = savedCount > 0;

    // Tapping always opens the "save to list" sheet — it never silently
    // un-saves. The button just reflects how many lists hold this video.
    Future<void> openSheet() async {
      await showSaveVideoSheet(context, video: v);
      if (mounted) setState(() {});
    }

    final label = saved ? l.savedToListCount(savedCount) : l.saveVideoButton;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        width: double.infinity,
        child: saved
            ? FilledButton.icon(
                onPressed: openSheet,
                icon: const Icon(Icons.bookmark, size: 20),
                label: Text(label),
              )
            : OutlinedButton.icon(
                onPressed: openSheet,
                icon: const Icon(Icons.bookmark_border, size: 20),
                label: Text(label),
              ),
      ),
    );
  }
}
