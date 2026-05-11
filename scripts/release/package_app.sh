#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/release/package_app.sh [options]

Build and assemble dist/Paddlr.app from the SwiftPM Paddlr executable.
The app bundle is locally signed so macOS can validate its bundle resources.

Options:
  --output-dir <path>        Directory for release artifacts (default: dist)
  --version <version>        CFBundleShortVersionString (default: latest v* tag or 0.1.2)
  --build-number <number>    CFBundleVersion (default: UTC timestamp)
  --bundle-id <id>           CFBundleIdentifier (default: com.zachskjaveland.paddlr)
  --minimum-macos <version>  LSMinimumSystemVersion (default: 15.0)
  --skip-build               Reuse an existing .build release executable
  --clean                    Remove the output directory before packaging
  --create-zip               Create dist/Paddlr-<version>.zip after packaging
  --no-sign                  Skip local bundle signing (not recommended for downloads)
  -h, --help                 Show this help

Examples:
  scripts/release/package_app.sh
  scripts/release/package_app.sh --clean --create-zip
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
version=""
build_number=""

latest_tag_version() {
  local tag
  tag=$(git -C "$repo_root" describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || true)
  if [[ -n "$tag" ]]; then
    printf '%s\n' "${tag#v}"
  else
    printf '0.1.2\n'
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

if [[ "$clean_output" == true ]]; then
  rm -rf "$output_dir"
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
  codesign \
    --force \
    --sign - \
    --requirements "=designated => identifier \"$bundle_id\"" \
    "$app_path"
  codesign --verify --strict --verbose=2 "$app_path"
fi

if [[ "$create_zip" == true ]]; then
  final_zip="$output_dir/Paddlr-$version.zip"
  rm -f "$final_zip"
  (
    cd "$output_dir"
    zip -qry -X "$final_zip" "$bundle_name"
  )
  echo "Created archive: $final_zip"
fi

if [[ "$sign_bundle" == true ]]; then
  echo "Created locally signed app bundle: $app_path"
else
  echo "Created unsigned app bundle: $app_path"
fi
echo "Bundle identifier: $bundle_id"
echo "Version: $version ($build_number)"
