class Word implements Comparable<Word> {
  Word({required this.word, required this.subWords});

  late String word;
  late List<SubWord> subWords;

  Word.fromJson(String word, dynamic wordJson) {
    this.word = word;

    List<SubWord> subWords = [];
    wordJson.forEach((subJson) {
      SubWord subWord = SubWord.fromJson(subJson);
      subWords.add(subWord);
    });

    this.subWords = subWords;
  }

  @override
  int compareTo(Word other) {
    return this.word.compareTo(other.word);
  }

  @override
  String toString() {
    return this.word;
  }
}

class SubWord {
  SubWord(
      {required this.keywords,
      required this.videoLinks,
      required this.definitions,
      required this.regions});

  late List<String> keywords;
  late List<String> videoLinks;
  late List<Definition> definitions;
  late List<String> regions;

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
