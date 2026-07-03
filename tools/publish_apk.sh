#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Baut die Release-APK und veroeffentlicht sie als GitHub-Release-Asset.
#
# Voraussetzung:
#   - Versionsnummer in pubspec.yaml / lib/app_globals.dart wurde bereits erhoeht
#   - gh CLI installiert (winget install GitHub.cli)
#   - Ausfuehren im Repo-Root in Git Bash:  bash tools/publish_apk.sh
#
# Das Skript holt das GitHub-Token automatisch aus dem Windows Credential
# Manager (derselbe Login, den 'git push' nutzt) -> kein 'gh auth login' noetig.
# ---------------------------------------------------------------------------
set -euo pipefail

REPO="ulysses4439/orga_sphere"

VERSION=$(grep -E '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*([0-9.]+).*/\1/')
APK="OrgaSphere_v${VERSION}.apk"

echo "==> Baue Release-APK fuer v${VERSION} ..."
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk "$APK"

echo "==> Hole GitHub-Token aus dem Credential-Store ..."
export GH_TOKEN=$(printf 'protocol=https\nhost=github.com\n\n' \
  | git credential fill 2>/dev/null | sed -n 's/^password=//p')
if [ -z "${GH_TOKEN}" ]; then
  echo "FEHLER: Kein GitHub-Token gefunden. Einmalig 'gh auth login' ausfuehren." >&2
  exit 1
fi

GH="/c/Program Files/GitHub CLI/gh.exe"
[ -x "$GH" ] || GH="gh"

echo "==> Erstelle GitHub-Release v${VERSION} ..."
"$GH" release create "v${VERSION}" \
  --repo "$REPO" \
  --target main \
  --title "OrgaSphere v${VERSION}" \
  --notes "Android-Build v${VERSION}. Details siehe Commit-Historie." \
  "$APK"

echo "==> Fertig: https://github.com/${REPO}/releases/tag/v${VERSION}"
