import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
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
          return SettingsList(
              contentPadding: EdgeInsets.only(top: 10),
              sections: [
                SettingsSection(
                  title: Text('Cache'),
                  tiles: [
                    SettingsTile.switchTile(
                      title: Text('Cache videos'),
                      initialValue: prefs.getBool(KEY_SHOULD_CACHE)!,
                      onToggle: onChangeShouldCache,
                    ),
                    SettingsTile.navigation(
                        title: Text(
                          'Drop cache',
                          textAlign: TextAlign.center,
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
                ),
                SettingsSection(title: Text('Data'), tiles: [
                  SettingsTile.navigation(
                    title: Text(
                      'Check for new dictionary data',
                      textAlign: TextAlign.center,
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
                ]),
                SettingsSection(title: Text('Legal'), tiles: [
                  SettingsTile.navigation(
                    title: Text(
                      'See legal information',
                      textAlign: TextAlign.center,
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
                ]),
              ]);
        });
  }
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
