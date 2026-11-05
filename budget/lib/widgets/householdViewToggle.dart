import 'package:budget/struct/householdView.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';

/// "Everyone | Mine" switch for transaction lists and totals. Shows nothing outside a household.
class HouseholdViewToggle extends StatelessWidget {
  const HouseholdViewToggle({super.key});

  @override
  Widget build(BuildContext context) {
    if (!householdViewFilterActive) return const SizedBox.shrink();
    final bool mine = householdViewIsMine;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
          start: 20, end: 20, top: 4, bottom: 10),
      child: Row(
        children: [
          ChoiceChip(
            label: TextFont(text: "Everyone", fontSize: 14),
            selected: !mine,
            onSelected: (_) => saveHouseholdView(kHouseholdViewEveryone),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: TextFont(text: "Mine", fontSize: 14),
            selected: mine,
            onSelected: (_) => saveHouseholdView(kHouseholdViewMine),
          ),
        ],
      ),
    );
  }
}
