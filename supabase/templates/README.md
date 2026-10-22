# Omnia auth emails

Paste each file into Supabase › Authentication › Email Templates:

| File | Template | Subject |
| --- | --- | --- |
| confirmation.html | Confirm signup | Confirm your Omnia account |
| magic_link.html | Magic Link | Your Omnia sign-in code |
| recovery.html | Reset Password | Reset your Omnia password |

The wordmark is loaded from the public `brand` storage bucket
(`brand/omnia-wordmark-dark.png`, the light-glyph version for the dark card).
Email clients don't show SVG, so the PNG has to be hosted.
