import 'package:auslan_dictionary/entries_types.dart';
import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/lists_service.dart';
import 'package:dictionarylib/save_video_sheet.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:dictionarylib/video_player_screen.dart';
import 'package:dots_indicator/dots_indicator.dart';
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
      await launch(url, forceSafariVC: false);
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

  @override
  _EntryPageState createState() => _EntryPageState();
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

  @override
  void initState() {
    super.initState();
    _applyFocusVideo();
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
    setState(() {
      playbackSpeed = PlaybackSpeed.One;
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text("Set playback speed to ${getPlaybackSpeedString(p!)}"),
              duration: const Duration(milliseconds: 1000)));
        },
      )
    ];

    return InheritedPlaybackSpeed(
        playbackSpeed: playbackSpeed,
        child: Scaffold(
          appBar:
              AppBar(title: Text(word), actions: buildActionButtons(actions)),
          body: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: PageController(initialPage: currentPage),
                  itemCount: subEntries.length,
                  itemBuilder: (context, index) => SubEntryPage(
                    word: widget.entry,
                    subEntry: subEntries[index],
                    initialVideoIndex:
                        index == currentPage ? _focusedVideoInitialIndex : null,
                    showSaveButton: widget.showFavouritesButton,
                  ),
                  onPageChanged: onPageChanged,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 5, bottom: 15),
                child: DotsIndicator(
                  dotsCount: subEntries.length,
                  position: currentPage.toDouble(),
                  decorator: DotsDecorator(
                    activeColor: MAIN_COLOR,
                  ),
                ),
              ),
            ],
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
      navigateToEntryPage: (context, entry, showFavouritesButton,
              {SavedVideo? focusVideo}) =>
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

class SubEntryPage extends StatefulWidget {
  const SubEntryPage({
    super.key,
    required this.word,
    required this.subEntry,
    this.initialVideoIndex,
    this.showSaveButton = true,
  });

  final Entry word;
  final MySubEntry subEntry;

  /// Within-sub-entry video index to land on. Used only on first build
  /// (via [SubEntryPageState.initState]); subsequent swipes update the
  /// internal `_currentVideo` directly.
  final int? initialVideoIndex;

  /// Whether to render the per-video bookmark button. Hidden in
  /// flashcards review surfaces where bookmarking from the summary
  /// page isn't the user's intent.
  final bool showSaveButton;

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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    var videoPlayerScreen = VideoPlayerScreen(
      mediaLinks: widget.subEntry.videoLinks,
      fallbackAspectRatio: 16 / 9,
      initialPage: _currentVideo,
      onPageChanged: _onVideoChanged,
    );

    Widget? bookmarkRow;
    if (widget.showSaveButton && widget.subEntry.videoLinks.isNotEmpty) {
      final urls = widget.subEntry.videoLinks;
      final url = urls[_currentVideo.clamp(0, urls.length - 1)];
      bookmarkRow = _BookmarkButton(entry: widget.word, videoUrl: url);
    }

    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);

    Widget? keywordsWidget = getRelatedEntriesWidget(
        context, widget.subEntry, shouldUseHorizontalDisplay);
    Widget regionalInformationWidget = getRegionalInformationWidget(
        widget.subEntry, shouldUseHorizontalDisplay);

    if (!shouldUseHorizontalDisplay) {
      List<Widget> children = [];
      children.add(videoPlayerScreen);
      if (bookmarkRow != null) children.add(bookmarkRow);
      if (keywordsWidget != null) {
        children.add(keywordsWidget);
      }
      children.add(Expanded(
        child: definitions(context, widget.subEntry.definitions),
      ));
      children.add(regionalInformationWidget);
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
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
            if (bookmarkRow != null) bookmarkRow,
            regionalInformationWidget,
          ]),
          LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
            List<Widget> children = [];
            if (keywordsWidget != null) {
              children.add(keywordsWidget);
            }
            children.add(Expanded(
                child: definitions(context, widget.subEntry.definitions)));
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
  return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          definition.heading!,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Column(
          children: definition.subdefinitions!
              .map((s) => Padding(
                  padding: const EdgeInsets.only(left: 10.0, top: 8.0),
                  child: Text(s)))
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
  const _BookmarkButton({required this.entry, required this.videoUrl});

  @override
  State<_BookmarkButton> createState() => _BookmarkButtonState();
}

class _BookmarkButtonState extends State<_BookmarkButton> {
  @override
  Widget build(BuildContext context) {
    final v = SavedVideo(
        entryKey: widget.entry.getKey(), videoUrl: widget.videoUrl);
    var saved = false;
    for (final list in listsService.myLists) {
      if (list.containsVideo(v)) {
        saved = true;
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          onPressed: () async {
            await showSaveVideoSheet(context, video: v);
            if (mounted) setState(() {});
          },
          icon: Icon(
              saved ? Icons.bookmark_remove : Icons.bookmark_add_outlined,
              size: 20),
          label: Text(saved ? 'Saved' : 'Save'),
        ),
      ),
    );
  }
}
