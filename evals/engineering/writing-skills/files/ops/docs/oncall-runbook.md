# On-call runbook: disk-full page

When you get paged for "disk usage above 90%" on an app host:

1. Note: check which host paged first, the alert names it.
2. SSH to the host and run `df -h /srv` to confirm. If usage is under 90%
   now, the alert was a spike: acknowledge it and stop.
3. Look at what is using the space: `sudo du -xh /srv | sort -h | tail -20`.
   Usually it is old release directories or rotated logs.
4. Remove old releases with `deployctl gc --keep 3`. Never delete release
   directories by hand; `current` may point at one of them.
5. Compress logs older than a day: `sudo find /srv/shop/logs -name '*.log.1' -exec gzip {} +`.
6. NEVER restart the database to free space. Postgres replays its WAL on
   restart, which needs more disk, and the host can end up unable to start it.
7. If usage is still above 85% after steps 4 and 5, page the platform team
   in #platform-oncall and stop; do not delete anything else.

Afterwards, post in #ops what you removed and how much space it freed. We
usually recieve two or three of these pages a month.
