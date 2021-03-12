class Word {
  Word({this.word, this.subWords});

  String? word;
  List<SubWord>? subWords;

  Word.fromJson(String word, dynamic wordJson) {
    this.word = word;

    List<SubWord> subWords = [];
    wordJson.forEach((subJson) {
      SubWord subWord = SubWord.fromJson(subJson);
      subWords.add(subWord);
    });

    this.subWords = subWords;
  }
}

class SubWord {
  SubWord({this.keywords, this.videoLinks, this.definitions, this.regions});

  List<String>? keywords;
  List<String>? videoLinks;
  List<Definition>? definitions;
  List<String>? regions;

  SubWord.fromJson(dynamic wordJson) {
    this.keywords = wordJson["keywords"].cast<String>();
    this.videoLinks = wordJson["video_links"].cast<String>();

    List<Definition> definitions = [];
    wordJson["definitions"].forEach((heading, value) {
      List<String>? subdefinitions = value.cast<String>();
      definitions
          .add(Definition(heading: heading, subdefinitions: subdefinitions));
    });
    this.definitions = definitions;

    this.regions = wordJson["regions"].cast<String>();
  }
}

class Definition {
  Definition({this.heading, this.subdefinitions});

  final String? heading;
  final List<String>? subdefinitions;
}
