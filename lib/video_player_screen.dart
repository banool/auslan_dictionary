import 'dart:io';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'common.dart';
import 'globals.dart';

enum PlaybackSpeed {
  PointFiveZero,
  PointSevenFive,
  One,
  OneTwoFive,
  OneFiveZero,
}

String getPlaybackSpeedString(PlaybackSpeed playbackSpeed) {
  switch (playbackSpeed) {
    case PlaybackSpeed.PointFiveZero:
      return "0.5x";
    case PlaybackSpeed.PointSevenFive:
      return "0.75x";
    case PlaybackSpeed.One:
      return "1x";
    case PlaybackSpeed.OneTwoFive:
      return "1.25x";
    case PlaybackSpeed.OneFiveZero:
      return "1.5x";
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

Widget getPlaybackSpeedDropdownWidget(void Function(PlaybackSpeed?) onChanged,
    {bool enabled = true}) {
  Color? color;
  if (!enabled) {
    color = APP_BAR_DISABLED_COLOR;
  }
  return Container(
      child: Align(
          alignment: Alignment.center,
          child: PopupMenuButton<PlaybackSpeed>(
            icon: Icon(
              Icons.slow_motion_video,
              color: color,
            ),
            enabled: enabled,
            itemBuilder: (BuildContext context) {
              return PlaybackSpeed.values.map((PlaybackSpeed value) {
                return PopupMenuItem<PlaybackSpeed>(
                  value: value,
                  child: Text(getPlaybackSpeedString(value)),
                );
              }).toList();
            },
            onSelected: enabled ? onChanged : null,
          )));
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
    bool shouldCache = sharedPreferences.getBool(KEY_SHOULD_CACHE) ?? true;

    VideoPlayerOptions videoPlayerOptions =
        VideoPlayerOptions(mixWithOthers: true);

    try {
      late VideoPlayerController controller;
      // Don't cache .bak files. They're rare and tricky to handle. In short,
      // the underlying video players depend on the extension to figure out
      // what kind of file we're working with. We need to remove the .bak
      // extension for the video player to work correctly.
      if (videoLink.endsWith(".bak")) {
        shouldCache = false;
      }
      bool shouldDownloadDirectly = !shouldCache;
      if (shouldCache) {
        try {
          print("Pulling video $videoLink from either cache or the internet");
          File file = await videoCacheManager.getSingleFile(videoLink);
          controller = VideoPlayerController.file(file,
              videoPlayerOptions: videoPlayerOptions);
        } catch (e) {
          print(
              "Failed to use cache despite caching being enabled, just trying to download directly: $e");
          shouldDownloadDirectly = true;
        }
      }
      if (shouldDownloadDirectly) {
        if (!shouldCache) {
          print("Caching is disabled, pulling from the network");
        }
        if (videoLink.endsWith(".bak")) {
          print("Building video controller with custom .bak behaviour");
          HttpClient httpClient = new HttpClient();
          var request = await httpClient.getUrl(Uri.parse(videoLink));
          var response = await request.close();
          if (response.statusCode != 200) {
            throw "Failed to load $videoLink with custom .bak behaviour: $response";
          }
          String dir = (await getTemporaryDirectory()).path;
          var bytes = await consolidateHttpClientResponseBytes(response);
          String newFileName = videoLink.split("/").last.replaceAll(".bak", "");
          File file = new File("$dir/$newFileName");
          await file.writeAsBytes(bytes);
          controller = VideoPlayerController.file(file,
              videoPlayerOptions: videoPlayerOptions);
        } else {
          controller = VideoPlayerController.network(videoLink,
              videoPlayerOptions: videoPlayerOptions);
        }
      }

      // Use the controller to loop the video.
      await controller.setLooping(true);

      // Turn off the sound (some videos have sound for some reason).
      await controller.setVolume(0.0);

      // Start the video paused.
      await controller.pause();

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
              "Failed to load video. Please confirm your device is connected to the internet. If it is, the Auslan Signbank servers may be having issues. This is not an issue with the app itself.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            Padding(padding: EdgeInsets.only(top: 10)),
            Text(
              "$videoLink: $e",
              style: TextStyle(fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
          mainAxisAlignment: MainAxisAlignment.center,
        );
      } else {
        errorWidgets[idx] = Column(children: [
          Text(
            "Unexpected error loading $videoLink: $e",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11),
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
      controllers[currentPage]?.play();
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

  void setPlaybackSpeed(
      BuildContext context, VideoPlayerController controller) {
    if (mounted) {
      double playbackSpeedDouble = getDoubleFromPlaybackSpeed(
          InheritedPlaybackSpeed.of(context)!.playbackSpeed);
      controller.setPlaybackSpeed(playbackSpeedDouble);
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
            setPlaybackSpeed(context, controller);

            // Set it again repeatedly since there can be a weird race.
            // I have confirmed that even from within video_player.dart, it is
            // trying to set the correct value but the video still plays at
            // the wrong playback speed.
            Future.delayed(Duration(milliseconds: 100),
                () => setPlaybackSpeed(context, controller));
            Future.delayed(Duration(milliseconds: 250),
                () => setPlaybackSpeed(context, controller));
            Future.delayed(Duration(milliseconds: 500),
                () => setPlaybackSpeed(context, controller));
            Future.delayed(Duration(milliseconds: 1000),
                () => setPlaybackSpeed(context, controller));
            Future.delayed(Duration(milliseconds: 2000),
                () => setPlaybackSpeed(context, controller));
            Future.delayed(Duration(milliseconds: 4000),
                () => setPlaybackSpeed(context, controller));
            Future.delayed(Duration(milliseconds: 6000),
                () => setPlaybackSpeed(context, controller));
            Future.delayed(Duration(milliseconds: 8000),
                () => setPlaybackSpeed(context, controller));

            // Play or pause the video based on whether this is the first video.
            if (idx == currentPage) {
              controller.play();
            } else {
              controller.pause();
            }

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
