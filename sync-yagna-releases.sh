#!/usr/bin/env bash

set -euo pipefail

readonly DEFAULT_REPOSITORY="golemfactory/yagna"
readonly DEFAULT_DESTINATION="s3://golem-releases/yagna/"
readonly DEFAULT_CACHE_CONTROL="public,max-age=31536000,immutable"

repository="${YAGNA_RELEASE_REPOSITORY:-$DEFAULT_REPOSITORY}"
destination="${YAGNA_RELEASE_DESTINATION:-$DEFAULT_DESTINATION}"
cache_control="${YAGNA_RELEASE_CACHE_CONTROL:-$DEFAULT_CACHE_CONTROL}"
force=false
dry_run=false
tags=()

usage() {
    cat <<'EOF'
Usage: ./sync-yagna-releases.sh [--dry-run] [--force] [TAG [TAG ...]]

Copy Yagna provider and requestor release bundles from GitHub Releases to S3.
Objects that already exist with the expected size are skipped.

Options:
  --dry-run  Show what would be copied without downloading or uploading assets.
  --force    Replace existing S3 objects.
  -h, --help Show this help.

Environment:
  YA_INSTALLER_CORE              Release tag used when no TAG argument is given
  GH_TOKEN                       GitHub token with read access to the private repo
  AWS_PROFILE                    Optional AWS CLI profile
  YAGNA_RELEASE_REPOSITORY       Source repo (default: golemfactory/yagna)
  YAGNA_RELEASE_DESTINATION      S3 URI (default: s3://golem-releases/yagna/)
  YAGNA_RELEASE_CACHE_CONTROL    Cache-Control metadata for uploaded objects
EOF
}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        fail "sha256sum or shasum is required to verify GitHub asset digests"
    fi
}

while (($#)); do
    case "$1" in
        --dry-run)
            dry_run=true
            ;;
        --force)
            force=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            tags+=("$@")
            break
            ;;
        -*)
            fail "unknown option: $1"
            ;;
        *)
            tags+=("$1")
            ;;
    esac
    shift
done

if ((${#tags[@]} == 0)) && [[ -n "${YA_INSTALLER_CORE:-}" ]]; then
    tags+=("$YA_INSTALLER_CORE")
fi

((${#tags[@]} > 0)) || {
    usage >&2
    fail "provide at least one release tag or set YA_INSTALLER_CORE"
}

[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
    fail "invalid GitHub repository: $repository"
[[ "$destination" == s3://* ]] ||
    fail "destination must be an s3:// URI: $destination"

for tag in "${tags[@]}"; do
    [[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || fail "invalid release tag: $tag"
done

require_command aws
require_command gh
require_command jq
require_command mktemp
require_command awk

s3_path="${destination#s3://}"
s3_path="${s3_path%/}"
if [[ "$s3_path" == */* ]]; then
    bucket="${s3_path%%/*}"
    prefix="${s3_path#*/}"
else
    bucket="$s3_path"
    prefix=""
fi
[[ -n "$bucket" ]] || fail "destination has no bucket name: $destination"

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
manifest="$tmp_dir/assets.tsv"
: >"$manifest"

export AWS_PAGER=""

for tag in "${tags[@]}"; do
    release_json="$tmp_dir/release-${#tag}-${tag}.json"
    if ! gh api "repos/$repository/releases/tags/$tag" >"$release_json"; then
        fail "cannot read release $tag from $repository; check GH_TOKEN or gh auth status"
    fi

    if [[ "$(jq -r '.draft' "$release_json")" == "true" ]]; then
        fail "release $tag is still a draft"
    fi

    jq -r --arg tag "$tag" '
        .assets[]
        | select(
            (.name | test("^golem-(provider|requestor)-"))
            and (.name | test("\\.(tar\\.gz|zip)$"))
        )
        | [
            $tag,
            (.id | tostring),
            .name,
            (.size | tostring),
            (.digest // "")
        ]
        | @tsv
    ' "$release_json" >>"$manifest"
done

asset_count="$(wc -l <"$manifest")"
((asset_count > 0)) ||
    fail "the requested releases contain no provider or requestor bundles"

copied=0
skipped=0

while IFS=$'\t' read -r tag asset_id asset_name expected_size digest; do
    [[ "$asset_name" != */* && -n "$asset_name" ]] ||
        fail "unsafe GitHub asset name: $asset_name"
    [[ "$expected_size" =~ ^[0-9]+$ ]] ||
        fail "invalid size for GitHub asset $asset_name: $expected_size"

    if [[ -n "$prefix" ]]; then
        object_key="$prefix/$asset_name"
    else
        object_key="$asset_name"
    fi
    object_uri="s3://$bucket/$object_key"
    head_json="$tmp_dir/head-$asset_id.json"
    head_error="$tmp_dir/head-$asset_id.err"
    object_exists=false

    if aws s3api head-object \
        --bucket "$bucket" \
        --key "$object_key" \
        --output json >"$head_json" 2>"$head_error"; then
        object_exists=true
    elif ! grep -Eq '(^|[^0-9])404([^0-9]|$)|Not Found|NoSuchKey' "$head_error"; then
        cat "$head_error" >&2
        fail "cannot check $object_uri"
    fi

    if [[ "$object_exists" == "true" && "$force" == "false" ]]; then
        remote_size="$(jq -r '.ContentLength' "$head_json")"
        if [[ "$remote_size" != "$expected_size" ]]; then
            fail "$object_uri exists with size $remote_size, expected $expected_size; use --force to replace it"
        fi
        printf 'skip  %s (already present, %s bytes)\n' "$object_uri" "$remote_size"
        ((skipped += 1))
        continue
    fi

    if [[ "$dry_run" == "true" ]]; then
        if [[ "$object_exists" == "true" ]]; then
            printf 'would replace %s (%s bytes)\n' "$object_uri" "$expected_size"
        else
            printf 'would copy    %s (%s bytes)\n' "$object_uri" "$expected_size"
        fi
        ((copied += 1))
        continue
    fi

    download="$tmp_dir/asset-$asset_id"
    printf 'fetch %s release %s\n' "$asset_name" "$tag"
    if ! gh api \
        -H 'Accept: application/octet-stream' \
        "repos/$repository/releases/assets/$asset_id" >"$download"; then
        fail "cannot download GitHub asset $asset_name"
    fi

    actual_size="$(wc -c <"$download")"
    [[ "$actual_size" == "$expected_size" ]] ||
        fail "downloaded $asset_name has size $actual_size, expected $expected_size"

    if [[ "$digest" == sha256:* ]]; then
        expected_digest="${digest#sha256:}"
        actual_digest="$(sha256_file "$download")"
        [[ "$actual_digest" == "$expected_digest" ]] ||
            fail "SHA-256 mismatch for $asset_name"
    fi

    printf 'copy  %s\n' "$object_uri"
    aws s3 cp "$download" "$object_uri" \
        --only-show-errors \
        --cache-control "$cache_control" \
        --metadata \
        "github-repository=$repository,github-release-tag=$tag,github-asset-id=$asset_id"

    uploaded_size="$(aws s3api head-object \
        --bucket "$bucket" \
        --key "$object_key" \
        --query ContentLength \
        --output text)"
    [[ "$uploaded_size" == "$expected_size" ]] ||
        fail "uploaded $object_uri has size $uploaded_size, expected $expected_size"

    ((copied += 1))
done <"$manifest"

printf 'done: %s copied, %s skipped\n' "$copied" "$skipped"
