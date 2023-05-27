import 'dart:math';

import 'package:dolphinsr_dart/dolphinsr_dart.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'flashcards_logic.dart';
import 'globals.dart';
import 'types.dart';

class RevisionHistoryPage extends StatefulWidget {
  RevisionHistoryPage({Key? key}) : super(key: key);

  @override
  _RevisionHistoryPageState createState() => _RevisionHistoryPageState();
}

class _RevisionHistoryPageState extends State<RevisionHistoryPage> {
  late RevisionStrategy revisionStrategy;

  @override
  void initState() {
    super.initState();
    revisionStrategy = loadRevisionStrategy();
  }

  @override
  Widget build(BuildContext context) {
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

    Widget getRevisionStrategyButton(RevisionStrategy rs) {
      return Container(
          child: TextButton(
        onPressed: () {
          setState(() {
            revisionStrategy = rs;
          });
        },
        style: ButtonStyle(
            padding: MaterialStateProperty.all(EdgeInsets.all(10)),
            backgroundColor: MaterialStateProperty.all(settingsBackgroundColor),
            foregroundColor: MaterialStateProperty.all(rs == revisionStrategy
                ? MAIN_COLOR
                : Color.fromARGB(255, 145, 145, 145)),
            minimumSize: MaterialStateProperty.all<Size>(Size(140, 35)),
            side: MaterialStateProperty.all(BorderSide(
                color: Color.fromARGB(110, 185, 185, 185), width: 1.5))),
        child: Text(rs.pretty),
      ));
    }

    String getDatetimeString(DateTime dt) {
      return "${dt.year.toString()}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    }

    List<Widget> leftColumn;
    List<Widget> rightColumn;

    Widget disclaimer = Container();

    switch (revisionStrategy) {
      case RevisionStrategy.SpacedRepetition:
        List<Review> reviewsRaw = readReviews();

        List<Review> reviews = [];
        for (Review r in reviewsRaw) {
          // Skip incomplete reviews.
          if (r.master == null || r.rating == null || r.ts == null) {
            print("Skipping incomplete review: $r");
            continue;
          }
          reviews.add(r);
        }

        int totalAnswers = reviews.length;
        int numCardsRemembered = 0;
        int numCardsForgotten = 0;
        double rememberRate = 0;
        Set<String> uniqueMasters = {};
        int longestStreakDays = 0;

        if (reviews.length > 0) {
          reviews.sort((a, b) {
            return a.ts!.compareTo(b.ts!);
          });

          DateTime earliestDateTime = reviews[0].ts!;

          DateTime startOfStreak = earliestDateTime;
          DateTime previousDateTime = earliestDateTime;

          int i = 1;
          for (Review r in reviews) {
            // Build up unique words.
            uniqueMasters.add(r.master!);

            // Count up success / failure based on the ratings.
            switch (r.rating!) {
              case Rating.Good:
              case Rating.Easy:
                numCardsRemembered += 1;
                break;
              case Rating.Hard:
              case Rating.Again:
                numCardsForgotten += 1;
                break;
            }

            // Determine the longest streak.
            int daysSincePreviousDateTime =
                (r.ts!.difference(previousDateTime).inHours / 24).round();
            if (daysSincePreviousDateTime > 1 || i == reviews.length) {
              // If we're just in this block because we've hit the end of
              // the list, use this datetime if it has been 1 day since the
              // previous one. Otherwise just use the previous one, since in
              // any other case, we're here because the current datetime was
              // more than 1 day after the previous one, breaking the streak.
              DateTime comparison;
              if (daysSincePreviousDateTime == 1) {
                comparison = r.ts!;
              } else {
                comparison = previousDateTime;
              }
              int daysSinceStartOfStreak =
                  (comparison.difference(startOfStreak).inHours / 24).round();
              longestStreakDays =
                  max(longestStreakDays, daysSinceStartOfStreak);
              startOfStreak = r.ts!;
            }
            previousDateTime = r.ts!;
            i += 1;
          }

          rememberRate = numCardsRemembered / totalAnswers;

          String dateString = getDatetimeString(earliestDateTime);
          disclaimer = Text("Stats collected since $dateString");
        }

        String days = longestStreakDays == 1 ? "day" : "days";

        leftColumn = [
          getText("Total Reviews:", bold: true),
          getText("Success Rate:", bold: true),
          getText("Successful Cards:", bold: true),
          getText("Unsuccessful Cards:", bold: true),
          getText("Unique Words:", bold: true),
          getText("Longest Streak:", bold: true),
        ];
        rightColumn = [
          getText("$totalAnswers"),
          getText("${(rememberRate * 100).toStringAsFixed(1)}%"),
          getText("$numCardsRemembered"),
          getText("$numCardsForgotten"),
          getText("${uniqueMasters.length}"),
          getText("$longestStreakDays $days"),
        ];
        break;
      case RevisionStrategy.Random:
        int totalRandomReviews =
            sharedPreferences.getInt(KEY_RANDOM_REVIEWS_COUNTER) ?? 0;
        leftColumn = [
          getText("Total Reviews:", bold: true),
        ];
        rightColumn = [getText("$totalRandomReviews")];
        int? firstStartedTrackingRandomReviews =
            sharedPreferences.getInt(KEY_FIRST_RANDOM_REVIEW);
        if (firstStartedTrackingRandomReviews != null) {
          var dt = DateTime.fromMillisecondsSinceEpoch(
                  firstStartedTrackingRandomReviews * 1000)
              .toLocal();
          String dateString = getDatetimeString(dt);
          disclaimer = Text("Stats collected since $dateString");
        }
        break;
    }

    return Scaffold(
        appBar: AppBar(
          title: Text("Revision Progress"),
          centerTitle: true,
        ),
        body: CustomScrollView(slivers: [
          SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 50),
                  ),
                  Text("Revision strategy to show stats for"),
                  Padding(
                    padding: EdgeInsets.only(top: 15),
                  ),
                  Row(children: [
                    getRevisionStrategyButton(
                        RevisionStrategy.SpacedRepetition),
                    Padding(
                      padding: EdgeInsets.only(left: 20),
                    ),
                    getRevisionStrategyButton(RevisionStrategy.Random),
                  ], mainAxisAlignment: MainAxisAlignment.center),
                  Padding(
                    padding: EdgeInsets.only(top: 30),
                  ),
                  Divider(
                    height: 20,
                    thickness: 2,
                    indent: 20,
                    endIndent: 20,
                  ),
                  Row(children: [
                    Padding(
                      padding: EdgeInsets.only(left: 60),
                    ),
                    Column(
                      children: leftColumn,
                      crossAxisAlignment: CrossAxisAlignment.start,
                    ),
                    Spacer(),
                    Column(
                      children: rightColumn,
                      crossAxisAlignment: CrossAxisAlignment.end,
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 60),
                    ),
                  ], mainAxisAlignment: MainAxisAlignment.center),
                  Expanded(child: Container()),
                  disclaimer,
                  Padding(
                    padding: EdgeInsets.only(bottom: 50),
                  )
                ],
                mainAxisAlignment: MainAxisAlignment.start,
              ))
        ]));
  }
}
