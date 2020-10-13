#! /bin/bash

SAVED_BRANCH=$(git branch --show-current)

git branch -D tmp
git checkout -b tmp

cat installer.sh > dist/as-provider
sed 's/YA_INSTALLER_VARIANT=provider/YA_INSTALLER_VARIANT=requestor/' < installer.sh > dist/as-requestor

git add dist/as-provider dist/as-requestor
git commit --no-verify -m "update"

#git subtree push -f --prefix dist origin gh-pages
git push origin `git subtree split --prefix dist tmp`:gh-pages --force
git checkout $SAVED_BRANCH
