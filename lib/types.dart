class Word {
  Word({this.word, this.keywords, this.videoLinks, this.definitions});

  String word;
  List<String> keywords;
  List<String> videoLinks;
  Map<String, List<String>> definitions;

  Word.fromJson(String word, dynamic wordJson) {
    this.word = word;
    this.keywords = wordJson["keywords"].cast<String>();
    this.videoLinks = wordJson["video_links"].cast<String>();
    this.definitions = wordJson["definitions"].cast<List<String>>();
  }
}
