# Pen Me In: phone test guide (v1.0.0)

Install: download `app-arm64-v8a-release.apk`, then My Files › Downloads › tap it › Install.

1. **First run.** Allow the microphone and notifications, download the speech model (~40 MB, Wi-Fi), and tap **Allow** under "Keep running".
   Also set Settings › Apps › Pen Me In › Battery › **Unrestricted**.
2. **Typed note.** Tap **+ New note**, type something and go back. It should appear at the top with a ⌨ icon.
   Open it again to test editing, copying, sharing and deleting. Swiping left also deletes, with Undo.
3. **In-app mic (listening off).** Tap the red mic and say "buy milk". Stop talking: it should save after about 2.5 s.
   Then try "call mum done", which should save straight away.
4. **Listening on.** Flip the big switch. A notification should read "Listening for 'pen me in'".
5. **Locked test (the main one).** Lock the phone, wait about 30 s, then say "**pen me in**".
   Wait for the buzz and say your note. Then either pause or say "done".
   You should feel a second buzz, and the notification should show "1 note taken · last: …".
6. Say "pen me in … **cancel note**". Nothing should be saved.
7. Open the app. Locked-screen notes should show with a 🎙 icon.
8. **Long-run test.** Leave it listening for an hour with the screen off, then try step 5 again. This checks that the phone doesn't kill it.

If something fails, tell me which step, what the notification said, and whether you felt a buzz.

Known limits:
- The small offline model can mishear words. Speak clearly; notes are easy to fix by editing.
- Words spoken before the first buzz are not included.
- While listening is on, the mic is in use, so other apps that need the mic (calls, voice recorder) may conflict. Turn listening off first.
