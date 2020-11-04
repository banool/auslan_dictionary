import 'dart:io';

import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/types.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:dots_indicator/dots_indicator.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'common.dart';

class WordPage extends StatefulWidget {
  WordPage({Key key, this.word, this.allWords}) : super(key: key);

  final Word word;
  final List<Word> allWords;

  @override
  _WordPageState createState() =>
      _WordPageState(word: word, allWords: allWords);
}

class _WordPageState extends State<WordPage> {
  _WordPageState({this.word, this.allWords});

  int currentPage = 0;

  void onPageChanged(int index) {
    setState(() {
      currentPage = index;
    });
  }

  final Word word;
  final List<Word> allWords;

  @override
  Widget build(BuildContext context) {
    List<Widget> pages = [];
    for (int i = 0; i < word.subWords.length; i++) {
      SubWord subWord = word.subWords[i];
      SubWordPage subWordPage =
          SubWordPage(word: word, allWords: allWords, subWord: subWord);
      pages.add(subWordPage);
    }

    return Scaffold(
        appBar: AppBar(
          title: Text(word.word),
        ),
        body: PageView.builder(
            itemCount: word.subWords.length,
            itemBuilder: (context, index) => SubWordPage(
                word: word, allWords: allWords, subWord: word.subWords[index]),
            onPageChanged: onPageChanged),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(top: 5, bottom: 15),
          child: DotsIndicator(
            dotsCount: word.subWords.length,
            position: currentPage.toDouble(),
            decorator: DotsDecorator(
              color: Colors.black, // Inactive color
              activeColor: MAIN_COLOR,
            ),
          ),
        ));
  }
}

class SubWordPage extends StatefulWidget {
  SubWordPage({Key key, this.word, this.allWords, this.subWord})
      : super(key: key);

  final Word word;
  final List<Word> allWords;
  final SubWord subWord;

  @override
  _SubWordPageState createState() =>
      _SubWordPageState(word: word, allWords: allWords, subWord: subWord);
}

class _SubWordPageState extends State<SubWordPage> {
  _SubWordPageState({this.word, this.allWords, this.subWord});

  final Word word;
  final List<Word> allWords;
  final SubWord subWord;

  RichText getRelatedWords() {
    Map<String, Word> allWordsMap = {};
    for (Word word in allWords) {
      allWordsMap[word.word] = word;
    }
    List<TextSpan> textSpans = [];
    textSpans.add(TextSpan(
        text: "Related words: ",
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)));

    int idx = 0;
    for (String keyword in subWord.keywords) {
      if (keyword == word.word) {
        idx += 1;
        continue;
      }
      Color color;
      Function navFunction;
      Word relatedWord;
      if (allWordsMap.containsKey(keyword)) {
        relatedWord = allWordsMap[keyword];
        color = MAIN_COLOR;
        navFunction = () => navigateToWordPage(context, relatedWord, allWords);
      } else {
        relatedWord = null;
        color = Colors.black;
        navFunction = null;
      }
      String suffix;
      if (idx < subWord.keywords.length - 1) {
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
    return RichText(text: TextSpan(children: textSpans));
  }

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

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        videoPlayerScreen,
        if (subWord.keywords.length > 0)
          Padding(
              padding: EdgeInsets.only(
                  left: 20.0, right: 20.0, top: 15.0, bottom: 10.0),
              child: getRelatedWords()),
        Expanded(
          child: definitions(context, subWord.definitions),
        ),
        Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
                padding: EdgeInsets.only(bottom: 5.0, top: 15.0),
                child: Text(
                  regionsStr,
                  textAlign: TextAlign.center,
                ))),
      ],
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  VideoPlayerScreen({Key key, this.videoLinks}) : super(key: key);

  final List<String> videoLinks;

  @override
  _VideoPlayerScreenState createState() =>
      _VideoPlayerScreenState(videoLinks: videoLinks);
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  _VideoPlayerScreenState({this.videoLinks});

  final List<String> videoLinks;

  Map<int, VideoPlayerController> controllers = {};

  List<Future<void>> initializeVideoPlayerFutures = [];

  Future<void> firstInitVideosFuture;

  CarouselController carouselController;

  int currentPage = 0;

  @override
  void initState() {
    // Initialise the videos, reading from cache if possible.
    int idx = 0;
    for (String videoLink in videoLinks) {
      initializeVideoPlayerFutures.add(initSingleVideo(videoLink, idx));
      idx += 1;
    }
    // Make carousel slider controller.
    carouselController = CarouselController();
    super.initState();
  }

  Future<void> initSingleVideo(String videoLink, int idx) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool shouldCache = prefs.getBool(KEY_SHOULD_CACHE);

    VideoPlayerOptions videoPlayerOptions =
        VideoPlayerOptions(mixWithOthers: true);

    VideoPlayerController controller;
    if (shouldCache == null || shouldCache) {
      FileInfo fileInfo =
          await DefaultCacheManager().getFileFromCache(videoLink);

      File file;
      if (fileInfo == null || fileInfo.file == null) {
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
      controller.play();
    } else {
      controller.pause();
    }

    // Store the controller for later.
    setState(() {
      controllers[idx] = controller;
    });

    // Initialize the controller.
    await controller.initialize();

    // Set state again so it rebuilds and adjusts the aspect ratio.
    setState(() {});
  }

  void onPageChanged(int newPage) {
    setState(() {
      for (VideoPlayerController c in controllers.values) {
        c.pause();
      }
      currentPage = newPage;
      controllers[currentPage].play();
    });
  }

  @override
  void dispose() {
    // Ensure disposing of the VideoPlayerController to free up resources.
    for (VideoPlayerController c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> items = [];
    for (int idx = 0; idx < videoLinks.length; idx++) {
      var futureBuilder = FutureBuilder(
          future: initializeVideoPlayerFutures[idx],
          builder: (context, snapshot) {
            var waitingWidget = Padding(
                padding: EdgeInsets.only(top: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [CircularProgressIndicator()],
                ));
            if (snapshot.connectionState != ConnectionState.done) {
              return waitingWidget;
            }
            if (!controllers.containsKey(idx)) {
              return waitingWidget;
            }
            var controller = controllers[idx];
            var player = VideoPlayer(controller);
            var videoContainer =
                Container(padding: EdgeInsets.only(top: 15), child: player);
            return videoContainer;
          });
      items.add(futureBuilder);
    }
    double aspectRatio;
    if (controllers.containsKey(currentPage)) {
      aspectRatio = controllers[currentPage].value.aspectRatio;
    } else {
      aspectRatio = 16 / 9;
    }
    return CarouselSlider(
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
          definition.heading,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        Column(
          children: definition.subdefinitions
              .map((s) => Padding(
                  padding: EdgeInsets.only(left: 10.0, top: 8.0),
                  child: Text(s)))
              .toList(),
        )
      ]));
}
