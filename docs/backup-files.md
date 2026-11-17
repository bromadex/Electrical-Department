# Backing up uploaded files

The nightly **Database backup** workflow keeps the database. Photos, SOPs,
drawings, certificates, signatures and chat files live in Supabase Storage,
and its **Copy uploaded files** job copies them, encrypted, to storage you
choose. Until it is set up the job only warns and does nothing.

It uses [rclone](https://rclone.org), which can write to almost anything.
The free options that suit us:

| Destination | Free space | Notes |
| --- | --- | --- |
| Google Drive | 15 GB (shared with the account's mail) | easiest; use a department account |
| Cloudflare R2 | 10 GB | needs a card on file; no download fees |
| Backblaze B2 | 10 GB | no card needed |
| OneDrive (company Microsoft 365) | usually 1 TB | **what we use**; see below |

## One-time setup (on any computer, about 15 minutes)

1. **A key for Supabase Storage.** Supabase dashboard → Project Settings →
   Storage → **S3 access keys** → New access key. Note the endpoint, access
   key and secret.
2. **Install rclone** (`rclone.org/install`) and run `rclone config`:
   - New remote **`supabase`**: type `s3`, provider `Other`, the access key
     and secret from step 1, endpoint from step 1, region as shown there.
   - New remote **`dest`**: your destination (for Google Drive choose
     `drive` and sign in with the department account).
   - New remote **`files`**: type `crypt`, remote `dest:bravura-files`,
     filename encryption `standard`, and a password (and salt) of your own.
     **Keep that password with the BACKUP_PASSPHRASE**: without it the
     copies cannot be opened.
3. Check it: `rclone lsd supabase:` lists the buckets; `rclone copy
   supabase:documents files:documents` copies one.
4. In GitHub: Settings → Secrets and variables → Actions → New repository
   secret **`RCLONE_CONFIG`**, and paste the whole contents of the file
   `rclone config file` shows.
5. Run **Database backup** once by hand (Actions → Database backup → Run
   workflow). The first run copies everything; later nights only what is new.

## OneDrive with the company account

We back up to OneDrive for Business with a company Microsoft 365 account.
Use a shared department mailbox if IT can give one, so the backup does not
depend on one person's account. Follow the setup above, with these
changes in step 2.

**The `dest` remote (OneDrive):**

1. `rclone config` → `n` (new remote) → name **`dest`**.
2. Storage type: **`onedrive`** (Microsoft OneDrive).
3. `client_id` and `client_secret`: leave empty (press Enter).
4. Region: **`global`** (Microsoft Cloud Global).
5. Edit advanced config: **No**.
6. Use web browser to automatically authenticate: **Yes**. A browser
   opens: sign in with the **company email** and accept.
   - If it says *"Need admin approval"*, the company's Microsoft 365 admin
     has to allow rclone once (in Microsoft Entra ID → Enterprise
     applications → rclone, *Grant admin consent*), or approve the request
     that page sends. Then run this step again.
7. Type of connection: **`onedrive`** (OneDrive Personal or Business), and
   pick the drive it shows (the account's own *OneDrive*, not a SharePoint
   site, unless IT gave a shared library for it).
8. Confirm the drive, then **Yes** to keep the remote.

**The `files` remote (encryption)** is as above: type `crypt`, remote
**`dest:bravura-files`**, filename encryption `standard`, and your own
password and salt. Keep them with the BACKUP_PASSPHRASE.

**Check, then add the secret** as in steps 3 to 5:
- `rclone lsd dest:` lists the OneDrive's folders.
- `rclone copy supabase:avatars files:avatars` copies one bucket; a
  `bravura-files` folder of scrambled names appears in OneDrive (that is
  the encryption working).
- `rclone config file` shows where the settings are; paste the whole file
  into the GitHub secret **`RCLONE_CONFIG`**.

**Every few months: sign in again.** Microsoft limits how long rclone's
saved sign-in lasts (about 90 days, or less if the company's policy says
so), and the nightly job cannot save a renewed one back to GitHub. When it
runs out, the **Copy uploaded files** job fails with a sign-in error
(GitHub emails a failed scheduled run to whoever last changed the
workflow). To fix it, on the computer where you set it up:

```
rclone config reconnect dest:
```

Sign in again in the browser, then paste the whole `rclone config file`
into `RCLONE_CONFIG` once more. Changing the company password, or IT
signing the account out everywhere, needs the same step.

## Getting files back

With the same rclone config: `rclone copy files:documents ./documents`
(decrypts as it copies), then upload them back to the bucket of the same
name, or `rclone copy ./documents supabase:documents`.
