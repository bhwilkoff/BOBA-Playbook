#!/usr/bin/env bash
#
# embed_native_debug_symbols.sh — make Play Console stop warning about
# "native code … no debug symbols", with NO manual upload.
#
# WHY: our AAB ships a few tiny .so files that Google distributes PRE-STRIPPED
# (AndroidX graphics-path, CameraX image_processing_util_jni, DataStore
# shared_counter). `ndk.debugSymbolLevel` can't extract symbols that were
# already stripped, so AGP embeds nothing and Play warns. The standalone
# native-debug-symbols.zip can only be ingested via the Play Developer API
# (edits.deobfuscationfiles.upload), which is blocked for us by the Play
# Console "API access" ACL issue — so the manual UI upload is the only path,
# and it's unreliable.
#
# This embeds the symbols the way AGP itself does — into the AAB at
#   BUNDLE-METADATA/com.android.tools.build.debugsymbols/<abi>/<lib>.so.dbg
# (path + ".dbg" suffix confirmed from AGP's ExtractNativeDebugMetadataTask.kt)
# — then re-signs with the upload key. Play reads symbols straight out of the
# uploaded bundle, so the warning never fires and nothing else is needed.
# Play accepts BuildID-only symbols (verified: our prior stripped zip cleared
# the warning), so the stripped .so's renamed to .so.dbg are sufficient.
#
# Usage:  embed_native_debug_symbols.sh <path-to-signed-app-release.aab>
# Needs (same env the release signingConfig uses):
#   UPLOAD_KEYSTORE_PATH UPLOAD_KEYSTORE_PASSWORD UPLOAD_KEY_PASSWORD UPLOAD_KEY_ALIAS
# Skips gracefully (exit 0) if the keystore env isn't present (e.g. a debug build).

set -euo pipefail

AAB="${1:?usage: embed_native_debug_symbols.sh <app-release.aab>}"
DBG_DIR="BUNDLE-METADATA/com.android.tools.build.debugsymbols"

if [[ ! -f "$AAB" ]]; then echo "  [symbols] AAB not found: $AAB — skipping"; exit 0; fi
if [[ -z "${UPLOAD_KEYSTORE_PATH:-}" || -z "${UPLOAD_KEYSTORE_PASSWORD:-}" ]]; then
  echo "  [symbols] keystore env not set — skipping embed (debug build?)."; exit 0
fi

ALIAS="${UPLOAD_KEY_ALIAS:-boba-upload}"
KEYPASS="${UPLOAD_KEY_PASSWORD:-$UPLOAD_KEYSTORE_PASSWORD}"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
AAB_ABS="$(cd "$(dirname "$AAB")" && pwd)/$(basename "$AAB")"

# 1. Pull the packaged .so files (base/lib/<abi>/*.so).
unzip -q "$AAB_ABS" 'base/lib/*/*.so' -d "$work/x" 2>/dev/null || true
if ! ls "$work"/x/base/lib/*/*.so >/dev/null 2>&1; then
  echo "  [symbols] AAB has no native libs — nothing to embed."; exit 0
fi

# 2. Build the debugsymbols tree: <abi>/<lib>.so.dbg (AGP's exact layout).
#    --only-keep-debug when an ELF objcopy is available (smaller, canonical);
#    otherwise copy the .so verbatim (still carries the BuildID Play matches on).
OBJCOPY="$(command -v llvm-objcopy || command -v objcopy || true)"
count=0
for abi_path in "$work"/x/base/lib/*/; do
  abi="$(basename "$abi_path")"
  mkdir -p "$work/inject/$DBG_DIR/$abi"
  for so in "$abi_path"*.so; do
    out="$work/inject/$DBG_DIR/$abi/$(basename "$so").dbg"
    if [[ -n "$OBJCOPY" ]] && "$OBJCOPY" --only-keep-debug "$so" "$out" 2>/dev/null && [[ -s "$out" ]]; then :;
    else cp "$so" "$out"; fi
    count=$((count + 1))
  done
done
echo "  [symbols] staged $count .so.dbg files across $(ls "$work"/inject/"$DBG_DIR" | wc -l | tr -d ' ') ABIs"

# 3. Inject into the AAB and re-sign (jarsigner v1 — the AAB signing scheme).
#    Drop the old signature first so jarsigner produces a clean one over the
#    new entry set.
( cd "$work/inject" && zip -q -r -X "$AAB_ABS" BUNDLE-METADATA )
zip -qd "$AAB_ABS" 'META-INF/*.SF' 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' 2>/dev/null || true
jarsigner -keystore "$UPLOAD_KEYSTORE_PATH" \
  -storepass "$UPLOAD_KEYSTORE_PASSWORD" -keypass "$KEYPASS" \
  -digestalg SHA-256 -sigalg SHA256withRSA \
  "$AAB_ABS" "$ALIAS" >/dev/null
jarsigner -verify "$AAB_ABS" >/dev/null && echo "  [symbols] embedded + re-signed OK → $AAB"

# 4. Sanity: confirm the symbols are now in the bundle.
n="$(unzip -l "$AAB_ABS" | grep -c "$DBG_DIR/.*\.so\.dbg" || true)"
echo "  [symbols] AAB now contains $n embedded native debug symbol files."
