# Chromium: one profile, one browser per RDP/console session (Windows)

`0001-per-session-profile-lockfile.patch` (against Chromium `main`,
`chrome/browser/process_singleton_win.cc`; applies cleanly) appends the Windows
session id to the profile `lockfile` (`lockfile.s2`, ...). The singleton message
window and startup mutex are already per-session, so each RDP session can start
its own Chrome on the same `--user-data-dir`.

## Build
Needs a Windows machine, ~100 GB disk, Visual Studio, depot_tools, hours of build.
    fetch chromium && cd src && git apply <path>\0001-per-session-profile-lockfile.patch
    gn gen out\Release --args="is_debug=false is_component_build=false"
    autoninja -C out\Release chrome

## NOT done / untested
This patch only removes the *launch* block. It has not been built or run.
Two Chromes writing one profile will still conflict on:
- SQLite files (Cookies, History, Login Data...) opened with exclusive locking -> 2nd process fails or errors.
- LevelDB stores (Local Storage, IndexedDB, Sync Data) have a `LOCK` file -> 2nd process can't open them.
- Even when opened, each process caches cookies in memory, so sessions won't sync live and writes can clobber each other.
Making these work (shared-lock SQLite/WAL, per-process LevelDB, cookie change propagation) is a much
larger change that is not in this patch. Expect broken storage until that is done.
