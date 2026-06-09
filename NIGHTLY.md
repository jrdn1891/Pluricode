# Nightly builds & auto-updates

Pluricode updates itself via [Sparkle](https://sparkle-project.org). Stable releases
(`release.sh`) ship on the default channel; nightly builds ship on the `nightly` channel,
which users opt into under **Settings → Updates**. Both are published to a single appcast
feed on the `gh-pages` branch and served at the `SUFeedURL` in `Pluricode/Info.plist`.

The app is not notarized, so the **first** install still requires
System Settings → Privacy & Security → *Open Anyway*. Every Sparkle-delivered update after
that is seamless — Sparkle strips the quarantine flag on install.

## One-time setup

Do these once, in order. **Replace the placeholder `SUPublicEDKey` before the first real
build** — a build carrying the placeholder key can never validate a genuinely-signed update.

```sh
# 1. Get the Sparkle tools (match the version pinned in .github/workflows/nightly.yml)
VER=2.6.4
curl -fsSL -o /tmp/sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/$VER/Sparkle-$VER.tar.xz
mkdir -p /tmp/sparkle && tar -xf /tmp/sparkle.tar.xz -C /tmp/sparkle
export SPARKLE_BIN=/tmp/sparkle/bin

# 2. Generate the signing keypair (private key is saved in your login keychain)
#    and paste the printed public key into Pluricode/Info.plist → SUPublicEDKey
"$SPARKLE_BIN/generate_keys"

# 3. Export the private key and store it as the SPARKLE_PRIVATE_KEY repo secret for CI
"$SPARKLE_BIN/generate_keys" -x /tmp/sparkle_key
gh secret set SPARKLE_PRIVATE_KEY < /tmp/sparkle_key
rm /tmp/sparkle_key

# 4. Trigger the first nightly so the gh-pages branch is created
gh workflow run nightly.yml

# 5. Enable GitHub Pages on gh-pages (serves the appcast at SUFeedURL)
gh api -X POST repos/jrdn1891/Pluricode/pages --input - <<'JSON'
{"source":{"branch":"gh-pages","path":"/"}}
JSON
```

## Cutting a stable release

`release.sh` needs the Sparkle tools to sign the update. It reads the private key from your
keychain (step 2) and finds `sign_update` via `$SPARKLE_BIN`, your `PATH`, or DerivedData:

```sh
SPARKLE_BIN=/tmp/sparkle/bin ./release.sh
```

Bump `CFBundleShortVersionString` in `Pluricode/Info.plist` first; `CFBundleVersion` is
stamped automatically from the commit count so stable and nightly stay comparable.
