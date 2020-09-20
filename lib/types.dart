class Word {
  Word({this.word, this.keywords, this.videoLinks, this.definitions});

  String word;
  List<String> keywords;
  List<String> videoLinks;
  List<Definition> definitions;

  Word.fromJson(String word, dynamic wordJson) {
    this.word = word;
    this.keywords = wordJson["keywords"].cast<String>();
    this.videoLinks = wordJson["video_links"].cast<String>();

    List<Definition> definitions = [];
    wordJson["definitions"].forEach((heading, value) {
      List<String> subdefinitions = value.cast<String>();
      definitions
          .add(Definition(heading: heading, subdefinitions: subdefinitions));
    });
    this.definitions = definitions;
  }
}

class Definition {
  Definition({this.heading, this.subdefinitions});

  final String heading;
  final List<String> subdefinitions;
}

const String KEY_SHOULD_CACHE = "shouldCache";
