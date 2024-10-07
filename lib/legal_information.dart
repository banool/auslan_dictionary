import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

List<Widget> buildLegalInformationChildren() {
  return [
    const Text(
        "The Auslan information (including videos) displayed in this app is taken from Auslan Signbank (Johnston, T., & Cassidy, S. (2008). Auslan Signbank (auslan.org.au) Sydney: Macquarie University & Trevor Johnston).\n",
        textAlign: TextAlign.center),
    const Text(
        "Only some of the information relating to each sign that is found on Auslan Signbank is displayed here in this app. Please consult Auslan Signbank to see the information displayed as originally intended and endorsed by the author. There is a link to Auslan Signbank on each definition.",
        textAlign: TextAlign.center),
    Container(
      padding: const EdgeInsets.only(top: 10),
    ),
    TextButton(
      child: Text(
          "This content is licensed under\nCreative Commons BY-NC-ND 4.0.",
          textAlign: TextAlign.center,
          style: TextStyle()),
      onPressed: () async {
        const url = 'https://creativecommons.org/licenses/by-nc-nd/4.0/';
        await launch(url, forceSafariVC: false);
      },
    ),
  ];
}
