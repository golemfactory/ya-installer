# ya-installer

Generate provider and requestor installers for a single Yagna release:

```shell
python gen.py v0.17.7
```

This writes `dist/as-provider` and `dist/as-requestor`. Both installers default
to the supplied version, allow overriding it with `YA_INSTALLER_CORE`, and
download the Yagna bundle from `https://golem-releases.cdn.golem.network/yagna/`.

## Mirror Yagna release bundles to S3

Because `golemfactory/yagna` is private, copy the provider and requestor bundles
for each new release to the public release bucket:

```shell
GH_TOKEN=... AWS_PROFILE=... ./sync-yagna-releases.sh v0.17.7
```

When `YA_INSTALLER_CORE` is already set, the tag argument can be omitted:

```shell
YA_INSTALLER_CORE=v0.17.7 GH_TOKEN=... AWS_PROFILE=... ./sync-yagna-releases.sh
```

Install the repository-local AWS CLI v2 configured in `mise.toml`:

```shell
mise install
```

The script also requires Bash, GitHub CLI (`gh`), and `jq`. Authenticate `gh`
or set `GH_TOKEN` to a token with Contents read access to the private repository.
The AWS credentials must allow `s3:GetObject` and `s3:PutObject` for
`s3://golem-releases/yagna/`. The script accepts multiple release tags (or a
single tag from `YA_INSTALLER_CORE`), skips objects that are already present
with the expected size, and supports `--dry-run` and `--force`.

Only `golem-provider-*` and `golem-requestor-*` release bundles (`.tar.gz` and
`.zip`) are mirrored; unrelated release assets are not made public.
