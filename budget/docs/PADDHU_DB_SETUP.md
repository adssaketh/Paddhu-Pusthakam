# Paddhu Pusthakam: database setup (Cloud Firestore)

## 1. Create the database
1. Go to console.firebase.google.com and open (or create) your Paddhu project.
2. Build > Firestore Database > Create database. Choose **Production mode** and a region near you (asia-south1 Mumbai or asia-south2 Delhi).
3. Build > Authentication > Get started > enable **Email/Password** (and Google if you want).

## 2. Connect the Flutter app
```
dart pub global activate flutterfire_cli
flutterfire configure
flutter pub add firebase_core firebase_auth cloud_firestore rxdart
```
In `main()`:
```dart
WidgetsFlutterBinding.ensureInitialized();
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```
Offline cache is on by default on Android, so the app works offline and syncs when back online.

## 3. Publish the rules and indexes
Console: Firestore > Rules, paste `firestore.rules`, Publish.
Or CLI:
```
npm i -g firebase-tools
firebase login
firebase init firestore   # point it at the two files in this folder
firebase deploy --only firestore:rules,firestore:indexes
```
Indexes take a few minutes to build. If a query errors with a link, open it to create the index.

## 4. Structure
```
users/{uid}                      profile, householdId           (owner only)
  accounts/{id}                  real bank/card details          (owner only)
  settings/prefs                 font, theme, preferences        (owner only)
  loans/{id}, deposits/{id}      loans and fixed deposits        (owner only)
  pending/{id}                   Ping SMS review queue           (owner only)
  learned/{merchantKey}          learned corrections             (owner only)
invites/{code}                   householdId, ownerId
households/{h}                   ownerId, showBalances
  members/{uid}                  role, canDelete, displayName
  balances/{accId}               ownerId, balance                (hidden unless showBalances)
  categories/{id}                shared categories
  transactions/{id}              everyone sees; isPrivate = owner only
```

## 5. Notes
- Loans and fixed deposits are private to each person. If you want them shared with the household, tell me and I'll move them.
- Ping: use a hash of the SMS (sender + body + timestamp) as the transaction id, so a re-sent SMS never creates a duplicate.
- Test the rules in Firestore > Rules > Rules Playground before relying on them.
