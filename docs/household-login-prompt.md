# Prompt: Household login for Paddhu Pusthakam

You are working on **Paddhu Pusthakam** (github.com/adssaketh/Paddhu-Pusthakam), my personal Flutter fork of Cashew. The app lives in `budget/`. Add **household login**: several people in my home each sign in with their own Google account and share one household budget, while every entry still shows who made it.

Read the code first, then give me a short plan and wait for my go-ahead before you write code. Ask me only about the open decisions at the bottom.

## What the repo does today (checked)

- **Sign-in:** Google only. `signInGoogle()` in `lib/widgets/accountAndBackup.dart` asks for profile, email and Drive app-data scopes. `lib/struct/firebaseAuthGlobal.dart` turns that into a Firebase Auth credential and stores `currentUserEmail` in settings. The Firebase project is `budget-app-flutter`.
- **Device sync:** `lib/struct/syncClient.dart` uploads one `sync-<clientID>.sqlite` per device to the signed-in person's own Google Drive `appDataFolder`, and other devices merge it. This is private to one Google account, so two different people can never sync through it. It is for one person with many devices.
- **Settings merge:** `lib/struct/settingsMerge.dart` merges settings, loans, fixed deposits and card dues item by item, using an `_u` (updated-at) stamp and a `{"_d": true}` delete marker. Login and device settings such as `currentUserEmail` and `hasSignedIn` are deliberately not synced.
- **Existing sharing:** `lib/struct/shareBudget.dart` and `lib/pages/sharedBudgetSettings.dart` share a single Budget through Firestore (`budgets/{sharedKey}` with a `members` array of emails and a `transactions` subcollection, plus an offline queue `sendTransactionsToServerQueue`). It does not cover accounts, categories, loans, fixed deposits or settings. Transactions already carry `transactionOriginalOwnerEmail`, `sharedKey` and `sharedDateUpdated` (`lib/database/tables.dart`).
- **Local data:** Drift/SQLite (`lib/database/tables.dart`, `schema_versions.dart`, `drift_schemas/`). There is no per-person field on accounts (wallets), and no per-person display name beyond one global `username` setting.
- **Ping:** Ping hands bank SMS to this app through `PingInboxProvider.java`, `lib/struct/pingInbox.dart`, `pingImport.dart` and `pingSave.dart`. These are saved on the phone that received them.
- **No Firestore security rules file exists in the repo.** The repo is public and `google-services.json` is committed, so rules are the only real protection.

## What I want

1. **Household:** one person creates a household. Others join by invite using their Google email. A person belongs to one household. There are two roles: owner (invites, removes, deletes household) and member.
2. **Login stays Google.** Do not add another auth provider. Reuse the existing Google and Firebase Auth flow.
3. **One shared ledger.** Transactions, accounts, categories, budgets, loans, fixed deposits and card dues are shared across members and sync automatically between phones, as I asked for earlier. Use Firestore for this. Reuse the `_u` / `_d` item-merge approach from `settingsMerge.dart` so offline edits on two phones merge instead of overwriting, and keep an offline queue like the existing one.
4. **Who did it:** every transaction records the member who created it and shows their name or initial in lists, details, filters and search. Add a "by member" filter and a per-member spending view. Imports from Ping are tagged with the signed-in member on that phone, and are shared with the household like any other transaction.
5. **Everything is visible to everyone.** Any transaction a member adds, edits or deletes (by hand, from a widget, or imported from Ping) must appear on every other member's phone, and so must the accounts it belongs to. There is no private account and no per-transaction privacy setting. A transaction is pushed to the household as soon as it is saved, and if the phone is offline it waits in a queue and goes out when the connection returns, so nothing is lost. Do not hold back any member's data from the household.
6. **Per-person settings stay per-person** (theme, notifications, lock, language). Household-level settings (currency, categories, budgets) are shared.
7. **Leave and remove:** a member who leaves keeps a local copy of what they entered. Removed members lose cloud access immediately. The owner can transfer ownership.
8. **Do not break single-user mode.** If I never create a household, the app behaves exactly as now. Existing Drive backup and device sync keep working for personal use. Add a one-time, safe migration that lets me turn my existing data into the first household.

## Security (required, not optional)

- Write `firestore.rules` and add it to the repo, with `firebase.json` pointing at it. Rules must check membership, so only members of a household can read or write its documents, only the owner can change membership, and every member can read all household transactions and accounts.
- Never trust the client for membership. Invites should be keyed by email and accepted only by the signed-in account with that verified email.
- Do not put secrets or keystore values anywhere. Explain what I must configure in the Firebase console (Firestore enabled, rules deployed, indexes) as numbered steps.

## Engineering constraints

- Flutter 3.19.6 (pinned in `.github/workflows/build-apk.yml`). Do not bump Flutter or add packages unless needed, and say why.
- Drift schema change: add a proper migration in `tables.dart`, update `schema_versions.dart` and `drift_schemas/`, and regenerate `tables.g.dart` if required.
- Follow existing patterns for settings, popups, bottom sheets and text widgets. Keep the existing look, including Google Sans and the logo on the home page.
- Raise the build number in `budget/pubspec.yaml` (currently `5.4.3+421`) for the release.
- Add tests in `budget/test/` for the merge logic, ownership and visibility rules, and the migration. Pure-Dart logic (like `settingsMerge.dart`) should stay pure so `dart run` can check it.
- Build in small steps I can review: (1) data model + migration, (2) household create/invite/join, (3) shared sync, (4) "by member" UI, (5) offline queue and conflict handling for transactions added on several phones at once, (6) rules + docs. Tell me which files each step changed.

## Open decisions: ask me these before step 1

1. Should a member's existing personal data be merged into the household, or should each person start empty?
2. Can any member edit or delete another member's transaction, or only their own (owner can edit all)?
3. Should members see each other's names from their Google profile, or a nickname they set in the app?
4. Is a maximum household size needed (default: 6)?
