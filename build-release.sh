#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="-"
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

#############
### BUILD ###
#############

./build-docs.sh --release
./build-shell-completion.sh

./generate.sh
./script/check-uncommitted-files.sh
./generate.sh --build-version "$build_version" --codesign-identity "$codesign_identity" --generate-git-hash

swift build -c release --arch arm64 --arch x86_64 --product aerospace -Xswiftc -warnings-as-errors # CLI

# todo: make xcodebuild use the same toolchain as swift
# toolchain="$(plutil -extract CFBundleIdentifier raw ~/Library/Developer/Toolchains/swift-6.1-RELEASE.xctoolchain/Info.plist)"
# xcodebuild -toolchain "$toolchain" \
# Unfortunately, Xcode 16 fails with:
#     2025-05-05 15:51:15.618 xcodebuild[4633:13690815] Writing error result bundle to /var/folders/s1/17k6s3xd7nb5mv42nx0sd0800000gn/T/ResultBundle_2025-05-05_15-51-0015.xcresult
#     xcodebuild: error: Could not resolve package dependencies:
#       <unknown>:0: warning: legacy driver is now deprecated; consider avoiding specifying '-disallow-use-new-driver'
#     <unknown>:0: error: unable to execute command: <unknown>

rm -rf .release && mkdir .release

cd ./xcode
    xcode_configuration="Release"
    xcodebuild -version
    xcodebuild-pretty ../.release/xcodebuild.log clean build \
        -scheme AeroSpace \
        -destination "generic/platform=macOS" \
        -configuration "$xcode_configuration" \
        -derivedDataPath .xcode-build
cd -

git restore -- Sources/Common/versionGenerated.swift Sources/Common/gitHashGenerated.swift

cp -r "xcode/.xcode-build/Build/Products/$xcode_configuration/TileSail.app" .release
cp -r .build/apple/Products/Release/aerospace .release
cp .release/aerospace .release/tilesail

################
### SIGN CLI ###
################

codesign -s "$codesign_identity" .release/aerospace
codesign -s "$codesign_identity" .release/tilesail

################
### VALIDATE ###
################

expected_layout=$(cat <<EOF
.release/TileSail.app
.release/TileSail.app/Contents
.release/TileSail.app/Contents/_CodeSignature
.release/TileSail.app/Contents/_CodeSignature/CodeResources
.release/TileSail.app/Contents/MacOS
.release/TileSail.app/Contents/MacOS/TileSail
.release/TileSail.app/Contents/Resources
.release/TileSail.app/Contents/Resources/default-config.toml
.release/TileSail.app/Contents/Resources/AppIcon.icns
.release/TileSail.app/Contents/Resources/Assets.car
.release/TileSail.app/Contents/Info.plist
.release/TileSail.app/Contents/PkgInfo
EOF
)

if test "$expected_layout" != "$(find .release/TileSail.app)"; then
    echo "!!! Expect/Actual layout don't match !!!"
    find .release/TileSail.app
    exit 1
fi

check-universal-binary() {
    if ! file "$1" | grep --fixed-string -q "Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64"; then
        echo "$1 is not a universal binary"
        exit 1
    fi
}

check-contains-hash() {
    hash=$(git rev-parse HEAD)
    if ! strings "$1" | grep --fixed-string "$hash" > /dev/null; then
        echo "$1 doesn't contain $hash"
        exit 1
    fi
}

check-universal-binary .release/TileSail.app/Contents/MacOS/TileSail
check-universal-binary .release/aerospace

check-contains-hash .release/TileSail.app/Contents/MacOS/TileSail
check-contains-hash .release/aerospace

codesign -v .release/TileSail.app
codesign -v .release/aerospace

############
### PACK ###
############

mkdir -p ".release/TileSail-v$build_version/manpage" && cp .man/*.1 ".release/TileSail-v$build_version/manpage"
cp -r ./legal ".release/TileSail-v$build_version/legal"
cp -r .shell-completion ".release/TileSail-v$build_version/shell-completion"
cd .release
    mkdir -p "TileSail-v$build_version/bin" && cp -r aerospace tilesail "TileSail-v$build_version/bin"
    cp -r TileSail.app "TileSail-v$build_version"
    zip -r "TileSail-v$build_version.zip" "TileSail-v$build_version"
cd -
