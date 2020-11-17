#! /bin/bash

read -rp "Consider useing manual GitHub action instead
https://github.com/golemfactory/ya-installer/actions?query=workflow%3A%22Update+installer%22
Are you sure you want to continue (yes/no)?
" yn
case $yn in
    Yes|yes|YES) ;;
    * ) exit;;
esac

SAVED_BRANCH=$(git rev-parse --abbrev-ref HEAD)

git branch -D tmp
git checkout -b tmp

python3.8 gen.py || exit 1

cp setup-kvm.sh dist
git add dist/as-provider dist/as-requestor dist/dev/as-provider dist/dev/as-requestor dist/setup-kvm.sh
git commit --no-verify -m "updated from console"

git push origin "$(git subtree split --prefix dist tmp)":gh-pages --force
git checkout "${SAVED_BRANCH}"
