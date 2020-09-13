import 'package:auslan_dictionary/types.dart';
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
    var videoPlayerScreen = VideoPlayerScreen(word: word, key: _key);

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
  VideoPlayerScreen({Key key, this.word}) : super(key: key);

  final Word word;

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState(word: word);
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  _VideoPlayerScreenState({this.word});

  final Word word;

  VideoPlayerController _controller;
  Future<void> _initializeVideoPlayerFuture;

  @override
  void initState() {
    // Create and store the VideoPlayerController. The VideoPlayerController
    // offers several different constructors to play videos from assets, files,
    // or the internet.
    _controller = VideoPlayerController.network(
      word.videoLinks[0],
    );

    // Initialize the controller and store the Future for later use.
    _initializeVideoPlayerFuture = _controller.initialize();

    // Use the controller to loop the video.
    _controller.setLooping(true);

    // Turn off the sound (some videos have sound for some reason).
    _controller.setVolume(0.0);

    // Play or pause the video based on shouldPlay.
    _controller.play();

    super.initState();
  }

  @override
  void dispose() {
    // Ensure disposing of the VideoPlayerController to free up resources.
    _controller.dispose();

    super.dispose();
  }

  void reactToShouldPlay(bool shouldPlay) {
    if (shouldPlay) {
      _controller.play();
    } else {
      // If the video is paused, play it.
      _controller.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initializeVideoPlayerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          // If the VideoPlayerController has finished initialization, use
          // the data it provides to limit the aspect ratio of the video.
          return AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            // Use the VideoPlayer widget to display the video.
            child: VideoPlayer(_controller),
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
