import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/householdMembers.dart';
import 'package:budget/struct/householdService.dart';
import 'package:budget/struct/householdSpending.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Who spent how much in a month: the household's shared spending split by member.
class HouseholdSpendingPage extends StatefulWidget {
  const HouseholdSpendingPage({Key? key}) : super(key: key);

  @override
  State<HouseholdSpendingPage> createState() => _HouseholdSpendingPageState();
}

class _HouseholdSpendingPageState extends State<HouseholdSpendingPage> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  int _loadId = 0;
  List<HouseholdMemberSpending> _rows = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final int loadId = ++_loadId;
    if (!mounted) return;
    setState(() => _loading = true);
    final AllWallets allWallets =
        Provider.of<AllWallets>(context, listen: false);
    List<HouseholdMemberSpending> rows = [];
    try {
      rows = await getHouseholdSpendingByMember(
        allWallets,
        _month,
        DateTime(_month.year, _month.month + 1),
      );
    } catch (e) {
      print("Household spending: ${e.toString()}");
    }
    if (!mounted || loadId != _loadId) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _moveMonth(int by) {
    _month = DateTime(_month.year, _month.month + by);
    _load();
  }

  String get _monthLabel {
    final String name = localizedMonthNames.length >= 12
        ? localizedMonthNames[_month.month - 1].capitalizeFirst
        : _month.month.toString();
    return name + " " + _month.year.toString();
  }

  Widget _monthSwitcher() {
    final DateTime now = DateTime.now();
    final bool isCurrentMonth =
        _month.year == now.year && _month.month == now.month;
    return Padding(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 15, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => _moveMonth(-1),
          ),
          TextFont(
            text: _monthLabel,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: isCurrentMonth ? null : () => _moveMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _memberRow(
      HouseholdMemberSpending row, double grandTotal, AllWallets allWallets) {
    final bool isMe = row.uid == currentHouseholdUserUid;
    final double share = grandTotal <= 0 ? 0 : row.total / grandTotal;
    final Color color = Colors.primaries[
        householdMemberColorIndex(row.uid, Colors.primaries.length)];
    return Padding(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 25, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFont(
                  text: householdMemberName(row.uid) + (isMe ? " (you)" : ""),
                  fontSize: 17,
                  maxLines: 1,
                ),
              ),
              TextFont(
                text: convertToMoney(allWallets, row.total),
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 10,
              color: color,
              backgroundColor: color.withOpacity(0.15),
            ),
          ),
          const SizedBox(height: 4),
          TextFont(
            text: (share * 100).toStringAsFixed(0) +
                "% of the household, " +
                row.count.toString() +
                (row.count == 1 ? " transaction" : " transactions"),
            fontSize: 13,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final double grandTotal =
        _rows.fold<double>(0, (double sum, row) => sum + row.total);

    Widget content;
    if (_loading) {
      content = const Padding(
        padding: EdgeInsetsDirectional.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_rows.isEmpty) {
      content = const Padding(
        padding: EdgeInsetsDirectional.symmetric(horizontal: 25, vertical: 40),
        child: TextFont(
          text: "No shared spending in this month yet.",
          fontSize: 16,
          textAlign: TextAlign.center,
          maxLines: 3,
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 25, vertical: 6),
            child: TextFont(
              text: "Household total  " + convertToMoney(allWallets, grandTotal),
              fontSize: 15,
              maxLines: 2,
            ),
          ),
          for (final HouseholdMemberSpending row in _rows)
            _memberRow(row, grandTotal, allWallets),
          const SizedBox(height: 30),
        ],
      );
    }

    return PageFramework(
      horizontalPaddingConstrained: true,
      dragDownToDismiss: true,
      expandedHeight: 56,
      title: "Spending by member",
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _monthSwitcher(),
              content,
            ],
          ),
        ),
      ],
    );
  }
}
