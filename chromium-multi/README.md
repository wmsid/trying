# chromium-multi

Run several Chromium windows from the **same profile**, each on its own X/VNC display.

Stock Chromium allows one process per profile (`SingletonLock`), and concurrent writers corrupt it.
`chromium-multi` gives each display a private copy-on-write view of one shared base profile:
logins/cookies/extensions carry over, writes stay isolated.

- root: overlayfs (instant, lower = base profile)
- non-root: tar copy of the base profile (caches and locks skipped)

```bash
# virtual displays (optionally view via x11vnc -display :1)
./chromium-multi -d :1 --xvfb -- https://example.com
./chromium-multi -d :2 --xvfb -- https://example.org
# real displays / VNC servers that already exist
./chromium-multi -d :5
./chromium-multi -d :1 --reset      # drop this display's changes
./chromium-multi -d :1 --promote    # push this display's profile back to the base
```

Each instance gets remote debugging on port `9222 + display number` (override with `--port`).
Base profile defaults to `~/.config/chromium-multi/base`; point `-p` at an existing profile
(close Chromium using it first). Requires `tar`; `Xvfb` for `--xvfb`.

This is a wrapper around stock Chromium, not a source patch, so it needs no rebuild.
