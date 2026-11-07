#!/bin/zsh
# Publishes a GitHub Release that installed copies of GitOS update to: ./scripts/release.sh 0.2.0
# Needs a clean main branch, `gh auth login`, and the Sparkle private key in the login Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: ./scripts/release.sh <version>, e.g. 0.2.0}"
TAG="v$VERSION"
REPO="Dhunu/gitOS"

[[ "$(git branch --show-current)" == "main" ]] || { echo "Switch to main first."; exit 1; }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "Commit or stash your changes first."; exit 1; }
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "$TAG already exists."; exit 1; }

sed -i '' "s/^VERSION=\".*\"/VERSION=\"$VERSION\"/" scripts/build-app.sh
swift test
./scripts/make-dmg.sh

DMG="build/GitOS-$VERSION.dmg"
SIGNATURE="$(.build/artifacts/sparkle/Sparkle/bin/sign_update --account gitos "$DMG")"
cat > build/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>GitOS</title>
    <item>
      <title>GitOS $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$REPO/releases/tag/$TAG</sparkle:fullReleaseNotesLink>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/GitOS-$VERSION.dmg" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
XML

git diff --quiet scripts/build-app.sh || git commit -m "Release $VERSION" scripts/build-app.sh
git tag "$TAG"
git push origin main "$TAG"
gh release create "$TAG" "$DMG" build/appcast.xml --repo "$REPO" --title "GitOS $VERSION" --generate-notes
echo "Published $TAG"

# Point the Homebrew tap at the new version (best effort; the release itself is already out).
CASK_REPO="Dhunu/homebrew-tap"
CASK_PATH="Casks/gitos.rb"
if OLD_CASK_SHA=$(gh api "repos/$CASK_REPO/contents/$CASK_PATH" --jq .sha 2>/dev/null); then
  SHA256=$(shasum -a 256 "$DMG" | awk '{print $1}')
  gh api "repos/$CASK_REPO/contents/$CASK_PATH" --jq .content | base64 -d \
    | sed -e "s/^  version \".*\"/  version \"$VERSION\"/" \
          -e "s/^  sha256 \".*\"/  sha256 \"$SHA256\"/" > build/gitos.rb
  gh api -X PUT "repos/$CASK_REPO/contents/$CASK_PATH" \
    -f message="gitos $VERSION" \
    -f content="$(base64 -i build/gitos.rb)" \
    -f sha="$OLD_CASK_SHA" > /dev/null
  echo "Updated $CASK_REPO to $VERSION"
else
  echo "Homebrew tap not found; skipped cask update."
fi
