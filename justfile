set shell := ["bash", "-euo", "pipefail", "-c"]

project := "QatVasl.xcodeproj"
scheme := "QatVasl"
build_root := "build"
derived_data := "build/DerivedData"
dist_dir := "build/dist"
dmg_staging := "build/dmg-staging"
archive_path := "build/QatVasl.xcarchive"
debug_app := "build/DerivedData/Build/Products/Debug/QatVasl.app"
release_app := "build/DerivedData/Build/Products/Release/QatVasl.app"
dmg_path := "build/dist/QatVasl.dmg"

default:
    @just --list

doctor:
    xcodebuild -version
    xcodebuild -list -project "{{project}}"

build configuration="Debug":
    xcodebuild -project "{{project}}" -scheme "{{scheme}}" -configuration "{{configuration}}" -destination 'platform=macOS' -derivedDataPath "{{derived_data}}" CODE_SIGNING_ALLOWED=NO build

build-debug:
    just build Debug

build-release:
    just build Release

run configuration="Debug":
    app="{{derived_data}}/Build/Products/{{configuration}}/{{scheme}}.app"; \
    if [[ ! -d "$app" ]]; then just build "{{configuration}}"; fi; \
    pkill -x "{{scheme}}" || true; \
    open "$app"

dev:
    just run Debug

clean:
    xcodebuild -project "{{project}}" -scheme "{{scheme}}" -configuration Debug -derivedDataPath "{{derived_data}}" clean || true
    rm -rf "{{build_root}}"

archive:
    xcodebuild -project "{{project}}" -scheme "{{scheme}}" -configuration Release -destination 'generic/platform=macOS' -archivePath "{{archive_path}}" -derivedDataPath "{{derived_data}}" CODE_SIGNING_ALLOWED=NO archive

package-app:
    just build Release
    mkdir -p "{{dist_dir}}"
    rm -rf "{{dist_dir}}/{{scheme}}.app"
    ditto "{{release_app}}" "{{dist_dir}}/{{scheme}}.app"
    @echo "Created {{dist_dir}}/{{scheme}}.app"

dmg:
    just build Release
    mkdir -p "{{dist_dir}}"
    rm -rf "{{dmg_staging}}"
    mkdir -p "{{dmg_staging}}"
    ditto "{{release_app}}" "{{dmg_staging}}/{{scheme}}.app"
    ln -s /Applications "{{dmg_staging}}/Applications"
    hdiutil create -volname "{{scheme}}" -srcfolder "{{dmg_staging}}" -ov -format UDZO "{{dmg_path}}"
    @echo "Created {{dmg_path}}"

open-dmg:
    just dmg
    open "{{dmg_path}}"

install:
    just build Release
    ditto "{{release_app}}" "/Applications/{{scheme}}.app"

logs:
    log stream --style compact --predicate 'process == "{{scheme}}"'

reset-settings:
    defaults delete com.mhmoaz.QatVasl || true
