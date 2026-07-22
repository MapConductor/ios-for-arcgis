#!/usr/bin/env bash
set -euo pipefail

# Downloads the two ArcGIS Maps SDK for Swift binaries (ArcGIS.xcframework,
# CoreArcGIS.xcframework) that MapConductorForArcGIS.podspec vendors, at the exact version/
# checksum pinned in this package's Package.resolved. Esri only distributes this SDK via Swift
# Package Manager binaryTargets (no public CocoaPods spec), so CocoaPods consumers need these
# fetched into Frameworks/ directly - see MapConductorForArcGIS.podspec for the full rationale.
#
# Re-run this after bumping the arcgis-maps-sdk-swift dependency in Package.swift/Package.resolved.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORKS_DIR="$ROOT_DIR/Frameworks"
RESOLVED="$ROOT_DIR/Package.resolved"

version=$(python3 -c "
import json
with open('$RESOLVED') as f:
    data = json.load(f)
for pin in data['pins']:
    if pin['identity'] == 'arcgis-maps-sdk-swift':
        print(pin['state']['version'])
        break
")

if [ -z "$version" ]; then
  echo "Could not find arcgis-maps-sdk-swift pin in $RESOLVED" >&2
  exit 1
fi

package_swift_url="https://raw.githubusercontent.com/Esri/arcgis-maps-sdk-swift/$version/Package.swift"
echo "Fetching binaryTarget URLs/checksums for arcgis-maps-sdk-swift $version..."

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
curl -sL -o "$work_dir/Package.swift" "$package_swift_url"

for name in ArcGIS CoreArcGIS; do
  url=$(python3 -c "
import re
with open('$work_dir/Package.swift') as f:
    text = f.read()
m = re.search(r'name:\s*\"$name\",\s*\n\s*url:\s*\"([^\"]+)\"', text)
print(m.group(1) if m else '')
")
  checksum=$(python3 -c "
import re
with open('$work_dir/Package.swift') as f:
    text = f.read()
m = re.search(r'name:\s*\"$name\",\s*\n\s*url:\s*\"[^\"]+\",\s*\n\s*checksum:\s*\"([^\"]+)\"', text)
print(m.group(1) if m else '')
")

  if [ -z "$url" ] || [ -z "$checksum" ]; then
    echo "Could not parse binaryTarget for $name from $package_swift_url" >&2
    exit 1
  fi

  zip_path="$work_dir/$name.xcframework.zip"
  echo "Downloading $name ($url)..."
  curl -sL -o "$zip_path" "$url"

  actual_checksum=$(shasum -a 256 "$zip_path" | cut -d' ' -f1)
  if [ "$actual_checksum" != "$checksum" ]; then
    echo "Checksum mismatch for $name: expected $checksum, got $actual_checksum" >&2
    exit 1
  fi

  rm -rf "$FRAMEWORKS_DIR/$name.xcframework"
  unzip -q "$zip_path" -d "$work_dir/$name-extracted"
  mkdir -p "$FRAMEWORKS_DIR"
  mv "$work_dir/$name-extracted/$name.xcframework" "$FRAMEWORKS_DIR/$name.xcframework"
  echo "$name.xcframework ready at $FRAMEWORKS_DIR/$name.xcframework"
done

echo "Done."
