import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

List<Widget> buildLegalInformationChildren() {
  const bodyStyle = TextStyle(fontSize: 15, height: 1.55);
  return [
    const Text(
        "The Auslan information (including videos) displayed in this app is taken from Auslan Signbank (Johnston, T., & Cassidy, S. (2008). Auslan Signbank (auslan.org.au) Sydney: Macquarie University & Trevor Johnston).",
        style: bodyStyle),
    const SizedBox(height: 14),
    const Text(
        "Only some of the information relating to each sign that is found on Auslan Signbank is displayed here in this app. Please consult Auslan Signbank to see the information displayed as originally intended and endorsed by the author. There is a link to Auslan Signbank on each definition.",
        style: bodyStyle),
    const SizedBox(height: 18),
    // Builder so we can read the theme for the link colour.
    Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () async {
            final uri =
                Uri.parse('https://creativecommons.org/licenses/by-nc-nd/4.0/');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Text(
            "This content is licensed under Creative Commons BY-NC-ND 4.0.",
            style: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      );
    }),
  ];
}
