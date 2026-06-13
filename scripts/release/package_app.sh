#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/release/package_app.sh [options]

Build and assemble dist/Paddlr.app from the SwiftPM Paddlr executable.
By default the app bundle is locally signed so macOS can validate its bundle resources.
For public downloads, pass a Developer ID Application identity and --notarize.

Options:
  --output-dir <path>        Directory for release artifacts (default: dist)
  --version <version>        CFBundleShortVersionString (default: latest v* tag or 0.1.10)
  --build-number <number>    CFBundleVersion (default: UTC timestamp)
  --bundle-id <id>           CFBundleIdentifier (default: com.zachskjaveland.paddlr)
  --minimum-macos <version>  LSMinimumSystemVersion (default: 15.0)
  --signing-identity <id>    codesign identity (default: ad-hoc local signing)
  --notarize                 Submit the zip to Apple's notary service, staple the app, and recreate the zip
  --notary-profile <name>    notarytool keychain profile (default: PADDLR_NOTARY_PROFILE or paddlr-notary)
  --skip-build               Reuse an existing .build release executable
  --clean                    Remove generated Paddlr artifacts from the output directory before packaging
  --create-zip               Create dist/Paddlr-<version>.zip after packaging
  --no-sign                  Skip local bundle signing (not recommended for downloads)
  -h, --help                 Show this help

Examples:
  scripts/release/package_app.sh
  scripts/release/package_app.sh --clean --create-zip
  xcrun notarytool store-credentials paddlr-notary --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
  scripts/release/package_app.sh --clean --create-zip --signing-identity "Developer ID Application: Example (TEAMID)" --notarize
USAGE
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
info_plist_template="$repo_root/Resources/Paddlr/Info.plist"
app_icon_path="$repo_root/Resources/Paddlr/AppIcon.icns"
output_dir="$repo_root/dist"
bundle_name="Paddlr.app"
executable_name="Paddlr"
bundle_id="com.zachskjaveland.paddlr"
minimum_macos="15.0"
skip_build=false
clean_output=false
create_zip=false
sign_bundle=true
signing_identity="${PADDLR_CODESIGN_IDENTITY:--}"
notarize=false
notary_profile="${PADDLR_NOTARY_PROFILE:-paddlr-notary}"
version=""
build_number=""

latest_tag_version() {
  local tag
  tag=$(git -C "$repo_root" describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || true)
  if [[ -n "$tag" ]]; then
    printf '%s\n' "${tag#v}"
  else
    printf '0.1.10\n'
  fi
}

utc_build_number() {
  date -u +%Y%m%d%H%M%S
}

require_value() {
  if [[ -z "${2:-}" ]]; then
    echo "$1 requires a value." >&2
    exit 2
  fi
}

resolve_output_dir() {
  local raw_path=$1
  local trimmed_path

  trimmed_path=${raw_path%/}
  if [[ -z "$trimmed_path" || "$trimmed_path" == "/" ]]; then
    echo "Refusing unsafe output directory: ${raw_path:-<empty>}" >&2
    exit 2
  fi

  mkdir -p "$trimmed_path"
  cd "$trimmed_path" && pwd -P
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      require_value "$1" "${2:-}"
      output_dir=$2
      shift 2
      ;;
    --version)
      require_value "$1" "${2:-}"
      version=$2
      shift 2
      ;;
    --build-number)
      require_value "$1" "${2:-}"
      build_number=$2
      shift 2
      ;;
    --bundle-id)
      require_value "$1" "${2:-}"
      bundle_id=$2
      shift 2
      ;;
    --minimum-macos)
      require_value "$1" "${2:-}"
      minimum_macos=$2
      shift 2
      ;;
    --signing-identity)
      require_value "$1" "${2:-}"
      signing_identity=$2
      sign_bundle=true
      shift 2
      ;;
    --notarize)
      notarize=true
      create_zip=true
      sign_bundle=true
      shift
      ;;
    --notary-profile)
      require_value "$1" "${2:-}"
      notary_profile=$2
      shift 2
      ;;
    --skip-build)
      skip_build=true
      shift
      ;;
    --clean)
      clean_output=true
      shift
      ;;
    --create-zip)
      create_zip=true
      shift
      ;;
    --no-sign)
      sign_bundle=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$notarize" == true && "$sign_bundle" != true ]]; then
  echo "Notarization requires signing. Remove --no-sign." >&2
  exit 2
fi

if [[ "$notarize" == true && "$signing_identity" == "-" ]]; then
  echo "Notarization requires a Developer ID Application signing identity." >&2
  echo "Pass --signing-identity \"Developer ID Application: <Name> (<Team ID>)\" or set PADDLR_CODESIGN_IDENTITY." >&2
  exit 2
fi

if [[ "$notarize" == true && -z "$notary_profile" ]]; then
  echo "Notarization requires a notarytool keychain profile." >&2
  echo "Create one with: xcrun notarytool store-credentials paddlr-notary --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>" >&2
  exit 2
fi

if [[ -z "$version" ]]; then
  version=$(latest_tag_version)
fi

if [[ -z "$build_number" ]]; then
  build_number=$(utc_build_number)
fi

if [[ ! -f "$info_plist_template" ]]; then
  echo "Info.plist template not found: $info_plist_template" >&2
  exit 1
fi

output_dir=$(resolve_output_dir "$output_dir")
if [[ "$output_dir" == "$repo_root" ]]; then
  echo "Refusing to use the private repo root as the output directory." >&2
  exit 2
fi
case "$repo_root" in
  "$output_dir"/*)
    echo "Refusing to use an output directory that contains the private repo: $output_dir" >&2
    exit 2
    ;;
esac

clean_generated_artifacts() {
  rm -rf "$output_dir/$bundle_name"
  find "$output_dir" -maxdepth 1 -type f -name 'Paddlr-*.zip' -exec rm -f {} +
}

if [[ "$clean_output" == true ]]; then
  clean_generated_artifacts
fi
mkdir -p "$output_dir"
app_path="$output_dir/$bundle_name"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"
info_plist="$contents_path/Info.plist"

if [[ "$skip_build" != true ]]; then
  swift build --package-path "$repo_root" --configuration release --product "$executable_name"
fi

bin_path=$(swift build --package-path "$repo_root" --configuration release --show-bin-path)
executable_path="$bin_path/$executable_name"
if [[ ! -x "$executable_path" ]]; then
  echo "Release executable not found or not executable: $executable_path" >&2
  echo "Run without --skip-build first, or run: swift build -c release --product Paddlr" >&2
  exit 1
fi

rm -rf "$app_path"
mkdir -p "$macos_path" "$resources_path"
cp "$executable_path" "$macos_path/$executable_name"
chmod 755 "$macos_path/$executable_name"
cp "$info_plist_template" "$info_plist"
if [[ -f "$app_icon_path" ]]; then
  cp "$app_icon_path" "$resources_path/AppIcon.icns"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$info_plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$info_plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$info_plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $minimum_macos" "$info_plist"
plutil -lint "$info_plist" >/dev/null
xattr -cr "$app_path" 2>/dev/null || true

if [[ "$sign_bundle" == true ]]; then
  if [[ "$signing_identity" == "-" ]]; then
    codesign \
      --force \
      --sign - \
      --requirements "=designated => identifier \"$bundle_id\"" \
      "$app_path"
  else
    if ! security find-identity -v -p codesigning | grep -F -- "$signing_identity" >/dev/null; then
      echo "Signing identity not found in the keychain: $signing_identity" >&2
      echo "Install the Developer ID Application certificate, then rerun packaging." >&2
      exit 1
    fi

    codesign \
      --force \
      --timestamp \
      --options runtime \
      --sign "$signing_identity" \
      "$macos_path/$executable_name"
    codesign \
      --force \
      --timestamp \
      --options runtime \
      --sign "$signing_identity" \
      "$app_path"
  fi
  codesign --verify --strict --verbose=2 "$app_path"
fi

create_zip_archive() {
  local zip_path=$1
  rm -f "$zip_path"
  (
    cd "$output_dir"
    ditto -c -k --sequesterRsrc --keepParent "$bundle_name" "$zip_path"
  )
}

if [[ "$create_zip" == true ]]; then
  final_zip="$output_dir/Paddlr-$version.zip"
  create_zip_archive "$final_zip"
fi

if [[ "$notarize" == true ]]; then
  echo "Submitting archive for notarization: $final_zip"
  xcrun notarytool submit "$final_zip" --keychain-profile "$notary_profile" --wait
  xcrun stapler staple "$app_path"
  xcrun stapler validate "$app_path"
  spctl -a -vvv -t exec "$app_path"
  create_zip_archive "$final_zip"
  echo "Notarized and stapled app bundle: $app_path"
  echo "Recreated notarized archive: $final_zip"
elif [[ "$create_zip" == true ]]; then
  echo "Created archive: $final_zip"
fi

if [[ "$sign_bundle" == true ]]; then
  if [[ "$signing_identity" == "-" ]]; then
    echo "Created locally signed app bundle: $app_path"
  else
    echo "Created Developer ID signed app bundle: $app_path"
  fi
else
  echo "Created unsigned app bundle: $app_path"
fi
echo "Bundle identifier: $bundle_id"
echo "Version: $version ($build_number)"
