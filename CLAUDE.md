# Project rules

## Versioning (apps are live in production)
- Every change that affects what users install (anything outside `bin/` and `*.md`: `brand.env`, `scripts/`,
  `installers/`, `.github/workflows/`) MUST bump `BUILD_VERSION` in `brand.env` in the same commit/push.
  Never ship a changed build under an existing version number.
- Semantic versioning: patch (1.1.0 -> 1.1.1) for fixes, minor (1.1.x -> 1.2.0) for new features or a
  NetBird upstream bump (`NETBIRD_VERSION`), major only for breaking changes (e.g. renamed service/paths).
- State the old and new version when reporting the change.

## Branches
- Production downloads come from `bin/` on `main` (GitHub Actions rebuilds and commits them on every push).
- The repo's default branch is `claude/headless-softether-client-s13nn0`, which is NOT what users download.
