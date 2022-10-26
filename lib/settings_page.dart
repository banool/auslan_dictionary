import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:launch_review/launch_review.dart';
import 'package:mailto/mailto.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';
import 'flashcards_logic.dart';
import 'globals.dart';
import 'settings_help_page.dart';
import 'top_level_scaffold.dart';

class SettingsPage extends StatefulWidget {
  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  void onChangeShouldCache(bool newValue) {
    setState(() {
      sharedPreferences.setBool(KEY_SHOULD_CACHE, newValue);
    });
  }

  void onChangeHideFlashcardsFeature(bool newValue) {
    setState(() {
      sharedPreferences.setBool(KEY_HIDE_FLASHCARDS_FEATURE, newValue);
      //myHomePageController.toggleFlashcards(newValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    String appStoreTileString;
    if (Platform.isAndroid) {
      appStoreTileString = 'Give feedback on Play Store';
    } else if (Platform.isIOS) {
      appStoreTileString = 'Give feedback on App Store';
    } else {
      appStoreTileString = "N/A";
    }

    EdgeInsetsDirectional margin =
        EdgeInsetsDirectional.only(start: 15, end: 15, top: 10, bottom: 10);

    SettingsSection? featuresSection;
    if (enableFlashcardsKnob && !getShouldUseHorizontalLayout(context)) {
      featuresSection = SettingsSection(
        title: Text('Revision'),
        tiles: [
          SettingsTile.switchTile(
            title: Text(
              'Hide revision feature',
              style: TextStyle(fontSize: 15),
            ),
            initialValue:
                sharedPreferences.getBool(KEY_HIDE_FLASHCARDS_FEATURE) ?? false,
            onToggle: onChangeHideFlashcardsFeature,
          ),
          SettingsTile.navigation(
              title: getText(
                'Delete all revision progress',
              ),
              trailing: Container(),
              onPressed: (BuildContext context) async {
                bool confirmed = await confirmAlert(
                    context,
                    Text("This will delete all your review progress from all "
                        "time for both the spaced repetition and random review "
                        "strategies. Your lists (including favourites) will not "
                        "be affected. Are you 100% sure you want to do this?"));
                if (confirmed) {
                  await writeReviews([], [], force: true);
                  await sharedPreferences.setInt(KEY_RANDOM_REVIEWS_COUNTER, 0);
                  await sharedPreferences.remove(KEY_FIRST_RANDOM_REVIEW);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text("All review progress deleted"),
                    backgroundColor: MAIN_COLOR,
                  ));
                }
              }),
        ],
        margin: margin,
      );
    }

    List<AbstractSettingsSection?> sections = [
      SettingsSection(
        title: Text('Cache'),
        tiles: [
          SettingsTile.switchTile(
            title: Text(
              'Cache videos',
              style: TextStyle(fontSize: 15),
            ),
            initialValue: sharedPreferences.getBool(KEY_SHOULD_CACHE) ?? true,
            onToggle: onChangeShouldCache,
          ),
          SettingsTile.navigation(
              title: getText(
                'Drop cache',
              ),
              trailing: Container(),
              onPressed: (BuildContext context) async {
                await videoCacheManager.emptyCache();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text("Cache dropped"),
                  backgroundColor: MAIN_COLOR,
                ));
              }),
        ],
        margin: margin,
      ),
      SettingsSection(
        title: Text('Data'),
        tiles: [
          SettingsTile.navigation(
            title: getText(
              'Check for new dictionary data',
            ),
            trailing: Container(),
            onPressed: (BuildContext context) async {
              bool updated = await getNewData(true);
              String message;
              if (updated) {
                wordsGlobal = await loadWords();
                updateKeyedWordsGlobal();
                message = "Successfully updated dictionary data";
              } else {
                message = "Data is already up to date";
              }
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(message), backgroundColor: MAIN_COLOR));
            },
          )
        ],
        margin: margin,
      ),
      featuresSection,
      SettingsSection(
        title: Text('Legal'),
        tiles: [
          SettingsTile.navigation(
            title: getText(
              'See legal information',
            ),
            trailing: Container(),
            onPressed: (BuildContext context) async {
              return await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LegalInformationPage(),
                  ));
            },
          )
        ],
        margin: margin,
      ),
      SettingsSection(
          title: Text('Help'),
          tiles: [
            SettingsTile.navigation(
              title: getText(
                'Report issue with dictionary data',
              ),
              trailing: Container(),
              onPressed: (BuildContext context) async {
                var url = 'https://www.auslan.org.au/feedback/';
                await launch(url, forceSafariVC: false);
              },
            ),
            SettingsTile.navigation(
              title: getText(
                'Report issue with app (GitHub)',
              ),
              trailing: Container(),
              onPressed: (BuildContext context) async {
                var url = 'https://github.com/banool/auslan_dictionary/issues';
                await launch(url, forceSafariVC: false);
              },
            ),
            SettingsTile.navigation(
              title: getText(
                'Report issue with app (Email)',
              ),
              trailing: Container(),
              onPressed: (BuildContext context) async {
                var mailto = Mailto(
                    to: ['danielporteous1@gmail.com'],
                    subject: 'Issue with Auslan Dictionary',
                    body:
                        'Please tell me what device you are using and describe the issue in detail. Thanks!');
                String url = "$mailto";
                if (await canLaunch(url)) {
                  await launch(url);
                } else {
                  print('Could not launch $url');
                }
              },
            ),
            SettingsTile.navigation(
              title: getText(appStoreTileString),
              trailing: Container(),
              onPressed: (BuildContext context) async {
                await LaunchReview.launch(
                    iOSAppId: "1531368368", writeReview: true);
              },
            ),
          ],
          margin: margin),
    ];

    List<AbstractSettingsSection> nonNullSections = [];
    for (AbstractSettingsSection? section in sections) {
      if (section != null) {
        nonNullSections.add(section);
      }
    }

    Widget body = SettingsList(sections: nonNullSections);

    List<Widget> actions = [
      buildActionButton(
        context,
        Icon(Icons.help),
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => getSettingsHelpPage()),
          );
        },
      )
    ];

    return TopLevelScaffold(body: body, title: "Search", actions: actions);
  }
}

Text getText(String s, {bool larger = false, Color? color}) {
  double size = 15;
  if (larger) {
    size = 18;
  }
  return Text(
    s,
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: size, color: color),
  );
}

class LegalInformationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(APP_NAME),
        ),
        body: Padding(
            padding: EdgeInsets.only(bottom: 10, left: 20, right: 32, top: 20),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Text(
                      "The Auslan information (including videos) displayed in this app is taken from Auslan Signbank (Johnston, T., & Cassidy, S. (2008). Auslan Signbank (auslan.org.au) Sydney: Macquarie University & Trevor Johnston).\n",
                      textAlign: TextAlign.center),
                  Text(
                      "Only some of the information relating to each sign that is found on Auslan Signbank is displayed here in this app. Please consult Auslan Signbank to see the information displayed as originally intended and endorsed by the author. There is a link to Auslan Signbank on each definition.",
                      textAlign: TextAlign.center),
                  Container(
                    padding: EdgeInsets.only(top: 10),
                  ),
                  TextButton(
                    child: Text(
                        "This content is licensed under\nCreative Commons BY-NC-ND 4.0.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: MAIN_COLOR)),
                    onPressed: () async {
                      const url =
                          'https://creativecommons.org/licenses/by-nc-nd/4.0/';
                      await launch(url, forceSafariVC: false);
                    },
                  ),
                ])));
  }
}
