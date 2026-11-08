# Play Store: internal testing

What is ready, and what only the account owner can do. Issue #17.

## Ready in the repository

- **Signed app bundle.** A release (Actions → App → Run workflow with a
  version, e.g. `v0.1.3`) builds `bravura-electrical-<version>.aab` next to
  the APK and attaches both to the GitHub release. It is signed with the
  same key as the APK (`ANDROID_KEYSTORE_BASE64` and friends). Use Play App
  Signing and upload this key as the **upload key**.
- **Privacy policy:** <https://electrical-department-lake.vercel.app/privacy.html>
  (`app/web/privacy.html`, published with the web app).
- **App id:** the `prod` flavour's application id in
  `app/android/app/build.gradle.kts`.

## Only you can do

1. A Google Play developer account. It costs a one-time 25 US dollars; it is
   the one step that is not free. Skip Play entirely if the APK from GitHub
   releases (or Firebase App Distribution) is enough for the team.
2. Create the app in Play Console (free app, not a game), turn on Play App
   Signing, and upload the first `.aab` to **Testing → Internal testing**.
3. Add testers by email (up to 100), then share the opt-in link.

## Listing text

- **Name:** Bravura Electrical
- **Short description (80):** Job cards, tools, inventory, safety and team chat for the electrical department.
- **Full description:**

  The Bravura Electrical Department app runs the electrical team's daily
  work across all sites.

  - Job cards from fault report to verified closure, with photos, work log
    and safety checks
  - Tools register with signed issue forms, calibration certificates and
    who has what
  - Inventory: receive, issue, take back, count; material requests and
    purchases; project BOQs
  - Projects, calendar and the weekly roster with standby
  - Daily reports, checklists, SOPs and drawings with read-and-sign
  - Team chat with calls, meetings and minutes
  - Works without signal and sends everything when back online

  For Bravura staff and contractors with an account from the department.

- **Category:** Business. **Contact email:** the department's admin address.
- **Screenshots:** phone screenshots of Home, a job card, Inventory and Chat
  (at least 2; 1080×1920 works).

## Data safety form

| Question | Answer |
|---|---|
| Collects or shares user data | Collects; shares with no one (Supabase, Firebase and Vercel are service providers) |
| Encrypted in transit | Yes |
| Users can ask for deletion | Yes, through the department's admin |
| Personal info | Name, email, phone (optional): app functionality, account management |
| Photos and files | Yes: app functionality |
| Messages | In-app messages: app functionality |
| App activity | Actions in the app (work records): app functionality |
| App info and performance | Crash logs, diagnostics: analytics (fixing errors) |
| Device or other IDs | Push token: app functionality |
| Location, contacts, financial, health | Not collected |
