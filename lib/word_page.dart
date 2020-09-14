import 'package:auslan_dictionary/types.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class WordPage extends StatefulWidget {
  WordPage({Key key, this.word}) : super(key: key);

  final Word word;

  @override
  _WordPageState createState() => _WordPageState(word: word);
}

class _WordPageState extends State<WordPage> {
  _WordPageState({this.word});

  final Word word;

  bool shouldPlay = true;
  final GlobalKey<_VideoPlayerScreenState> _key = GlobalKey();

  void togglePlay(VideoPlayerScreen videoPlayerScreen) {
    setState(() {
      // If the video is playing, pause it.
      shouldPlay = !shouldPlay;
      _key.currentState.reactToShouldPlay(shouldPlay);
    });
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
                padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                child: Text("Keywords: ${word.keywords.join(', ')}"),
              ),
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

  List<VideoPlayerController> controllers = [];

  CarouselController carouselController;

  Future<void> _initializeVideoPlayerFuture;

  int currentPage = 0;

  @override
  void initState() {
    for (String v in videoLinks) {
      var controller = VideoPlayerController.network(
        v,
      );

      // Use the controller to loop the video.
      controller.setLooping(true);

      // Turn off the sound (some videos have sound for some reason).
      controller.setVolume(0.0);

      // Play or pause the video based on shouldPlay.
      controller.pause();

      controllers.add(controller);
    }

    // Initialize the controller and store the Future for later use.
    _initializeVideoPlayerFuture = controllers[0].initialize();

    // Initialize the rest but don't store the futures.
    for (var i = 1; i < controllers.length; i += 1) {
      controllers[i].initialize();
    }

    // Start playing first video in carousel.
    controllers[0].play();

    // Make carousel slider controller.
    carouselController = CarouselController();

    super.initState();
  }

  void onPageChanged(int newPage) {
    setState(() {
      for (VideoPlayerController c in controllers) {
        c.pause();
      }
      currentPage = newPage;
      controllers[currentPage].play();
    });
  }

  @override
  void dispose() {
    // Ensure disposing of the VideoPlayerController to free up resources.
    for (VideoPlayerController c in controllers) {
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
    for (VideoPlayerController c in controllers) {
      var player = VideoPlayer(c);
      var container =
          Container(padding: EdgeInsets.only(top: 20), child: player);
      items.add(container);
    }
    return FutureBuilder(
      future: _initializeVideoPlayerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return CarouselSlider(
            carouselController: carouselController,
            items: items,
            options: CarouselOptions(
              aspectRatio: controllers[currentPage].value.aspectRatio,
              autoPlay: false,
              viewportFraction: 0.8,
              enableInfiniteScroll: false,
              onPageChanged: (index, reason) => onPageChanged(index),
              enlargeCenterPage: true,
            ),
          );
        } else {
          // If the VideoPlayerController is still initializing, show a
          // loading spinner.
          return Padding(
              padding: EdgeInsets.only(top: 150),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [CircularProgressIndicator()],
              ));
        }
      },
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
