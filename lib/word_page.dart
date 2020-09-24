import 'dart:io';

import 'package:auslan_dictionary/main.dart';
import 'package:auslan_dictionary/types.dart';
import 'package:carousel_slider/carousel_slider.dart';
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

  final Word word;
  final List<Word> allWords;

  bool shouldPlay = true;
  final GlobalKey<_VideoPlayerScreenState> _key = GlobalKey();

  void togglePlay(VideoPlayerScreen videoPlayerScreen) {
    setState(() {
      // If the video is playing, pause it.
      shouldPlay = !shouldPlay;
      _key.currentState.reactToShouldPlay(shouldPlay);
    });
  }

  TextSpan getRelatedWords() {
    Map<String, Word> allWordsMap = {};
    for (Word word in allWords) {
      allWordsMap[word.word] = word;
    }
    List<WidgetSpan> relatedWordsButtons = [];

    int idx = 0;
    for (String keyword in word.keywords) {
      if (keyword == word.word) {
        idx += 1;
        continue;
      }
      Color color;
      Function navFunction;
      if (allWordsMap.containsKey(keyword)) {
        Word relatedWord = allWordsMap[keyword];
        color =
            MAIN_COLOR; // TODO: Or just hyperlink blue, or black since it seems they all link.
        navFunction = () => navigateToWordPage(context, relatedWord, allWords);
      } else {
        color = Colors.black;
        navFunction = null;
      }
      String suffix;
      if (idx < word.keywords.length - 1) {
        suffix = ", ";
      } else {
        suffix = "";
      }
      relatedWordsButtons.add(WidgetSpan(
          child: TextButton(
              onPressed: navFunction,
              style: ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity(
                      horizontal: VisualDensity.minimumDensity,
                      vertical: VisualDensity.minimumDensity)),
              child: Text("$keyword$suffix", style: TextStyle(color: color)))));
      idx += 1;
    }
    List<InlineSpan> children = [];
    children.add(TextSpan(
        text: "Related words: ",
        style: TextStyle(fontWeight: FontWeight.bold)));
    children.addAll(relatedWordsButtons);
    return TextSpan(children: children);
  }

  @override
  Widget build(BuildContext context) {
    var videoPlayerScreen =
        VideoPlayerScreen(videoLinks: word.videoLinks, key: _key);

    return Scaffold(
        appBar: AppBar(
          title: Text(word.word),
        ),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            videoPlayerScreen,
            if (word.keywords.length > 0)
              Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                  child: Text.rich(getRelatedWords())),
            Expanded(
              child: definitions(context, word.definitions),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            // Wrap the play or pause in a call to `setState`. This ensures the
            // correct icon is shown.
            togglePlay(videoPlayerScreen);
          },
          // Display the correct icon depending on the state of the player.
          child: Icon(
            shouldPlay ? Icons.pause : Icons.play_arrow,
          ),
        ));
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

      controller = VideoPlayerController.file(file);
    } else {
      print("Caching is disabled, pulling from the network");
      controller = VideoPlayerController.network(videoLink);
    }

    // Use the controller to loop the video.
    controller.setLooping(true);

    // Turn off the sound (some videos have sound for some reason).
    controller.setVolume(0.0);

    // Play or pause the video based on whether this is the first video.
    if (idx == 0) {
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

  void reactToShouldPlay(bool shouldPlay) {
    if (shouldPlay) {
      controllers[currentPage].play();
    } else {
      // If the video is paused, play it.
      controllers[currentPage].pause();
    }
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
                Container(padding: EdgeInsets.only(top: 20), child: player);
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
                  padding: EdgeInsets.only(left: 10.0, top: 10.0),
                  child: Text(s)))
              .toList(),
        )
      ]));
}
