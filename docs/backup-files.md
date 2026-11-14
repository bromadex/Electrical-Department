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

## Getting files back

With the same rclone config: `rclone copy files:documents ./documents`
(decrypts as it copies), then upload them back to the bucket of the same
name, or `rclone copy ./documents supabase:documents`.
