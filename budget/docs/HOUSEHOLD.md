# Household login

Several people each sign in with their own Google account and share one household budget. Every shared transaction shows who added it. If nobody creates or joins a household, the app behaves exactly as before.

## How it works

- **Sign-in:** Google only (the existing flow). A household is stored in Cloud Firestore and protected by `budget/firestore.rules`.
- **Roles:** one owner and members. The owner makes invite codes, removes members, switches account balances on or off for members, lets a member delete other people's transactions, and can hand the household to another member.
- **Invites:** 8-character codes (one active code at a time; making a new one cancels the old one). A household has up to 8 people. The limit is checked when the owner makes a code, because Firestore rules cannot count members.
- **Privacy:**
  - Accounts are private to their owner. Other members only see them if the owner switches "show balances" on.
  - Everyone in the household sees all shared transactions.
  - A transaction can be marked private: it is hidden from others and left out of household totals.
  - Members edit and delete only their own transactions, unless the owner allows deleting others'.
- **Your existing data:** after creating or joining, the app asks whether to share existing transactions or keep them private on this phone.
- **Per-person data stays personal:** settings, loans, fixed deposits, the Ping review queue and learned corrections.
- **Everyone / Mine:** "Everyone" (default in a household) shows shared transactions only, so totals match on every phone. "Mine" shows everything you own, including private and personal ones.
- **Offline:** transactions waiting to be uploaded are kept on the phone and go out when the connection returns. If you edit the same transaction on two of your own phones, the later edit wins.
- **Leaving or being removed:** you keep your own transactions as personal ones on this phone; other members' rows and their placeholder accounts are removed from it.

## Handing over ownership

Household page, tap a member, **Make owner**. The old owner becomes a normal member and the old invite code is cancelled; the new owner makes a new code. The change is one atomic write, so the household never has two owners or none. The new owner's phone picks up the role right away.

The owner cannot leave without handing over first. Deleting a household is not supported.

## Firebase console setup

1. Firebase console, project `cashew-saketh`, **Build > Authentication**: Google sign-in is on.
2. **Build > Firestore Database**: create the database if it does not exist (production mode).
3. **Firestore Database > Rules**: replace the rules with the contents of `budget/firestore.rules` and press **Publish**. On a phone the editor cuts long pastes off, so paste in pieces (the rules are short; paste from the top and check the last line reads `}`).
4. **Indexes:** none needed. All queries use equality filters only.
5. Test with two Google accounts: create a household on one, join with the code on the other, add a transaction on each.

After the ownership-transfer update, step 3 has to be repeated once: the `households` update rule changed.

## Tests

Run from the `budget` folder (no packages needed):

```
dart run test/household_visibility_test.dart
dart run test/household_members_test.dart
dart run test/household_ownership_test.dart
dart run test/household_migration_test.dart
```

They cover the merge logic, visibility, edit and delete rules, hidden accounts, who-added-it labels, spending per member, the member limit, ownership transfer, and the schema 47/48 migration (checked against `drift_schemas/` and `tables.dart`). The Firestore rules are not covered by these tests; test them with the two-account check above.

## Known gaps

- A placeholder account's total is only the sum of that member's shared transactions, not their real balance.
- Drive device sync still copies placeholder accounts and other members' rows between one person's own phones.
- A category rename can be lost if another phone merely used the category later (last writer wins).
- A granted delete, or a delete on one phone versus an edit on another phone, is not reconciled.
- Spending by member has no tap-through to the search page.
- The member tag is not shown on the transaction detail page.
