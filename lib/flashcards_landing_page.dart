import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'package:settings_ui/settings_ui.dart';

import 'common.dart';
import 'flashcards_help_page.dart';
import 'flashcards_logic.dart';
import 'flashcards_page.dart';
import 'globals.dart';
import 'revision_history_page.dart';
import 'settings_page.dart';
import 'top_level_scaffold.dart';
import 'types.dart';
import 'word_list_logic.dart';

const String KEY_SIGN_TO_WORD = "sign_to_word";
const String KEY_WORD_TO_SIGN = "word_to_sign";
const String KEY_USE_UNKNOWN_REGION_SIGNS = "use_unknown_region_signs";
const String KEY_ONE_CARD_PER_WORD = "one_card_per_word";

const String KEY_LISTS_TO_REVIEW = "lists_chosen_to_review";

const String ONLY_ONE_CARD_TEXT = "Show only one set of cards per word";
const String UNKNOWN_REGIONS_TEXT = "Signs with unknown region";

class FlashcardsLandingPage extends StatefulWidget {
  @override
  _FlashcardsLandingPageState createState() => _FlashcardsLandingPageState();
}

class _FlashcardsLandingPageState extends State<FlashcardsLandingPage> {
  late int numEnabledFlashcardTypes;

  late final bool initialValueSignToWord;
  late final bool initialValueWordToSign;

  late List<String> listsToReview;
  late Set<Word> wordsFromLists;

  Map<String, List<SubWordWrapper>> filteredSubWords = Map();

  late DolphinInformation dolphinInformation;
  List<Review>? existingReviews;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addObserver(LifecycleEventHandler(resumeCallBack: () async {
      updateRevisionSettings();
      print("Updated revision settings on foregrounding");
    }));
    updateRevisionSettings();
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

  void updateFilteredSubwords() {
    // Get lists we intend to review.
    listsToReview = sharedPreferences.getStringList(KEY_LISTS_TO_REVIEW) ??
        [KEY_FAVOURITES_WORDS];

    // Filter out lists that no longer exist.
    listsToReview.removeWhere(
        (element) => !wordListManager.wordLists.containsKey(element));

    // Get the words from all these lists.
    wordsFromLists = getWordsFromLists(listsToReview);

    // Get the subwords from all these words.
    Map<String, List<SubWordWrapper>> subWordsToReview =
        getSubWordsFromWords(wordsFromLists);

    // Load up all the data needed to filter the subwords.
    List<Region> allowedRegions =
        (sharedPreferences.getStringList(KEY_FLASHCARD_REGIONS) ?? [])
            .map((i) => Region.values[int.parse(i)])
            .toList();
    bool useUnknownRegionSigns =
        sharedPreferences.getBool(KEY_USE_UNKNOWN_REGION_SIGNS) ?? true;
    bool oneCardPerWord =
        sharedPreferences.getBool(KEY_ONE_CARD_PER_WORD) ?? false;

    // Finally get the final list of filtered subwords.
    setState(() {
      filteredSubWords = filterSubWords(subWordsToReview, allowedRegions,
          useUnknownRegionSigns, oneCardPerWord);
    });
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

  int getNumValidSubWords() {
    if (filteredSubWords.values.length == 0) {
      return 0;
    }
    if (filteredSubWords.values.length == 1) {
      return filteredSubWords.values.toList()[0].length;
    }
    return filteredSubWords.values.map((v) => v.length).reduce((a, b) => a + b);
  }

  bool startValid() {
    var revisionStrategy = loadRevisionStrategy();
    bool flashcardTypesValid = numEnabledFlashcardTypes > 0;
    bool numFilteredSubWordsValid = getNumValidSubWords() > 0;
    bool numCardsValid =
        getNumDueCards(dolphinInformation.dolphin, revisionStrategy) > 0;
    bool validBasedOnRevisionStrategy = true;
    return flashcardTypesValid &&
        numFilteredSubWordsValid &&
        numCardsValid &&
        validBasedOnRevisionStrategy;
  }

  DolphinInformation getDolphin({RevisionStrategy? revisionStrategy}) {
    revisionStrategy = revisionStrategy ?? loadRevisionStrategy();
    var wordToSign = sharedPreferences.getBool(KEY_WORD_TO_SIGN) ?? true;
    var signToWord = sharedPreferences.getBool(KEY_SIGN_TO_WORD) ?? true;
    var masters = getMasters(filteredSubWords, wordToSign, signToWord);
    switch (revisionStrategy) {
      case RevisionStrategy.Random:
        return getDolphinInformation(filteredSubWords, masters);
      case RevisionStrategy.SpacedRepetition:
        if (existingReviews == null) {
          setState(() {
            existingReviews = readReviews();
          });
          print("Start: Read ${existingReviews!.length} reviews from storage");
        }
        return getDolphinInformation(filteredSubWords, masters,
            reviews: existingReviews);
    }
  }

  void updateDolphin() {
    setState(() {
      dolphinInformation = getDolphin();
    });
  }

  void updateRevisionSettings() {
    setState(() {
      updateFilteredSubwords();
      updateDolphin();
    });
  }

  @override
  Widget build(BuildContext context) {
    EdgeInsetsDirectional margin =
        EdgeInsetsDirectional.only(start: 15, end: 15, top: 10, bottom: 10);

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

    var revisionStrategy = loadRevisionStrategy();

    int cardsToDo =
        getNumDueCards(dolphinInformation.dolphin, revisionStrategy);
    String cardNumberString;
    switch (revisionStrategy) {
      case RevisionStrategy.Random:
        cardNumberString = "$cardsToDo cards selected";
        break;
      case RevisionStrategy.SpacedRepetition:
        cardNumberString = "$cardsToDo cards due";
        break;
    }

    SettingsSection? sourceListSection;
    sourceListSection = SettingsSection(
        title: Padding(
            padding: EdgeInsets.only(bottom: 5),
            child: Text(
              'Revision Sources',
              style: TextStyle(fontSize: 16),
            )),
        tiles: [
          SettingsTile.navigation(
            title: getText("Select lists to revise"),
            trailing: Container(),
            onPressed: (BuildContext context) async {
              await showDialog(
                context: context,
                builder: (ctx) {
                  List<MultiSelectItem<String>> items = [];
                  for (MapEntry<String, WordList> e
                      in wordListManager.wordLists.entries) {
                    items.add(MultiSelectItem(e.key, e.value.getName()));
                  }
                  return MultiSelectDialog<String>(
                    listType: MultiSelectListType.CHIP,
                    title: Text("Select Lists"),
                    items: items,
                    initialValue: listsToReview,
                    onConfirm: (List<String> values) async {
                      await sharedPreferences.setStringList(
                          KEY_LISTS_TO_REVIEW, values);
                      setState(() {
                        updateRevisionSettings();
                      });
                    },
                  );
                },
              );
            },
            description: Text(
              listsToReview
                  .map((key) => WordList.getNameFromKey(key))
                  .toList()
                  .join(", "),
              textAlign: TextAlign.center,
            ),
          ),
        ]);

    List<AbstractSettingsSection?> sections = [
      sourceListSection,
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
                  updateRevisionSettings();
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
                  updateRevisionSettings();
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
                                          color: settingsBackgroundColor),
                                      color: settingsBackgroundColor,
                                      borderRadius: BorderRadius.circular(20)),
                                ),
                                onPressed: () async {
                                  await sharedPreferences.setInt(
                                      KEY_REVISION_STRATEGY, e.index);
                                  setState(() {
                                    updateRevisionSettings();
                                  });
                                  Navigator.of(context).pop();
                                },
                              ))
                          .toList(),
                    );
                    return dialog;
                  });
            },
            description: Text(
              revisionStrategy.pretty,
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
                        sharedPreferences.setStringList(KEY_FLASHCARD_REGIONS,
                            values.map((e) => e.toString()).toList());
                        updateRevisionSettings();
                      });
                    },
                  );
                },
              );
            },
          ),
          SettingsTile.switchTile(
            title: Text(
              UNKNOWN_REGIONS_TEXT,
              style: TextStyle(fontSize: 15),
            ),
            initialValue: useUnknownRegionSigns,
            onToggle: (newValue) {
              onPrefSwitch(KEY_USE_UNKNOWN_REGION_SIGNS, newValue,
                  influencesStartValidity: false);
              updateRevisionSettings();
            },
            description: Text(
              regionsString,
              textAlign: TextAlign.center,
            ),
          ),
          SettingsTile.switchTile(
            title: Text(
              ONLY_ONE_CARD_TEXT,
              style: TextStyle(fontSize: 15),
            ),
            initialValue:
                sharedPreferences.getBool(KEY_ONE_CARD_PER_WORD) ?? false,
            onToggle: (newValue) {
              onPrefSwitch(KEY_ONE_CARD_PER_WORD, newValue,
                  influencesStartValidity: false);
              updateRevisionSettings();
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
          MaterialPageRoute(
              builder: (context) => FlashcardsPage(
                    di: dolphinInformation,
                    revisionStrategy: revisionStrategy,
                    existingReviews: existingReviews,
                  )),
        );
        setState(() {
          existingReviews = readReviews();
        });
        print("Pop: Read ${existingReviews!.length} reviews from storage");
        updateRevisionSettings();
      };
    }

    Widget body = Container(
      child: Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
              padding: EdgeInsets.only(top: 30, bottom: 10),
              child: TextButton(
                key: ValueKey("startButton"),
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
                  minimumSize: MaterialStateProperty.all<Size>(Size(120, 50)),
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
      color: settingsBackgroundColor,
    );

    List<Widget> actions = [
      buildActionButton(
        context,
        Icon(Icons.timeline),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => RevisionHistoryPage()),
          );
        },
      ),
      buildActionButton(
        context,
        Icon(Icons.help),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => getFlashcardsHelpPage()),
          );
        },
      )
    ];

    return TopLevelScaffold(body: body, title: "Revision", actions: actions);
  }
}

class LifecycleEventHandler extends WidgetsBindingObserver {
  final AsyncCallback resumeCallBack;

  LifecycleEventHandler({
    required this.resumeCallBack,
  });

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        await resumeCallBack();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        break;
    }
  }
}
