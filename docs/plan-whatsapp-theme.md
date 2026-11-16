# Plan: WhatsApp look for chat

Chat gets WhatsApp's look, copied from the reference screenshots
(15 November 2026): WhatsApp for iPhone on phones (standard and the
liquid-glass version) and WhatsApp Desktop/Web on computers. Everything else
in the app keeps the burgundy liquid glass. Chat leaves the menu bar and opens
from a floating button in the bottom-right corner of every screen.

Nothing here is started yet. Each phase is built, pushed to the web and
released to phones only when Clement says.

---

## Phase A: Chat behind a floating button (done 15 November 2026, not yet released)

Goal: chat is one tap away from anywhere, like a messenger bubble, and the
menu bar has room for work screens.

- **Floating chat button**, bottom right on every screen (phones and web):
  green WhatsApp-style circle with the chat icon and a red badge with the
  number of unread chats (mentions shown with @).
  - Sits above the bottom bar on phones and clear of the ➕ New button.
  - Hidden on chat screens themselves, in calls and on the sign-in pages.
  - Long-press (phones) or hover (web): the last three chats, to jump
    straight in.
- **Remove Chat from the menu bar**: the Chat tab goes from the phone's
  bottom bar and the computer's side menu. Home, Jobs, Menu stay (Menu
  moves up one place).
- **Where it opens**
  - Phones: the chat list full screen, sliding up; back or ⌄ returns to
    the screen you were on.
  - Web/computer: the WhatsApp Desktop layout over the app (Phase F), with
    a close button back to where you were.
- Links that open a chat (notifications, `/chat/<id>`, shared records) keep
  working; the old `/chat` address opens the chat list.
- The green "Tap to return to call" bar stays as it is.

## Phase B: Chat theme foundation (done 15 November 2026, not yet released; chat follows the phone's light or dark)

Goal: one place that holds WhatsApp's look so every chat screen matches.

- Complete `ChatColors` for light and dark from the screenshots:
  - light: white lists, beige `#EFEAE2` wallpaper, bubbles `#D9FDD3` and
    white, green `#1DAB61`/`#25D366`, grey text `#667781`, chip green
    `#D9FDD3` with dark green text;
  - dark: **true black** lists (`#000000`/`#0B141A`), wallpaper with
    doodles, bubbles `#005C4B` and `#1F2C34`, chips `#103529`.
- **Light or dark in chat**: follows the phone's setting, as WhatsApp does
  (the rest of the app keeps its own setting). *Decision needed.*
- Text sizes and weights as in WhatsApp (large bold titles, 17 pt names,
  15 pt previews), outline icons (Cupertino) with the selected one filled.
- The electrical doodle wallpaper stays (WhatsApp's own doodles are
  WhatsApp's art, so we keep ours in the same style).

## Phase C: Chat list (phones) (done 15 November 2026, not yet released)

From the iPhone screenshots:

- **Top**: "…" (menu: Starred, Archived, Settings, Select chats), camera
  (straight to the chat camera), green ➕ (new chat or group); large
  **Chats** title that shrinks into the bar when scrolling.
- **Search** in a rounded grey field ("Search").
- **Filter chips**: All, Unread, Favourites, Groups; the chosen one light
  green with green text. *Favourites* needs a new flag per person and chat
  (small migration).
- **Archived** row at the top with the count, as on WhatsApp.
- **Rows**: round avatar (group picture when set), name in bold, last
  message in grey with ticks and small icons (📷 photo, 🎥 video, 🎤 0:02,
  📄 file), time on the right — green when unread — with a green unread
  circle, @ for mentions, a pin for pinned chats, "typing…" in green; thin
  dividers starting after the avatar.
- **Footer**: a small line in place of WhatsApp's "end-to-end encrypted",
  e.g. "Messages stay inside Bravura Electrical".
- **Inside chat, a bottom bar** like WhatsApp's: Chats, Calls, Meetings,
  Starred (our four), with outline icons and the selected one filled.

## Phase D: Inside a chat (phones) (done 16 November 2026, not yet released)

From the iPhone chat screenshots:

- **Header**: back with the unread count, avatar, name, status (online,
  last seen, "tap here for group info", members), video and voice call
  buttons.
- **Bubbles**: tails on the first bubble of a run, time and ticks inside
  the bottom-right corner, "Edited" before the time, sender name in colour
  above group messages (one colour per person), reactions as a small pill
  under the bubble.
- **Date pills** in the middle (Today, Yesterday, Thu 16 Mar) and **notices**
  as yellow or grey centred cards (meeting scheduled, call started,
  someone added).
- **Photos** large with the caption below and the time on the photo;
  **files** as a card with icon, name, size and type, and **Open** /
  **Save as…** buttons.
- **Message bar**: ➕ on the left, rounded field with the sticker/emoji
  button inside, camera and microphone on the right (send replaces the
  microphone when typing).
- **➕ sheet** as WhatsApp's grid of round coloured icons: Photos, Camera,
  Video, Document, From Documents, Tag a record (job card, equipment, tool),
  Location, and later Poll. *Location and Poll are new features; decision
  needed.*

## Phase E: Liquid glass for chat (iOS 26 style) (done 16 November 2026, not yet released)

From the last two iPhone images:

- The chat list and chat bottom bar become **frosted floating glass**: a
  floating rounded tab bar, a glass search field, glass chips.
- In a chat, the header is a **floating glass pill** (back, avatar and
  name, call buttons) over the wallpaper, and the message bar is a floating
  glass bar.
- Optional glass rows in the chat list (as in the concept image).
  *Decision needed: standard WhatsApp (Phases C–D) or the glass version as
  the default; the other can be a switch in Settings → Appearance.*

## Phase F: Web and computer layout (done 16 November 2026, not yet released)

From the WhatsApp Desktop screenshots:

- **Three parts**:
  - a thin **left rail**: Chats (with unread badge), Calls, Meetings,
    Starred, Archived; Settings and your photo at the bottom;
  - the **chat list** (Phase C look in the desktop size: title with new
    chat and filter buttons, search, chips, rows, the selected chat in light
    grey);
  - the **open chat**: white header with avatar, name and "online" or the
    members' names, video, call and search buttons; wallpaper; bubbles;
    rounded floating message bar with ➕, emoji and microphone.
- Opens over the app from the floating button (Phase A) and fills the
  window; Esc or ✕ closes it.
- Right-click on a chat or message for its menu, as on Desktop.

## Phase G: Calls in the WhatsApp look (done 16 November 2026, not yet released)

From the Desktop call screenshots (and WhatsApp for iPhone calls):

- **Web**: the call opens as a dark floating window over the chat (drag,
  resize, full screen) with the other person large, your picture in a
  corner, and a bottom bar: camera and microphone each with a device
  chooser, reactions, raise hand, share screen, add people, more, and the
  red hang-up.
- **Incoming call on web**: a small dark card at the top right with photo,
  name, "Video call", **Accept** (green), decline (red) and "…".
- **Phones**: the call screen in WhatsApp's dark style with the same
  buttons; keeps minimise, picture-in-picture and everything from the
  calls phases.

## Phase H: Finish (guide updated 16 November 2026; release waits for Clement)

- Contrast and size checks for both themes, big text and screen readers.
- Update the PDF guide, CHANGELOG and API.md (favourites flag if added).
- Release to phones when Clement says.

---

## Decisions (answered 16 November 2026: chat follows the phone; Location and Poll added; soft avatars everywhere)

1. Chat light/dark: follow the phone (like WhatsApp) or the app's setting?
2. Standard WhatsApp look or the liquid-glass version as the default?
3. Location and polls in the ➕ sheet: add them (new features) or leave out?
4. The four tabs inside chat: Chats, Calls, Meetings, Starred, or others?
5. The footer line in the chat list: wording.

## Order and size (rough)

| Phase | What | Database | Size |
|---|---|---|---|
| A | Floating chat button, Chat out of the menu bar | None | Small |
| B | Chat colours, type and icons | None | Small |
| C | Chat list like iPhone WhatsApp | Favourites flag | Medium |
| D | Inside a chat like iPhone WhatsApp | None (Location, Poll if chosen) | Medium |
| E | Liquid-glass version | None | Medium |
| F | Web/computer three-part layout | None | Medium |
| G | Calls in the WhatsApp look | None | Medium |
| H | Checks, guide, release | None | Small |
