#! /bin/bash

SAVED_BRANCH=$(git rev-parse --abbrev-ref HEAD)

git branch -D tmp
git checkout -b tmp

python3.8 gen.py || exit 1

git add dist/as-provider dist/as-requestor dist/dev/as-provider dist/dev/as-requestor
git commit --no-verify -m "update"

#git subtree push -f --prefix dist origin gh-pages
git push origin `git subtree split --prefix dist tmp`:gh-pages --force
git checkout $SAVED_BRANCH
