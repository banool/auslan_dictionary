import 'package:auslan_dictionary/entries_types.dart';
import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dots_indicator/dots_indicator.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';
import 'video_player_screen.dart';

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
    APP_BAR_DISABLED_COLOR,
    enabled: enabled,
  );
}

class EntryPage extends StatefulWidget {
  const EntryPage(
      {super.key, required this.entry, required this.showFavouritesButton});

  final Entry entry;
  final bool showFavouritesButton;

  @override
  _EntryPageState createState() =>
      _EntryPageState(entry: entry, showFavouritesButton: showFavouritesButton);
}

class _EntryPageState extends State<EntryPage> {
  _EntryPageState({required this.entry, required this.showFavouritesButton});

  final Entry entry;
  final bool showFavouritesButton;

  int currentPage = 0;

  bool isFavourited = false;

  PlaybackSpeed playbackSpeed = PlaybackSpeed.One;

  @override
  void initState() {
    if (wordIsFavourited(entry)) {
      isFavourited = true;
    } else {
      isFavourited = false;
    }
    super.initState();
  }

  bool wordIsFavourited(Entry entry) {
    return userEntryListManager
        .getEntryLists()[KEY_FAVOURITES_ENTRIES]!
        .entries
        .contains(entry);
  }

  Future<void> addEntryToFavourites(Entry entry) async {
    await userEntryListManager
        .getEntryLists()[KEY_FAVOURITES_ENTRIES]!
        .addEntry(entry);
  }

  Future<void> removeEntryFromFavourites(Entry entry) async {
    await userEntryListManager
        .getEntryLists()[KEY_FAVOURITES_ENTRIES]!
        .removeEntry(entry);
  }

  void onPageChanged(int index) {
    setState(() {
      playbackSpeed = PlaybackSpeed.One;
      currentPage = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> pages = [];
    List<MySubEntry> subEntries = entry.getSubEntries() as List<MySubEntry>;
    for (int i = 0; i < subEntries.length; i++) {
      MySubEntry subEntry = subEntries[i];
      SubEntryPage subEntryPage = SubEntryPage(
        word: entry,
        subEntry: subEntry,
      );
      pages.add(subEntryPage);
    }

    Icon starIcon;
    if (isFavourited) {
      starIcon = const Icon(Icons.star, semanticLabel: "Already favourited!");
    } else {
      starIcon =
          const Icon(Icons.star_outline, semanticLabel: "Favourite this word");
    }

    List<Widget> actions = [];
    if (showFavouritesButton) {
      actions.add(buildActionButton(
        context,
        starIcon,
        () async {
          setState(() {
            isFavourited = !isFavourited;
          });
          if (isFavourited) {
            await addEntryToFavourites(entry);
          } else {
            await removeEntryFromFavourites(entry);
          }
        },
        APP_BAR_DISABLED_COLOR,
      ));
    }

    String word = entry.getPhrase(LOCALE_ENGLISH)!;

    actions += [
      getAuslanSignbankLaunchAppBarActionWidget(context, word, currentPage),
      getPlaybackSpeedDropdownWidget(
        (p) {
          setState(() {
            playbackSpeed = p!;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text("Set playback speed to ${getPlaybackSpeedString(p!)}"),
              backgroundColor: MAIN_COLOR,
              duration: const Duration(milliseconds: 1000)));
        },
      )
    ];

    return InheritedPlaybackSpeed(
        playbackSpeed: playbackSpeed,
        child: Scaffold(
          appBar:
              AppBar(title: Text(word), actions: buildActionButtons(actions)),
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.only(top: 5, bottom: 10),
            child: DotsIndicator(
              dotsCount: entry.getSubEntries().length,
              position: currentPage,
              decorator: const DotsDecorator(
                color: Colors.black, // Inactive color
                activeColor: MAIN_COLOR,
              ),
            ),
          ),
          body: Center(
              child: PageView.builder(
                  itemCount: subEntries.length,
                  itemBuilder: (context, index) => SubEntryPage(
                        word: entry,
                        subEntry: subEntries[index],
                      ),
                  onPageChanged: onPageChanged)),
        ));
  }
}

Widget? getRelatedEntriesWidget(BuildContext context, MySubEntry subEntry,
    bool shouldUseHorizontalDisplay) {
  int numKeywords = subEntry.keywords.length;
  if (numKeywords == 0) {
    return null;
  }

  List<TextSpan> textSpans = [];

  int idx = 0;
  for (String keyword in subEntry.keywords) {
    Color color;
    void Function()? navFunction;
    Entry? relatedEntry;
    if (keyedByEnglishEntriesGlobal.containsKey(keyword)) {
      relatedEntry = keyedByEnglishEntriesGlobal[keyword];
      color = MAIN_COLOR;
      navFunction = () => navigateToEntryPage(context, relatedEntry!, true);
    } else {
      relatedEntry = null;
      color = Colors.black;
      navFunction = null;
    }
    String suffix;
    if (idx < numKeywords - 1) {
      suffix = ", ";
    } else {
      suffix = "";
    }
    textSpans.add(TextSpan(
      text: "$keyword$suffix",
      style: TextStyle(color: color),
      recognizer: TapGestureRecognizer()..onTap = navFunction,
    ));
    idx += 1;
  }

  var initial = const TextSpan(
      text: "Related words: ",
      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold));
  textSpans = [initial] + textSpans;
  var richText = RichText(
    text: TextSpan(children: textSpans),
    textAlign: TextAlign.center,
  );

  if (shouldUseHorizontalDisplay) {
    return Padding(
        padding: const EdgeInsets.only(left: 10.0, right: 20.0, top: 5.0),
        child: richText);
  } else {
    return Padding(
        padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 15.0),
        child: richText);
  }
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
  });

  final Entry word;
  final MySubEntry subEntry;

  @override
  SubEntryPageState createState() => SubEntryPageState();
}

class SubEntryPageState extends State<SubEntryPage> {
  @override
  Widget build(BuildContext context) {
    var videoPlayerScreen = VideoPlayerScreen(
      videoLinks: widget.subEntry.videoLinks,
    );
    // If the display is wide enough, show the video beside the words instead
    // of above the words (as well as other layout changes).
    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);

    Widget? keywordsWidget = getRelatedEntriesWidget(
        context, widget.subEntry, shouldUseHorizontalDisplay);
    Widget regionalInformationWidget = getRegionalInformationWidget(
        widget.subEntry, shouldUseHorizontalDisplay);

    if (!shouldUseHorizontalDisplay) {
      List<Widget> children = [];
      children.add(videoPlayerScreen);
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
            regionalInformationWidget,
          ]),
          LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
            // TODO Make this less janky and hardcoded.
            // The issue is the parent has infinite width and height
            // and Expanded doesn't seem to be working.
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
