import 'dart:io';

import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/types.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:dots_indicator/dots_indicator.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'common.dart';

bool getShouldUseHorizontalLayout(BuildContext context) {
  var screenSize = MediaQuery.of(context).size;
  var shouldUseHorizontalDisplay = screenSize.width > screenSize.height * 1.2;
  return shouldUseHorizontalDisplay;
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
  SharedPreferences? prefs;

  final Word word;
  bool isFavourited = false;

  @override
  void initState() {
    initStateAsyncFuture = initStateAsync();
    super.initState();
  }

  Future<void> initStateAsync() async {
    List<Word?> favourites = await loadFavourites(context);
    if (favourites.contains(word)) {
      isFavourited = true;
    } else {
      isFavourited = false;
    }
  }

  void onPageChanged(int index) {
    setState(() {
      currentPage = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
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
            SubWordPage subWordPage = SubWordPage(word: word, subWord: subWord);
            pages.add(subWordPage);
          }

          Icon starIcon;
          if (isFavourited) {
            starIcon = Icon(Icons.star, semanticLabel: "Already favourited!");
          } else {
            starIcon =
                Icon(Icons.star_outline, semanticLabel: "Favourite this word");
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(word.word),
              actions: <Widget>[
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
                        await addToFavourites(word, context);
                      } else {
                        await removeFromFavourites(word, context);
                      }
                    },
                    child: starIcon,
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
                    itemBuilder: (context, index) =>
                        SubWordPage(word: word, subWord: word.subWords[index]),
                    onPageChanged: onPageChanged)),
          );
        });
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

class SubWordPage extends StatefulWidget {
  SubWordPage({Key? key, required this.word, required this.subWord})
      : super(key: key);

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
    var videoPlayerScreen = VideoPlayerScreen(videoLinks: subWord.videoLinks);
    String regionsStr;
    if (subWord.regions.length == 0) {
      regionsStr = "Regional information unknown";
    } else if (subWord.regions[0].toLowerCase() == "everywhere") {
      regionsStr = "All states of Australia";
    } else {
      regionsStr = subWord.regions.join(", ");
    }

    // If the display is wide enough, show the video beside the words instead
    // of above the words (as well as other layout changes).
    var shouldUseHorizontalDisplay = getShouldUseHorizontalLayout(context);

    Widget? keywordsWidget =
        getRelatedWordsWidget(context, subWord, shouldUseHorizontalDisplay);
    if (!shouldUseHorizontalDisplay) {
      List<Widget> children = [];
      children.add(videoPlayerScreen);
      if (keywordsWidget != null) {
        children.add(keywordsWidget);
      }
      children.add(Expanded(
        child: definitions(context, subWord.definitions),
      ));
      children.add(Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
              padding: EdgeInsets.only(top: 15.0),
              child: Text(
                regionsStr,
                textAlign: TextAlign.center,
              ))));
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
            Padding(
                padding: EdgeInsets.only(top: 15.0),
                child: Text(
                  regionsStr,
                  textAlign: TextAlign.center,
                )),
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
  VideoPlayerScreen({Key? key, this.videoLinks}) : super(key: key);

  final List<String>? videoLinks;

  @override
  _VideoPlayerScreenState createState() =>
      _VideoPlayerScreenState(videoLinks: videoLinks);
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  _VideoPlayerScreenState({this.videoLinks});

  final List<String>? videoLinks;

  Map<int, VideoPlayerController> controllers = {};

  List<Future<void>> initializeVideoPlayerFutures = [];

  CarouselController? carouselController;

  int currentPage = 0;

  @override
  void initState() {
    // Initialise the videos, reading from cache if possible.
    int idx = 0;
    for (String videoLink in videoLinks!) {
      initializeVideoPlayerFutures.add(initSingleVideo(videoLink, idx));
      idx += 1;
    }
    // Make carousel slider controller.
    carouselController = CarouselController();
    super.initState();
  }

  Future<void> initSingleVideo(String videoLink, int idx) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? shouldCache = prefs.getBool(KEY_SHOULD_CACHE);

    VideoPlayerOptions videoPlayerOptions =
        VideoPlayerOptions(mixWithOthers: true);

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
        setState(() {
          file = fileInfo.file;
        });
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
  }

  void onPageChanged(int newPage) {
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
    for (int idx = 0; idx < videoLinks!.length; idx++) {
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
            if (!controllers.containsKey(idx)) {
              return waitingWidget;
            }
            var controller = controllers[idx]!;
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
        onPageChanged: (index, reason) => onPageChanged(index),
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
