import 'package:dots_indicator/dots_indicator.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';
import 'globals.dart';
import 'types.dart';
import 'video_player_screen.dart';

Widget getAuslanSignbankLaunchAppBarActionWidget(
    BuildContext context, String word, int currentPage,
    {bool enabled = true}) {
  return buildActionButton(
    context,
    Icon(Icons.public, semanticLabel: "Link to sign in Auslan Signbank"),
    () async {
      print('sdfdsf');
      var url =
          'http://www.auslan.org.au/dictionary/words/$word-${currentPage + 1}.html';
      await launch(url, forceSafariVC: false);
    },
    enabled: enabled,
  );
}

class WordPage extends StatefulWidget {
  WordPage({Key? key, required this.word, required this.showFavouritesButton})
      : super(key: key);

  final Word word;
  final bool showFavouritesButton;

  @override
  _WordPageState createState() =>
      _WordPageState(word: word, showFavouritesButton: showFavouritesButton);
}

class _WordPageState extends State<WordPage> {
  _WordPageState({required this.word, required this.showFavouritesButton});

  final Word word;
  final bool showFavouritesButton;

  int currentPage = 0;

  bool isFavourited = false;

  PlaybackSpeed playbackSpeed = PlaybackSpeed.One;

  @override
  void initState() {
    if (wordIsFavourited(word)) {
      isFavourited = true;
    } else {
      isFavourited = false;
    }
    super.initState();
  }

  bool wordIsFavourited(Word word) {
    return wordListManager.wordLists[KEY_FAVOURITES_WORDS]!.words
        .contains(word);
  }

  Future<void> addWordToFavourites(Word word) async {
    await wordListManager.wordLists[KEY_FAVOURITES_WORDS]!.addWord(word);
  }

  Future<void> removeWordFromFavourites(Word word) async {
    await wordListManager.wordLists[KEY_FAVOURITES_WORDS]!.removeWord(word);
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
    for (int i = 0; i < word.subWords.length; i++) {
      SubWord subWord = word.subWords[i];
      SubWordPage subWordPage = SubWordPage(
        word: word,
        subWord: subWord,
      );
      pages.add(subWordPage);
    }

    Icon starIcon;
    if (isFavourited) {
      starIcon = Icon(Icons.star, semanticLabel: "Already favourited!");
    } else {
      starIcon = Icon(Icons.star_outline, semanticLabel: "Favourite this word");
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
            await addWordToFavourites(word);
          } else {
            await removeWordFromFavourites(word);
          }
        },
      ));
    }

    actions += [
      getAuslanSignbankLaunchAppBarActionWidget(
          context, word.word, currentPage),
      getPlaybackSpeedDropdownWidget(
        (p) {
          setState(() {
            playbackSpeed = p!;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text("Set playback speed to ${getPlaybackSpeedString(p!)}"),
              backgroundColor: MAIN_COLOR,
              duration: Duration(milliseconds: 1000)));
        },
      )
    ];

    return InheritedPlaybackSpeed(
        playbackSpeed: playbackSpeed,
        child: Scaffold(
          appBar: AppBar(
              title: Text(word.word), actions: buildActionButtons(actions)),
          bottomNavigationBar: Padding(
            padding: EdgeInsets.only(top: 5, bottom: 10),
            child: DotsIndicator(
              dotsCount: word.subWords.length,
              position: currentPage.toDouble(),
              decorator: DotsDecorator(
                color: Colors.black, // Inactive color
                activeColor: MAIN_COLOR,
              ),
            ),
          ),
          body: Center(
              child: PageView.builder(
                  itemCount: word.subWords.length,
                  itemBuilder: (context, index) => SubWordPage(
                        word: word,
                        subWord: word.subWords[index],
                      ),
                  onPageChanged: onPageChanged)),
        ));
  }
}

Widget? getRelatedWordsWidget(
    BuildContext context, SubWord subWord, bool shouldUseHorizontalDisplay) {
  int numKeywords = subWord.keywords.length;
  if (numKeywords == 0) {
    return null;
  }

  Map<String?, Word> allWordsMap = {};
  for (Word word in wordsGlobal) {
    allWordsMap[word.word] = word;
  }
  List<TextSpan> textSpans = [];

  int idx = 0;
  for (String keyword in subWord.keywords) {
    Color color;
    void Function()? navFunction;
    Word? relatedWord;
    if (allWordsMap.containsKey(keyword)) {
      relatedWord = allWordsMap[keyword];
      color = MAIN_COLOR;
      navFunction = () => navigateToWordPage(context, relatedWord!);
    } else {
      relatedWord = null;
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

  var initial = TextSpan(
      text: "Related words: ",
      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold));
  textSpans = [initial] + textSpans;
  var richText = RichText(
    text: TextSpan(children: textSpans),
    textAlign: TextAlign.center,
  );

  if (shouldUseHorizontalDisplay) {
    return Padding(
        padding: EdgeInsets.only(left: 10.0, right: 20.0, top: 5.0),
        child: richText);
  } else {
    return Padding(
        padding: EdgeInsets.only(left: 20.0, right: 20.0, top: 15.0),
        child: richText);
  }
}

Widget getRegionalInformationWidget(
    SubWord subWord, bool shouldUseHorizontalDisplay,
    {bool hide = false}) {
  String regionsStr = subWord.getRegionsString();
  if (hide) {
    regionsStr = "";
  }
  if (shouldUseHorizontalDisplay) {
    return Padding(
        padding: EdgeInsets.only(top: 15.0),
        child: Text(
          regionsStr,
          textAlign: TextAlign.center,
        ));
  } else {
    return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
            padding: EdgeInsets.only(top: 15.0),
            child: Text(
              regionsStr,
              textAlign: TextAlign.center,
            )));
  }
}

class SubWordPage extends StatefulWidget {
  SubWordPage({
    Key? key,
    required this.word,
    required this.subWord,
  }) : super(key: key);

  final Word word;
  final SubWord subWord;

  @override
  _SubWordPageState createState() =>
      _SubWordPageState(word: word, subWord: subWord);
}

class _SubWordPageState extends State<SubWordPage> {
  _SubWordPageState({required this.word, required this.subWord});

  final Word word;
  final SubWord subWord;

  @override
  Widget build(BuildContext context) {
    var videoPlayerScreen = VideoPlayerScreen(
      videoLinks: subWord.videoLinks,
    );
    // If the display is wide enough, show the video beside the words instead
    // of above the words (as well as other layout changes).
    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);

    Widget? keywordsWidget =
        getRelatedWordsWidget(context, subWord, shouldUseHorizontalDisplay);
    Widget regionalInformationWidget =
        getRegionalInformationWidget(subWord, shouldUseHorizontalDisplay);

    if (!shouldUseHorizontalDisplay) {
      List<Widget> children = [];
      children.add(videoPlayerScreen);
      if (keywordsWidget != null) {
        children.add(keywordsWidget);
      }
      children.add(Expanded(
        child: definitions(context, subWord.definitions),
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
          new LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
            // TODO Make this less janky and hardcoded.
            // The issue is the parent has infinite width and height
            // and Expanded doesn't seem to be working.
            List<Widget> children = [];
            if (keywordsWidget != null) {
              children.add(keywordsWidget);
            }
            children.add(
                Expanded(child: definitions(context, subWord.definitions)));
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
      padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          definition.heading!,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        Column(
          children: definition.subdefinitions!
              .map((s) => Padding(
                  padding: EdgeInsets.only(left: 10.0, top: 8.0),
                  child: Text(s)))
              .toList(),
        )
      ]));
}
