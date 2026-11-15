# Plan: chat, calls and meetings like WhatsApp

**Status:** proposed on 15 November 2026, waiting for Clement's go-ahead.
Nothing below is built yet except where it says "we have". **No release
until Clement says so.**

Based on a study of nine Flutter apps Clement shared:

- **Chat:** WhatsUp (MIT), lets_chat, Whatsapp-Clone-Flutter (BSD-3),
  Chatteroom, chat-app.
- **Meetings:** jitsi-meet-flutter-sdk (Apache-2.0), flutter-meet (100ms),
  the Zoom Video SDK quickstart, SkyTalk.

## Ground rules

- **Keep our stack.** Supabase (database, files, sign-in), LiveKit (calls)
  and our offline outbox stay. All nine reference apps run on Firebase,
  Jitsi, 100ms or Zoom.
  - Screens and widgets can be adapted.
  - Data code is rewritten for Supabase.
  - Every change that can be made without signal goes through the outbox.
- **Licences.** We copy code only from MIT or BSD sources, and keep their
  copyright notice in the file:
  - WhatsUp (MIT) and Whatsapp-Clone-Flutter (BSD-3): code may be adapted.
  - lets_chat, Chatteroom, chat-app, flutter-meet and SkyTalk have no
    licence, so we take ideas only.
  - jitsi-meet-flutter-sdk (Apache-2.0) is used as a feature checklist,
    not as a dependency.
- **Look.** Keep the liquid-glass look in burgundy, rose and blue. The
  behaviour copies WhatsApp; the colours stay ours.
- **Every phase** ends with:
  - a database test for each migration;
  - app tests;
  - a browser test of the main flow;
  - CHANGELOG, API.md and the system guide updated.
- **Releases.** Phones get a phase only when Clement says to release.

## Where we start (what we have)

| Area | We have | Missing |
|---|---|---|
| Messages | Text, photos, voice notes, files, job-card links, replies with swipe-to-reply, reactions, @mentions, copy, unsend | Delivered and read ticks, forward, delete for me, edit, star |
| Chat screen | Typing…, Online, unread divider, date labels in the list | Scroll-to-bottom button with count, date chips in the chat, emoji keyboard, search in a chat |
| Media | Photo send (one at a time), file send | Several photos with captions, compression, full-screen viewer, video messages, in-app camera, download progress |
| Chats list | Search, pinned chats, unread counts, groups and direct chats | Mute, archive, group info (members, add or remove, media), last seen |
| Calls | Voice and video in any chat; Calling, then Ringing; timer from answer; 45-second no-answer; speaker; flip; reactions; captions; pin a person; screen share from a desktop browser | Back minimises, picture-in-picture, Android screen share, raise hand, grid view, chair controls, low-data mode, call list |
| Meetings | Scheduled with M- code, agenda, reminders, live captions, AI minutes in the department format | Check before joining, add people to a running call, meetings list, who spoke how long |

---

## Phase 1: chat feels like WhatsApp (done 15 November 2026, not yet released)

Goal: someone used to WhatsApp finds nothing missing in everyday chatting.

### 1.1 Ticks: sent, delivered, read
- **What people see:**
  - a clock while the message waits to send (we have this);
  - ✓ when the server has it;
  - ✓✓ grey when it reached the other phone;
  - ✓✓ blue when they have read it.
- **In groups:** two ticks only when everyone has it. Long-press → **Info**
  lists "Read by" and "Delivered to" with times.
- **How:**
  - New table `message_receipts (message_id, user_id, delivered_at,
    read_at)`.
  - A phone marks *delivered* when the message arrives (realtime or push,
    also in the background).
  - It marks *read* when the bubble is on screen (WhatsUp marks seen per
    message with a visibility detector). We already keep
    `conversation_members.last_read_at`; this adds per-message detail.
- **Source:** WhatsUp `MessageStatus` (pending, sent, delivered, seen),
  `message_cards.dart`, `chat.dart markAsSeen`.
- **Tests:** SQL test for receipts and who may write them; widget test for
  each tick state.

### 1.2 Hold-to-record voice notes
- Hold the mic to record.
- Slide left to cancel ("◀ Slide to cancel").
- Slide up to lock, so you can let go and keep recording.
- While locked: pause, resume, delete or send.
- A live waveform and timer while recording.
- **Playback:** waveform with drag-to-seek and 1×, 1.5×, 2× speed.
- **Source:** WhatsUp `voice_recorder.dart`, `chat_mic.dart`,
  `recording_visualiser.dart`, `AttachedVoiceViewer`. We keep our recorder
  package and voice upload (outbox).

### 1.3 Moving around a chat
- **Down-arrow button** at the bottom right when scrolled up, with the
  number of new messages; tap to jump to the newest (WhatsUp
  `scroll_btn.dart`).
- **Date chips** between messages: Today, Yesterday, then weekday, then
  date. They float at the top while scrolling (WhatsUp `chat_date.dart`).
- **Unread banner:** opening a chat jumps to "N unread messages". We have
  the divider; add the jump.
- **Tap a reply** to scroll to the original message and flash it.

### 1.4 Photos: several at once, with captions, compressed
- **Picker:** choose several photos (up to 30). A preview screen shows each
  one large with a caption box, a strip to switch between them, and
  remove (WhatsUp `attachment_sender.dart`).
- **Compression** before upload, done in the background:
  - longest side 1600 px, about 70% quality;
  - an **HD** toggle sends the original.

  This saves data on site networks (WhatsUp `compression_service.dart`).
- **Upload:** each photo is its own message through the outbox, so nothing
  is lost without signal.

### 1.5 Full-screen viewer
- Tap a photo: full screen, pinch to zoom, swipe between all photos in the
  chat, save to phone, share, forward, and "show in chat".
- **Source:** WhatsUp `attachment_viewer.dart`, `ImageViewer`.

### 1.6 Forward, delete for me, copy
- **Forward:** long-press one or more messages → **Forward** → pick chats
  (several allowed). Forwarded messages show "Forwarded". Photos, files
  and voice notes are forwarded without uploading again (same file path).
- **Delete for me:** hides a message only for you.
- **Delete for everyone:** we have this as unsend; keep "This message was
  deleted" in its place.
- **Select mode:** long-press, then tap more messages; the top bar shows
  Reply, Forward, Copy, Delete and Star.
- **How:**
  - `messages.forwarded_from`;
  - a `message_hidden (message_id, user_id)` table for delete for me;
  - new functions `fn_forward_messages` and `fn_hide_message`.

### 1.7 Emoji keyboard
- An emoji button in the message box opens an emoji panel in place of the
  keyboard. Back closes the panel first (WhatsUp `emoji_picker.dart`, uses
  `emoji_picker_flutter`).

### Phase 1 done when
- A test group of three phones and one browser shows correct ticks within
  a few seconds, including after a phone was offline.
- Voice notes can be cancelled and locked; ten photos can be sent with
  captions without signal and arrive later.
- Database, app and browser tests pass.

---

## Phase 2: calls and meetings

Goal: calls behave like WhatsApp, and meetings can show a screen from a
phone.

### 2.1 Back minimises the call (#38)
- Back or ⌄ **minimises** the call; only the red button hangs up.
- A green bar on every screen: **"Tap to return to call · 03:12 · 🎤"**.
- On Android, leaving the app shows a **picture-in-picture** window with
  the speaker's video. The ongoing-call notification stays, with
  Hang up.
- **How:** move the LiveKit room, timers, captions, reactions and the
  heartbeat out of `call_screen.dart` into an app-wide call controller
  (Riverpod). The call screen and the bar both read from it.

### 2.2 Screen sharing from phones (must have)
- **Android:** Share screen → Android asks for screen-capture permission →
  "You are sharing your screen · Stop" bar on the phone, and a
  notification while sharing. Share with or without phone sound.
- **Viewers** see the shared screen large and can pinch-zoom and pan
  (drawings, PLC screens, photos).
- **Web:** we have this on desktop; it stays.
- **iPhone:** needs a separate broadcast extension, and we have no iPhones
  in use, so later.
- **How:** LiveKit `setScreenShareEnabled` on Android with a media
  projection foreground service, plus the manifest permissions. Turn the
  share button on for Android (today it only shows on wide web screens).
- **Source:** flutter-meet (`startScreenShare`), Jitsi
  `toggleScreenShare` / `screenShareToggled`.

### 2.3 Raise hand
- ✋ button; a hand shows on your tile and in the participants list.
- The chair sees hands in the order raised and can lower one or all.
- **How:** a LiveKit participant attribute (no database needed); the order
  comes from the time it was raised.
- **Source:** Jitsi `raise-hand`, flutter-meet `raiseLocalPeerHand`.

### 2.4 Grid view and speaker view
- **Speaker view** (default): the speaker or shared screen large, with a
  strip of the others.
- **Grid view:** everyone in tiles, 2×2 to 3×3 per page, swipe for more.
- Your own video is a small window you can drag to any corner
  (flutter-meet uses `draggable_widget`).

### 2.5 Chair controls
- The meeting chair (or the caller in a group call) can:
  - mute one person or **mute everyone**;
  - **remove** someone;
  - **end the meeting for all**.
- Muted people get "The chair muted you"; they unmute themselves (like
  Zoom).
- **How:** a new edge function `call-admin` using LiveKit's server API. It
  checks the caller is the chair, through `_can_run_meeting`.
- **Source:** Jitsi `kick-out`, flutter-meet `endRoom`.

### 2.6 Low-data mode for mine sites
- A signal-strength icon on each tile (LiveKit connection quality).
- When the signal is poor, the app offers **"Switch to audio only"**.
- Settings: video quality Auto, Low (360p) or Audio only.
- **Source:** Jitsi `audio-only` and resolution flags.

### 2.7 Calls list
- A **Calls** section in Chat: incoming, outgoing and missed calls, with
  ↙ ↗ arrows, time and length.
- Tap to call back.
- A missed-call badge.
- **How:** we already store calls and participants (`fn_conversation_calls`
  per chat); add one list across chats.
- **Source:** lets_chat `calls_screen.dart` (idea).

### Phase 2 done when
- An Android phone shares its screen to a meeting watched on another phone
  and on a browser.
- Back keeps a call going with the bar and picture-in-picture.
- The chair can mute everyone and remove one person.
- Raise hand and grid view work with four people.

---

## Phase 3: chat extras

### 3.1 Video messages
- Record or pick a short video (up to 2 minutes, compressed to 720p).
- It plays in the chat with a thumbnail and length; full-screen player
  with seek.
- **Source:** WhatsUp `VideoViewer`, lets_chat `video_player_item.dart`.

### 3.2 In-app camera
- The camera button in the message box opens our own camera:
  - tap for a photo, hold for video;
  - flash, flip;
  - the last photos from the gallery in a strip.
- **Source:** Whatsapp-Clone `CameraScreen.dart` (BSD) and WhatsUp
  `camera.dart` (MIT), `gallery.dart`.

### 3.3 Download progress
- Large files and videos show a progress ring with cancel; downloaded
  files open from the phone without downloading again.
- **Source:** WhatsUp `progress_btn.dart`, `download_service.dart`.

### 3.4 Group info
- Tap the group name to open:
  - name, picture and description (admins edit);
  - **members** with roles, and add or remove (admins);
  - **media, files and links** shared;
  - mute, leave group.
- Site groups stay automatic; members follow roles.

### 3.5 Last seen, mute, archive
- **Last seen today at 14:05** when someone is not online (stored when the
  app closes).
- **Mute a chat:** 8 hours, 1 week or always. No push or sound, but the
  unread count stays.
- **Archive a chat:** hidden from the list until a new message arrives.

### 3.6 Search, star, edit
- **Search in a chat:** matches highlighted, with up and down to jump.
- **Star messages:** a starred list in each chat and across all chats.
- **Edit** your own text messages within 15 minutes; they show "edited".

---

## Phase 4: meeting extras

### 4.1 Before joining
- A small screen before joining:
  - camera preview and microphone level;
  - join with microphone off or camera off;
  - choose speaker or earpiece.
- **Source:** Jitsi `prejoinpage`.

### 4.2 Add people to a running call
- From the participants list, **Add people** rings them (phones) or
  notifies them (web).
- **Source:** Jitsi `add-people`.

### 4.3 Meetings list
- One place for upcoming and past meetings from all chats: date, chat,
  chair, minutes status. Open the minutes or join from there.
- **Source:** SkyTalk "recent meets" (idea).

### 4.4 Who spoke how long
- At the end of a meeting, the minutes show talking time per person, from
  the live captions we already collect.
- **Source:** Jitsi `speakerstats`.

### Later or optional
- **Background blur** on video.
- **Join by link for outsiders** (contractors, clients) in the browser,
  with a time limit, a waiting room and chair approval (Jitsi `lobby`).
- **Recording:** LiveKit can record, but it costs storage; transcripts and
  minutes cover most needs.

---

## Not adopting

| Feature | Seen in | Why not |
|---|---|---|
| Phone-number sign-in, contact matching | WhatsUp, lets_chat, Chatteroom | Admin creates accounts; everyone in the department can chat |
| Status / stories | lets_chat | Not useful for work; site updates go in the daily report |
| GIFs (Giphy) | lets_chat | Needs an outside key, adds nothing to the job |
| Agora, ZegoCloud, 100ms, Zoom, Jitsi calls | lets_chat, Chatteroom, flutter-meet, Zoom quickstart, SkyTalk | LiveKit already works on phones and web; others are paid per minute or have no web |
| Sending pushes from the phone | WhatsUp | Insecure (uses the receiver's device token from the phone); ours sends from the server |
| Isar local database | WhatsUp | We already store data on the phone (drift) |
| Breakout rooms, live streaming | Jitsi | Not needed for department meetings |
| Google sign-in | SkyTalk | Not our sign-in |

## Order and size (rough)

| Phase | Main pieces | Database changes | Size |
|---|---|---|---|
| 1 | Ticks, voice notes, scrolling, photos, viewer, forward, emoji | Receipts, hidden messages, forwarded from | Large |
| 2 | Minimise and PiP, Android screen share, raise hand, grid, chair controls, low data, calls list | None for the call; one edge function | Large |
| 3 | Video messages, camera, downloads, group info, last seen, mute, archive, search, star, edit | Mutes, archive, stars, edits, last seen | Medium |
| 4 | Pre-join, add people, meetings list, talking time | Small | Small |

Each phase is built, tested and pushed to the web. Phones get it only when
Clement says to release.
