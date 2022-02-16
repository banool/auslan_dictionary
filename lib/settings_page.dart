import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:launch_review/launch_review.dart';
import 'package:mailto/mailto.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';

class SettingsPage extends StatefulWidget {
  SettingsPage({Key? key}) : super(key: key);

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  Future<void>? initStateAsyncFuture;

  late SharedPreferences prefs;

  @override
  void initState() {
    initStateAsyncFuture = initStateAsync();
    super.initState();
  }

  Future<void> initStateAsync() async {
    prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(KEY_SHOULD_CACHE) == null) {
      prefs.setBool(KEY_SHOULD_CACHE, true);
    }
  }

  void onChangeShouldCache(bool newValue) {
    setState(() {
      prefs.setBool(KEY_SHOULD_CACHE, newValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: initStateAsyncFuture,
        builder: (context, snapshot) {
          var waitingWidget = Padding(
              padding: EdgeInsets.only(top: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [CircularProgressIndicator()],
              ));
          if (snapshot.connectionState != ConnectionState.done) {
            return waitingWidget;
          }

          String appStoreTileString;
          if (Platform.isAndroid) {
            appStoreTileString = 'Give feedback on Play Store';
          } else if (Platform.isIOS) {
            appStoreTileString = 'Give feedback on App Store';
          } else {
            appStoreTileString = "N/A";
          }

          EdgeInsetsDirectional margin = EdgeInsetsDirectional.only(
              start: 15, end: 15, top: 10, bottom: 10);

          return SettingsList(sections: [
            SettingsSection(
              title: Text('Cache'),
              tiles: [
                SettingsTile.switchTile(
                  title: Text(
                    'Cache videos',
                    style: TextStyle(fontSize: 14),
                  ),
                  initialValue: prefs.getBool(KEY_SHOULD_CACHE)!,
                  onToggle: onChangeShouldCache,
                ),
                SettingsTile.navigation(
                    title: getText(
                      'Drop cache',
                    ),
                    trailing: Container(),
                    onPressed: (BuildContext context) async {
                      await DefaultCacheManager().emptyCache();
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
                      var url =
                          'https://github.com/banool/auslan_dictionary/issues';
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
          ]);
        });
  }
}

Text getText(String s) {
  return Text(
    s,
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: 14),
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
                  FlatButton(
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
