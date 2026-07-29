# ya-installer

Generate provider and requestor installers for a single Yagna release:

```shell
python gen.py v0.17.7
```

This writes `dist/as-provider` and `dist/as-requestor`. Both installers are
pinned to the supplied version and download the Yagna bundle from
`https://golem-releases.cdn.golem.network/yagna/`.
