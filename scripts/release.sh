#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Kickstart a new QatVasl release.

Usage:
  scripts/release.sh --version <vX.Y.Z>
  scripts/release.sh --bump <major|minor|patch>
  scripts/release.sh <vX.Y.Z>
  scripts/release.sh <major|minor|patch>

Examples:
  scripts/release.sh --version v1.2.3
  scripts/release.sh --bump patch
  scripts/release.sh v1.2.3
  scripts/release.sh patch
USAGE
}

if [[ "${1:-}" == "" ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Error: 'git' is required."
  exit 1
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "main" ]]; then
  echo "Error: release must be created from 'main' (current: $current_branch)."
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working tree is not clean. Commit or stash your changes first."
  exit 1
fi

mode=""
input=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      mode="version"
      input="${2:-}"
      shift 2
      ;;
    --bump)
      mode="bump"
      input="${2:-}"
      shift 2
      ;;
    *)
      if [[ -n "$mode" ]]; then
        echo "Error: unexpected argument '$1'"
        usage
        exit 1
      fi
      input="$1"
      shift
      ;;
  esac
done

if [[ -z "$input" ]]; then
  echo "Error: missing value."
  usage
  exit 1
fi

next_version_from_bump() {
  local bump="$1"
  local latest_tag latest major minor patch

  latest_tag="$(git tag --list 'v*' --sort=-v:refname | head -n1 || true)"
  if [[ -z "$latest_tag" ]]; then
    latest_tag="v0.0.0"
  fi

  if [[ ! "$latest_tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Error: latest tag '$latest_tag' does not match vMAJOR.MINOR.PATCH"
    exit 1
  fi

  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[3]}"

  case "$bump" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      echo "Error: bump must be one of: major, minor, patch"
      exit 1
      ;;
  esac

  echo "v${major}.${minor}.${patch}"
}

if [[ "$mode" == "version" ]]; then
  if [[ ! "$input" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: --version must match vMAJOR.MINOR.PATCH"
    exit 1
  fi
  version="$input"
elif [[ "$mode" == "bump" ]]; then
  version="$(next_version_from_bump "$input")"
else
  if [[ "$input" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    version="$input"
  else
    version="$(next_version_from_bump "$input")"
  fi
fi

echo "Preparing release: ${version}"

git fetch --tags

if git rev-parse "${version}" >/dev/null 2>&1; then
  echo "Error: tag ${version} already exists locally."
  exit 1
fi

if git ls-remote --tags origin "refs/tags/${version}" | grep -q "${version}"; then
  echo "Error: tag ${version} already exists on origin."
  exit 1
fi

git tag -a "${version}" -m "Release ${version}"
git push origin "${version}"
echo "Release created: ${version}"
echo "Tag pushed. GitHub Actions will build DMG and publish the release."
