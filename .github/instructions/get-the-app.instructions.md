---
applyTo: "lib/features/notifications/suggest_mobile_dialog.dart"
description: "The web client's get-the-app dialog: what a computer and a phone browser show, where each link goes, and the store badge rules it follows."
---

# Get the App (web)

Notifications reach a learner through the app, so where the app asks for notification permission, the web client asks the learner to get the app instead. This doc decides what that dialog shows and where its links go.

## The experience

1. On web, a learner opens notification settings or a course page. If the browser is not already allowed to show Pangea Chat notifications, and they have not seen the dialog in the last 30 days, it opens.
2. On a computer, the dialog shows its title and a line saying the app is needed for notifications. Below them are a QR code, the words "Scan with your phone's camera", and the link written out as pangea.chat/app. The App Store and Google Play badges follow.
3. On a phone or tablet browser, the dialog shows the illustration, the title and line, and only that device's store badge.
4. Both end with "Then sign in to the app with this account." and a "Got it!" button.

## Decisions

- The QR code and the written link go to pangea.chat/app, which sends a phone to its own store. It is the one get-the-app link for QR codes and emails ([website navigation doc](https://github.com/pangeachat/website/blob/main/.github/instructions/navigation.instructions.md#get-the-app-link-app)). Re-decided by Will.
- On a computer the QR code leads, in the illustration's place, because a store link opened on a computer cannot install the app on the phone. The badges stay as a fallback. Unassigned.
- A phone or tablet gets no QR code, because it cannot scan its own screen. It gets only its own store's badge. An iPad counts as a tablet even when Safari says it is a Mac. Unassigned.
- The badges are the stores' official artwork, unaltered and in English, as Apple and Google require. The App Store badge comes first, both are the same height, with a quarter of that height between them. They link straight to each listing: pangea.chat/app would send a computer to the homepage. Unassigned.
- The QR code is dark on white in both themes, because phone cameras read an inverted code unreliably. Engineer.
- The sign-in line is there because installing the app alone does not bring this account's notifications to the phone. Unassigned.
