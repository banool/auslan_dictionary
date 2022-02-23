import 'package:auslan_dictionary/favourites_page.dart';
import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'package:settings_ui/settings_ui.dart';

import 'common.dart';
import 'globals.dart';
import 'settings_page.dart';
import 'types.dart';

// - The first screen for flashcards should be something that lets you choose
//   what list to revise. At first only favourites.
// - Once you start the review, push navigation, so you can't change the favourites
//   mid review.
// - In the settings, let people choose what state(s) they want to see flashcards for.
//   - What about the regional information unknown case?
// - In the flashcards app bar have a history button to see a summary of previous flashcard sessions.
// - In the settings, let people choose between random revision and spaced repetition, and in order (alphabetical or insertion order).
// - Add option to choose limit, like x cards at a time.
// - Have an info button in the app bar that takes you to a page explaining
//   how the filters and strategies work.
// - have cog icon that leads to specialist settings like wiping progress for space reptition learning
// - have option to only show one subword of a word

const String KEY_SIGN_TO_WORD = "sign_to_word";
const String KEY_WORD_TO_SIGN = "word_to_sign";
const String KEY_USE_UNKNOWN_REGION_SIGNS = "use_unknown_region_signs";
const String KEY_REVISION_STRATEGY = "revision_strategy";
const String KEY_ONE_CARD_PER_WORD = "one_card_per_word";

enum RevisionStrategy {
  SpacedRepetition,
  Random,
}

extension PrettyPrint on RevisionStrategy {
  String get pretty {
    switch (this) {
      case RevisionStrategy.SpacedRepetition:
        return "Spaced Repetition";
      case RevisionStrategy.Random:
        return "Random";
    }
  }
}

class FlashcardsPageController {
  bool isMounted = false;

  void onMount() {
    isMounted = true;
  }

  void dispose() {
    isMounted = false;
  }

  void Function() goToSettingsFunction;

  FlashcardsPageController(this.goToSettingsFunction);
}

class FlashcardsLandingPage extends StatefulWidget {
  final FlashcardsPageController controller;

  FlashcardsLandingPage({Key? key, required this.controller}) : super(key: key);

  @override
  _FlashcardsLandingPageState createState() =>
      _FlashcardsLandingPageState(controller);
}

class _FlashcardsLandingPageState extends State<FlashcardsLandingPage> {
  late FlashcardsPageController controller;

  _FlashcardsLandingPageState(FlashcardsPageController _controller) {
    controller = _controller;
  }

  late Future<void> initStateAsyncFuture;

  late int numEnabledFlashcardTypes;
  late final bool initialValueSignToWord;
  late final bool initialValueWordToSign;

  late final Map<String, List<SubWord>> favouriteSubWords;
  Map<String, List<SubWord>> filteredSubWords = Map();

  @override
  void initState() {
    super.initState();
    initStateAsyncFuture = initStateAsync();
    initialValueSignToWord =
        sharedPreferences.getBool(KEY_SIGN_TO_WORD) ?? true;
    initialValueWordToSign =
        sharedPreferences.getBool(KEY_WORD_TO_SIGN) ?? true;
    numEnabledFlashcardTypes = 0;
    if (initialValueSignToWord) {
      numEnabledFlashcardTypes += 1;
    }
    if (initialValueWordToSign) {
      numEnabledFlashcardTypes += 1;
    }
  }

  Future<void> initStateAsync() async {
    await loadFavouritesInner();
  }

  Future<void> loadFavouritesInner() async {
    List<Word> favourites = await loadFavourites(context);
    Map<String, List<SubWord>> subWords = Map();
    for (Word w in favourites) {
      subWords[w.word] = w.subWords;
    }
    setState(() {
      favouriteSubWords = subWords;
      updateFilteredSubwords();
    });
  }

  void updateFilteredSubwords() {
    setState(() {
      filteredSubWords = filterSubWords();
    });
  }

  Map<String, List<SubWord>> filterSubWords() {
    Map<String, List<SubWord>> out = Map();
    List<Region> allowedRegions =
        (sharedPreferences.getStringList(KEY_FLASHCARD_REGIONS) ?? [])
            .map((i) => Region.values[int.parse(i)])
            .toList();
    bool useUnknownRegionSigns =
        sharedPreferences.getBool(KEY_USE_UNKNOWN_REGION_SIGNS) ?? true;
    bool oneCardPerWord =
        sharedPreferences.getBool(KEY_ONE_CARD_PER_WORD) ?? false;

    for (MapEntry<String, List<SubWord>> e in favouriteSubWords.entries) {
      List<SubWord> validSubWords = [];
      e.value.shuffle();
      for (SubWord sw in e.value) {
        if (validSubWords.length > 0 && oneCardPerWord) {
          break;
        }
        if (sw.regions.contains(Region.EVERYWHERE)) {
          validSubWords.add(sw);
          continue;
        }
        if (sw.regions.length == 0 && useUnknownRegionSigns) {
          validSubWords.add(sw);
          continue;
        }
        for (Region r in sw.regions) {
          if (allowedRegions.contains(r)) {
            validSubWords.add(sw);
          }
        }
      }
      if (validSubWords.length > 0) {
        out[e.key] = validSubWords;
      }
    }
    return out;
  }

  void onPrefSwitch(String key, bool newValue,
      {bool influencesStartValidity = true}) {
    setState(() {
      sharedPreferences.setBool(key, newValue);
      if (influencesStartValidity) {
        if (newValue) {
          numEnabledFlashcardTypes += 1;
        } else {
          numEnabledFlashcardTypes -= 1;
        }
      }
    });
  }

  int getNumValidCards() {
    if (filteredSubWords.values.length == 0) {
      return 0;
    }
    if (filteredSubWords.values.length == 1) {
      return filteredSubWords.values.toList()[0].length;
    }
    return filteredSubWords.values.map((v) => v.length).reduce((a, b) => a + b);
  }

  bool startValid() {
    int revisionStrategyIndex =
        sharedPreferences.getInt(KEY_REVISION_STRATEGY) ??
            RevisionStrategy.SpacedRepetition.index;
    RevisionStrategy revisionStrategy =
        RevisionStrategy.values[revisionStrategyIndex];
    bool flashcardTypesValid = numEnabledFlashcardTypes > 0;
    bool numFilteredSubWordsValid = filteredSubWords.length > 0;
    bool validBasedOnRevisionStrategy = true;
    if (revisionStrategy == RevisionStrategy.SpacedRepetition) {
      validBasedOnRevisionStrategy = false;
    }
    // TODO: Check validity for spaced repitition case.
    print(
        "flashcardTypesValid: $flashcardTypesValid, numFilteredSubWordsValid: $numFilteredSubWordsValid, validBasedOnRevisionStrategy: $validBasedOnRevisionStrategy");
    print("num valid cards: ${getNumValidCards()}");
    return flashcardTypesValid &&
        numFilteredSubWordsValid &&
        validBasedOnRevisionStrategy;
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
          EdgeInsetsDirectional margin = EdgeInsetsDirectional.only(
              start: 15, end: 15, top: 10, bottom: 10);

          List<int> additionalRegionsValues =
              (sharedPreferences.getStringList(KEY_FLASHCARD_REGIONS) ?? [])
                  .map((e) => int.parse(e))
                  .toList();

          String regionsString = "All of Australia";

          String additionalRegionsValuesString = additionalRegionsValues
              .map((i) => Region.values[i].pretty)
              .toList()
              .join(", ");

          if (additionalRegionsValuesString.length > 0) {
            regionsString += " + " + additionalRegionsValuesString;
          }

          bool useUnknownRegionSigns =
              sharedPreferences.getBool(KEY_USE_UNKNOWN_REGION_SIGNS) ?? true;

          if (useUnknownRegionSigns) {
            regionsString += " + signs with unknown region";
          }

          int revisionStrategyIndex =
              sharedPreferences.getInt(KEY_REVISION_STRATEGY) ??
                  RevisionStrategy.SpacedRepetition.index;
          RevisionStrategy revisionStrategy =
              RevisionStrategy.values[revisionStrategyIndex];

          String cardNumberString;
          switch (revisionStrategy) {
            case RevisionStrategy.Random:
              cardNumberString = "${getNumValidCards()} cards selected";
              break;
            case RevisionStrategy.SpacedRepetition:
              cardNumberString = "Not implemented yet";
              break;
          }

          List<AbstractSettingsSection?> sections = [
            SettingsSection(
                title: Padding(
                    padding: EdgeInsets.only(bottom: 5),
                    child: Text(
                      'Flashcard Types',
                      style: TextStyle(fontSize: 16),
                    )),
                tiles: [
                  SettingsTile.switchTile(
                      title: Text(
                        'Sign -> Word',
                        style: TextStyle(fontSize: 15),
                      ),
                      initialValue:
                          sharedPreferences.getBool(KEY_SIGN_TO_WORD) ?? true,
                      onToggle: (newValue) {
                        onPrefSwitch(KEY_SIGN_TO_WORD, newValue);
                        updateFilteredSubwords();
                      }),
                  SettingsTile.switchTile(
                      title: Text(
                        'Word -> Sign',
                        style: TextStyle(fontSize: 15),
                      ),
                      initialValue:
                          sharedPreferences.getBool(KEY_WORD_TO_SIGN) ?? true,
                      onToggle: (newValue) {
                        onPrefSwitch(KEY_WORD_TO_SIGN, newValue);
                        updateFilteredSubwords();
                      }),
                ]),
            SettingsSection(
              title: Padding(
                  padding: EdgeInsets.only(bottom: 5),
                  child: Text(
                    'Revision Settings',
                    style: TextStyle(fontSize: 16),
                  )),
              tiles: [
                SettingsTile.navigation(
                  title: getText('Select revision strategy'),
                  trailing: Container(),
                  onPressed: (BuildContext context) async {
                    await showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          SimpleDialog dialog = SimpleDialog(
                            title: const Text('Strategy'),
                            children: RevisionStrategy.values
                                .map((e) => SimpleDialogOption(
                                      child: Container(
                                        padding: EdgeInsets.all(10),
                                        child: Text(
                                          e.pretty,
                                          textAlign: TextAlign.center,
                                        ),
                                        decoration: BoxDecoration(
                                            border: Border.all(
                                                color: SETTINGS_COLOR),
                                            color: SETTINGS_COLOR,
                                            borderRadius:
                                                BorderRadius.circular(20)),
                                      ),
                                      onPressed: () async {
                                        setState(() {
                                          sharedPreferences.setInt(
                                              KEY_REVISION_STRATEGY, e.index);
                                        });
                                        updateFilteredSubwords();
                                        Navigator.of(context).pop();
                                      },
                                    ))
                                .toList(),
                          );
                          return dialog;
                        });
                  },
                  description: Text(
                    RevisionStrategy.values[revisionStrategyIndex].pretty,
                    textAlign: TextAlign.center,
                  ),
                ),
                SettingsTile.navigation(
                  title: getText("Select additional sign regions"),
                  trailing: Container(),
                  onPressed: (BuildContext context) async {
                    await showDialog(
                      context: context,
                      builder: (ctx) {
                        return MultiSelectDialog(
                          listType: MultiSelectListType.CHIP,
                          title: Text("Regions"),
                          items: regionsWithoutEverywhere
                              .map((e) => MultiSelectItem(e.index, e.pretty))
                              .toList(),
                          initialValue: additionalRegionsValues,
                          onConfirm: (values) {
                            setState(() {
                              sharedPreferences.setStringList(
                                  KEY_FLASHCARD_REGIONS,
                                  values.map((e) => e.toString()).toList());
                            });
                            updateFilteredSubwords();
                          },
                        );
                      },
                    );
                  },
                ),
                SettingsTile.switchTile(
                  title: Text(
                    'Signs with unknown region',
                    style: TextStyle(fontSize: 15),
                  ),
                  initialValue: useUnknownRegionSigns,
                  onToggle: (newValue) {
                    onPrefSwitch(KEY_USE_UNKNOWN_REGION_SIGNS, newValue,
                        influencesStartValidity: false);
                    updateFilteredSubwords();
                  },
                  description: Text(
                    regionsString,
                    textAlign: TextAlign.center,
                  ),
                ),
                SettingsTile.switchTile(
                  title: Text(
                    'Show only one subcard per word',
                    style: TextStyle(fontSize: 15),
                  ),
                  initialValue:
                      sharedPreferences.getBool(KEY_ONE_CARD_PER_WORD) ?? false,
                  onToggle: (newValue) {
                    onPrefSwitch(KEY_ONE_CARD_PER_WORD, newValue,
                        influencesStartValidity: false);
                    updateFilteredSubwords();
                  },
                )
              ],
              margin: margin,
            ),
          ];

          List<AbstractSettingsSection> nonNullSections = [];
          for (AbstractSettingsSection? section in sections) {
            if (section != null) {
              nonNullSections.add(section);
            }
          }

          Widget settings = SettingsList(
            sections: nonNullSections,
          );

          Function()? onPressedStart;
          if (startValid()) {
            onPressedStart = () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => FlashcardsPage()),
              );
            };
          }

          return Container(
            child: Center(
                child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                    padding: EdgeInsets.only(top: 30, bottom: 10),
                    child: TextButton(
                      child: Text(
                        "Start",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20),
                      ),
                      style: ButtonStyle(
                        backgroundColor: MaterialStateProperty.resolveWith(
                          (states) {
                            if (states.contains(MaterialState.disabled)) {
                              return Colors.grey;
                            } else {
                              return MAIN_COLOR;
                            }
                          },
                        ),
                        foregroundColor:
                            MaterialStateProperty.all<Color>(Colors.white),
                        minimumSize:
                            MaterialStateProperty.all<Size>(Size(120, 50)),
                      ),
                      onPressed: onPressedStart,
                    )),
                Text(
                  cardNumberString,
                  textAlign: TextAlign.center,
                ),
                Expanded(child: settings),
              ],
            )),
            color: SETTINGS_COLOR,
          );
        });
  }
}

class FlashcardsPage extends StatefulWidget {
  FlashcardsPage({Key? key}) : super(key: key);

  @override
  _FlashcardsPageState createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends State<FlashcardsPage> {
  @override
  Widget build(BuildContext context) {
    DolphinSR dolphin = new DolphinSR();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Start", style: TextStyle(fontSize: 1)),
      ],
    );
  }
}
