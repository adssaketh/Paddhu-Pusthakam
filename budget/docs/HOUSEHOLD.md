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
- **Per-person data stays personal:** settings, the Ping review queue and learned corrections. Loans and fixed deposits are personal too, until their owner chooses to share them (next section).
- **Everyone / Mine:** "Everyone" (default in a household) shows shared transactions only, so totals match on every phone. "Mine" shows everything you own, including private and personal ones.
- **Offline:** transactions waiting to be uploaded are kept on the phone and go out when the connection returns. If you edit the same transaction on two of your own phones, the later edit wins.
- **Leaving or being removed:** you keep your own transactions as personal ones on this phone; other members' rows, their placeholder accounts and the loans and deposits they shared with you are removed from it.

## Sharing loans and fixed deposits

Loans and fixed deposits are private by default. The person who owns one decides who in the household sees it.

- **Who sees it:** in the loan terms page or the fixed deposit form, just before Save, the owner ticks the members who may see the item. Nothing is shared until the owner does this, and an empty list makes the item private again.
- **Who edits it:** a "Members can edit" switch (off by default) lets the ticked members change the item's details. Only the owner deletes an item or changes who sees it or whether others may edit.
- **What viewers see:** shared items from other people are listed in a separate **Household** section (Fixed deposits page, and the loans page), with a detail page. They are never added to the viewer's net worth or loan totals. A viewer's loan card shows "Paid so far": the owner's phone works out ticked instalments plus the payments recorded as transactions and sends the figure (`paidSoFar` in the loan payload) whenever it changes, so it is as of the owner's last sync. Nothing a viewer sends is used for it. If the owner's phone is on an older version that sends no figure, only the ticked instalments are counted.
- **Which loans:** only instalment loans (the ones with a loan terms page) can be shared. A plain loan without terms has nothing a viewer could see.
- **Linked transactions:** loan payments and deposit interest keep their own transaction privacy. Sharing an item does not share them.
- **Where it is stored:** one Firestore document per item, `households/{h}/sharedItems/{kind-ownerUid-localId}`, with `kind` (`loan` or `fd`), `ownerUid`, `localId`, `visibleTo` (uids besides the owner, at most 7), `membersCanEdit`, `_u` (milliseconds, newer wins) and `payload`. The owner's phone keeps who sees what in the setting `householdSharedOwn` and what was last sent in `householdSharedUploaded` (this phone only). Other people's items are kept on a phone in `householdSharedCopies`, which is not copied between one person's own phones.
- **Two queries:** each phone listens to `sharedItems where ownerUid == me` (to pick up member edits) and `sharedItems where visibleTo array-contains me` (what others share with me). The rules allow exactly these two. Taking somebody out of `visibleTo` makes the document drop out of their query, and their phone removes its copy.
- **Offline:** an item waits to be sent while its newest change (the item itself or the sharing choice) is newer than what was last sent. A member's edit needs the connection: offline it is refused with "Nothing was saved", not queued.
- **Edit flow and conflicts:** last writer wins, by `_u`. A member's edit is one Firestore transaction that writes only `payload` and `_u`, and is refused when the server copy is newer than the one the member started from. The owner's phone applies the member's edit to the real loan or deposit (newest `_u` wins; the owner's account stays, and a loan's amount is recalculated from its terms, never taken from the server). A newer edit on the owner's phone beats a member's earlier edit, and a member's later edit beats the owner's older one.
- **Leaving:** before a member's membership is deleted, the app deletes that person's shared items from the server (the rules only let a member delete them). If that fails, the person stays in the household and is told so, so nothing is left behind.
- **Being removed:** the household owner cannot list another person's shared items (the read rule only lets the item's owner and the people it is shared with read it), so a removed person's items stay on the server but are hidden from everyone, because their owner is no longer a member. They are deleted when that person joins the household again.
- **Handing over ownership:** items belong to the person who made them. Nothing changes for them; the new household owner does not become the owner of other people's items.

## Handing over ownership

Household page, tap a member, **Make owner**. The old owner becomes a normal member and the old invite code is cancelled; the new owner makes a new code. The change is one atomic write, so the household never has two owners or none. The new owner's phone picks up the role right away.

The owner cannot leave without handing over first. Deleting a household is not supported.

## Firebase console setup

1. Firebase console, project `cashew-saketh`, **Build > Authentication**: Google sign-in is on.
2. **Build > Firestore Database**: create the database if it does not exist (production mode).
3. **Firestore Database > Rules**: replace the rules with the contents of `budget/firestore.rules` and press **Publish**. On a phone the editor cuts long pastes off, so paste in pieces and check that the last line reads `}`.
4. **Indexes:** none needed. All queries use equality filters only (`array-contains` on `visibleTo` needs no composite index).
5. Test with two Google accounts: create a household on one, join with the code on the other, add a transaction on each.
6. Test sharing: on phone A open a fixed deposit, tick phone B's person, switch "Members can edit" on, Save. On phone B open Fixed deposits > Household > the deposit > Edit, change the note, Save. On phone A the note changes within a few seconds. Repeat with a loan (tick an instalment). Then switch editing off on A and check that B's Edit button is gone.

The "paid so far" figure needs no rules change: the rules only require the payload to be a map.

The rules have to be published again after the ownership-transfer update (the `households` update rule changed) and after the loans and deposits sharing update (the new `sharedItems` rule). One publish of the current file covers both.

## Tests

Run from the `budget` folder (no packages needed):

```
dart run test/household_visibility_test.dart
dart run test/household_members_test.dart
dart run test/household_ownership_test.dart
dart run test/household_migration_test.dart
dart run test/household_sharing_test.dart
dart run test/household_sharing_copies_test.dart
dart run test/household_sharing_edits_test.dart
```

They cover the merge logic, visibility, edit and delete rules, hidden accounts, who-added-it labels, spending per member, the member limit, ownership transfer, the schema 47/48 migration (checked against `drift_schemas/` and `tables.dart`), and for shared loans and deposits: who sees and edits an item, the copies kept on a viewer's phone, member edits and how the owner applies them, and what is cleared when somebody leaves or joins again. The Firestore rules are not covered by these tests; test them with the two-account checks above.

## Known gaps

- A placeholder account's total is only the sum of that member's shared transactions, not their real balance.
- Drive device sync still copies placeholder accounts and other members' rows between one person's own phones.
- A category rename can be lost if another phone merely used the category later (last writer wins).
- A granted delete, or a delete on one phone versus an edit on another phone, is not reconciled.
- Spending by member has no tap-through to the search page.
- The member tag is not shown on the transaction detail page.
- Shared items: a member's edit made while offline is refused, not queued.
- Shared items: if the owner's phone applies a member's edit while the owner has that loan or deposit open in an editor, the open editor does not refresh.
- Shared items: the viewer's Household list does not mark items they may edit (only the detail page shows the Edit button).
- Shared items: plain loans without terms cannot be shared.
- Shared items: the "paid so far" figure of a loan is only as new as the owner's last sync, and a viewer's own tick of an instalment shows in it only after the owner's phone has applied the edit and sent a new figure.
- Shared items: the items of a removed person stay on the server (hidden) until that person joins again, because the household owner cannot list them.
