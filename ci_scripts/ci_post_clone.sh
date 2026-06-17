#!/bin/sh
# Xcode Cloud post-clone hook.
#
# Xcode Cloud workers are stateless: every build starts with a fresh
# git clone, no .xcodeproj on disk. WoodlandsEats keeps the project
# file OUT of git (XcodeGen generates it from project.yml on demand).
# So we install XcodeGen here and regenerate WoodlandsEats.xcodeproj
# before Xcode Cloud tries to build it.
#
# This script is invoked by Xcode Cloud automatically on every build
# right after `git clone` completes and before any Xcode action runs.
# Apple's docs: developer.apple.com/documentation/xcode/writing-custom-build-scripts
#
# The script MUST be at exactly:
#   ci_scripts/ci_post_clone.sh
# (relative to repo root), and MUST be executable.

set -e

echo "==> Installing XcodeGen via Homebrew"
# Xcode Cloud workers come with Homebrew preinstalled.
brew install xcodegen

echo "==> Regenerating WoodlandsEats.xcodeproj from project.yml"
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "==> ci_post_clone.sh complete — XcodeGen-generated project ready for Xcode Cloud"
