import 'package:flutter/material.dart';

class RevisionHistoryPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {

  int numCardsRemembered = answers.values
      .where(
        (element) => element.rating == Rating.Good,
      )
      .length;
  int numCardsForgotten = answers.values
      .where(
        (element) => element.rating == Rating.Hard,
      )
      .length;
  int totalAnswers = answers.length;
  double rememberRate = numCardsRemembered / totalAnswers;

  Widget getText(String s, {bool bold = false}) {
    FontWeight? weight;
    if (bold) {
      weight = FontWeight.w600;
    }
    return Padding(
      child: Text(s, style: TextStyle(fontSize: 16, fontWeight: weight)),
      padding: EdgeInsets.only(top: 30),
    );
  }

  return Scaffold(
        appBar: AppBar(
          title: Text("Revision Progress"),
        ),
        body: Column(
    children: [
      Row(children: [
        Padding(
          padding: EdgeInsets.only(left: 60),
        ),
        Column(
          children: [
            getText("Success Rate:", bold: true),
            getText("Total Cards:", bold: true),
            getText("Successful Cards:", bold: true),
            getText("Incorrect Cards:", bold: true)
          ],
          crossAxisAlignment: CrossAxisAlignment.start,
        ),
        Spacer(),
        Column(
          children: [
            getText("${(rememberRate * 100).toStringAsFixed(1)}%"),
            getText("$totalAnswers"),
            getText("$numCardsRemembered"),
            getText("$numCardsForgotten"),
          ],
          crossAxisAlignment: CrossAxisAlignment.end,
        ),
        Padding(
          padding: EdgeInsets.only(left: 60),
        ),
      ], mainAxisAlignment: MainAxisAlignment.center),
      Padding(padding: EdgeInsets.only(bottom: 250))
    ],
    mainAxisAlignment: MainAxisAlignment.center,
  ));

  }
}

}
