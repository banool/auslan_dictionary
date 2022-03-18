import 'dart:io';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:dots_indicator/dots_indicator.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'common.dart';
import 'globals.dart';
import 'types.dart';

enum PlaybackSpeed {
  One,
  PointSevenFive,
  PointFiveZero,
  OneFiveZero,
  OneTwoFive,
}

String getPlaybackSpeedString(PlaybackSpeed playbackSpeed) {
  switch (playbackSpeed) {
    case PlaybackSpeed.One:
      return "1x";
    case PlaybackSpeed.PointSevenFive:
      return "0.75x";
    case PlaybackSpeed.PointFiveZero:
      return "0.5x";
    case PlaybackSpeed.OneFiveZero:
      return "1.5x";
    case PlaybackSpeed.OneTwoFive:
      return "1.25x";
  }
}

double getDoubleFromPlaybackSpeed(PlaybackSpeed playbackSpeed) {
  switch (playbackSpeed) {
    case PlaybackSpeed.One:
      return 1.0;
    case PlaybackSpeed.PointSevenFive:
      return 0.75;
    case PlaybackSpeed.PointFiveZero:
      return 0.5;
    case PlaybackSpeed.OneFiveZero:
      return 1.5;
    case PlaybackSpeed.OneTwoFive:
      return 1.25;
  }
}

class InheritedPlaybackSpeed extends InheritedWidget {
  InheritedPlaybackSpeed(
      {Key? key, required this.child, required this.playbackSpeed})
      : super(key: key, child: child);

  final PlaybackSpeed playbackSpeed;
  final Widget child;

  static InheritedPlaybackSpeed? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<InheritedPlaybackSpeed>();
  }

  @override
  bool updateShouldNotify(InheritedPlaybackSpeed oldWidget) {
    return oldWidget.playbackSpeed != playbackSpeed;
  }
}

class WordPage extends StatefulWidget {
  WordPage({Key? key, required this.word}) : super(key: key);

  final Word word;

  @override
  _WordPageState createState() => _WordPageState(word: word);
}

class _WordPageState extends State<WordPage> {
  _WordPageState({required this.word});

  int currentPage = 0;
  Future<void>? initStateAsyncFuture;

  final Word word;
  bool isFavourited = false;

  PlaybackSpeed playbackSpeed = PlaybackSpeed.One;

  @override
  void initState() {
    initStateAsyncFuture = initStateAsync();
    super.initState();
  }

  Future<void> initStateAsync() async {
    if (favouritesGlobal.contains(word)) {
      isFavourited = true;
    } else {
      isFavourited = false;
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
    return InheritedPlaybackSpeed(
        playbackSpeed: playbackSpeed,
        child: FutureBuilder(
            future: initStateAsyncFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return new Center(
                  child: new CircularProgressIndicator(),
                );
              }
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
                starIcon =
                    Icon(Icons.star, semanticLabel: "Already favourited!");
              } else {
                starIcon = Icon(Icons.star_outline,
                    semanticLabel: "Favourite this word");
              }

              return Scaffold(
                appBar: AppBar(
                  title: Text(word.word),
                  actions: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(0),
                      width: 30.0,
                      child: FlatButton(
                        padding: EdgeInsets.zero,
                        textColor: Colors.white,
                        onPressed: () async {
                          setState(() {
                            switch (playbackSpeed) {
                              case PlaybackSpeed.One:
                                playbackSpeed = PlaybackSpeed.PointSevenFive;
                                break;
                              case PlaybackSpeed.PointSevenFive:
                                playbackSpeed = PlaybackSpeed.PointFiveZero;
                                break;
                              case PlaybackSpeed.PointFiveZero:
                                playbackSpeed = PlaybackSpeed.OneFiveZero;
                                break;
                              case PlaybackSpeed.OneFiveZero:
                                playbackSpeed = PlaybackSpeed.OneTwoFive;
                                break;
                              case PlaybackSpeed.OneTwoFive:
                                playbackSpeed = PlaybackSpeed.One;
                                break;
                            }
                          });
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(
                                  "Set playback speed to ${getPlaybackSpeedString(playbackSpeed)}"),
                              backgroundColor: MAIN_COLOR,
                              duration: Duration(milliseconds: 750)));
                        },
                        child: Icon(Icons.slow_motion_video),
                        shape: CircleBorder(
                            side: BorderSide(color: Colors.transparent)),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(0),
                      width: 50.0,
                      child: FlatButton(
                        padding: EdgeInsets.zero,
                        textColor: Colors.white,
                        onPressed: () async {
                          setState(() {
                            isFavourited = !isFavourited;
                          });
                          if (isFavourited) {
                            await addToFavourites(word);
                          } else {
                            await removeFromFavourites(word);
                          }
                        },
                        child: starIcon,
                        shape: CircleBorder(
                            side: BorderSide(color: Colors.transparent)),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.only(right: 10),
                      width: 40.0,
                      child: FlatButton(
                        padding: EdgeInsets.zero,
                        textColor: Colors.white,
                        onPressed: () async {
                          var url =
                              'http://www.auslan.org.au/dictionary/words/${word.word}-${currentPage + 1}.html';
                          await launch(url, forceSafariVC: false);
                        },
                        child: Icon(Icons.public,
                            semanticLabel: "Link to sign in Auslan Signbank"),
                        shape: CircleBorder(
                            side: BorderSide(color: Colors.transparent)),
                      ),
                    ),
                  ],
                ),
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
              );
            }));
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
    SubWord subWord, bool shouldUseHorizontalDisplay) {
  String regionsStr = subWord.getRegionsString();
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

class VideoPlayerScreen extends StatefulWidget {
  VideoPlayerScreen({Key? key, required this.videoLinks}) : super(key: key);

  final List<String> videoLinks;

  @override
  _VideoPlayerScreenState createState() =>
      _VideoPlayerScreenState(videoLinks: videoLinks);
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  _VideoPlayerScreenState({required this.videoLinks});

  final List<String> videoLinks;

  Map<int, VideoPlayerController> controllers = {};
  Map<int, Widget> errorWidgets = {};

  List<Future<void>> initializeVideoPlayerFutures = [];

  CarouselController? carouselController;

  int currentPage = 0;

  @override
  void initState() {
    int idx = 0;
    for (String videoLink in videoLinks) {
      var f = initSingleVideo(videoLink, idx);
      initializeVideoPlayerFutures.add(f);
      idx += 1;
    }
    // Make carousel slider controller.
    carouselController = CarouselController();
    super.initState();
  }

  Future<void> initSingleVideo(String videoLink, int idx) async {
    bool? shouldCache = sharedPreferences.getBool(KEY_SHOULD_CACHE);

    VideoPlayerOptions videoPlayerOptions =
        VideoPlayerOptions(mixWithOthers: true);

    try {
      VideoPlayerController controller;
      if (shouldCache == null || shouldCache) {
        FileInfo? fileInfo =
            await DefaultCacheManager().getFileFromCache(videoLink);

        late File file;
        if (fileInfo == null) {
          print("Video for $videoLink not in cache, fetching and caching now");
          file = await DefaultCacheManager().getSingleFile(videoLink);
        } else {
          print("Video for $videoLink is in cache, reading from there");
          file = fileInfo.file;
        }

        controller = VideoPlayerController.file(file,
            videoPlayerOptions: videoPlayerOptions);
      } else {
        print("Caching is disabled, pulling from the network");
        controller = VideoPlayerController.network(videoLink,
            videoPlayerOptions: videoPlayerOptions);
      }

      // Use the controller to loop the video.
      controller.setLooping(true);

      // Turn off the sound (some videos have sound for some reason).
      controller.setVolume(0.0);

      // Play or pause the video based on whether this is the first video.
      if (idx == currentPage) {
        await controller.play();
      } else {
        await controller.pause();
      }

      // Initialize the controller.
      await controller.initialize();

      // Store the controller for later. We check mounted in case the user
      // navigated away before the video loading, in which case calling setState
      // would be invalid.
      if (mounted) {
        setState(() {
          controllers[idx] = controller;
        });
      } else {
        print("Not calling setState because not mounted");
      }
    } catch (e) {
      if ("$e".contains("Socket")) {
        errorWidgets[idx] = Column(
          children: [
            Text(
              "Failed to load video. Please confirm your phone is connected to the internet. If it is, the Auslan Signbank servers may be having issues. This is not an issue with the app itself.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15),
            ),
            Padding(padding: EdgeInsets.only(top: 20)),
            Text(
              "Error: $e",
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            )
          ],
          mainAxisAlignment: MainAxisAlignment.center,
        );
      } else {
        errorWidgets[idx] = Column(children: [
          Text(
            "Unexpected error: $e",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14),
          )
        ]);
      }
    }
  }

  void onPageChanged(BuildContext context, int newPage) {
    setState(() {
      for (VideoPlayerController c in controllers.values) {
        c.pause();
      }
      currentPage = newPage;
      controllers[currentPage]!.play();
    });
  }

  @override
  void dispose() {
    super.dispose();
    // Ensure disposing of the VideoPlayerController to free up resources.
    for (VideoPlayerController c in controllers.values) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get height of screen to ensure that the video only takes up
    // a certain proportion of it.
    List<Widget> items = [];
    for (int idx = 0; idx < videoLinks.length; idx++) {
      var futureBuilder = FutureBuilder(
          future: initializeVideoPlayerFutures[idx],
          builder: (context, snapshot) {
            var waitingWidget = Padding(
                padding: EdgeInsets.only(top: 20),
                child: Center(
                  child: CircularProgressIndicator(),
                ));
            if (snapshot.connectionState != ConnectionState.done) {
              return waitingWidget;
            }
            if (errorWidgets.containsKey(idx)) {
              return Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Center(child: errorWidgets[idx]!));
            }
            if (!controllers.containsKey(idx)) {
              return waitingWidget;
            }
            var controller = controllers[idx]!;
            // Set playback speed here, since we need the context.
            double playbackSpeedDouble = getDoubleFromPlaybackSpeed(
                InheritedPlaybackSpeed.of(context)!.playbackSpeed);
            controller.setPlaybackSpeed(playbackSpeedDouble);
            var player = VideoPlayer(controller);
            var videoContainer =
                Container(padding: EdgeInsets.only(top: 15), child: player);
            return videoContainer;
          });
      items.add(futureBuilder);
    }
    double aspectRatio;
    if (controllers.containsKey(currentPage)) {
      aspectRatio = controllers[currentPage]!.value.aspectRatio;
    } else {
      aspectRatio = 16 / 9;
    }
    var slider = CarouselSlider(
      carouselController: carouselController,
      items: items,
      options: CarouselOptions(
        aspectRatio: aspectRatio,
        autoPlay: false,
        viewportFraction: 0.8,
        enableInfiniteScroll: false,
        onPageChanged: (index, reason) => onPageChanged(context, index),
        enlargeCenterPage: true,
      ),
    );

    var size = MediaQuery.of(context).size;
    var screenWidth = size.width;
    var screenHeight = size.height;
    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);
    var boxConstraints;
    if (shouldUseHorizontalDisplay) {
      boxConstraints = BoxConstraints(
          maxWidth: screenWidth * 0.55, maxHeight: screenHeight * 0.67);
    } else {
      boxConstraints = BoxConstraints(maxHeight: screenHeight * 0.46);
    }

    // Ensure that the video doesn't take up the whole screen.
    // This only applies a maximum bound.
    var sliderContainer = Container(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: boxConstraints,
          child: slider,
        ));

    return sliderContainer;
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
