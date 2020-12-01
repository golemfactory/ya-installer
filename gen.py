from dataclasses import dataclass, fields as datafields
from pathlib import Path
from typing import List, Union
from urllib import request
import json


@dataclass
class Repo:
    id: int
    url: str
    assets_url: str
    tag_name: str
    name: str
    draft: bool
    prerelease: bool
    created_at: str


def dataclass_from_dict(klass, dikt: dict):
    fields = {f.name for f in datafields(klass)}
    return klass(**dict(((f, dikt[f]) for f in fields)))


def latest_release(owner: str, repo: str) -> Repo:
    response = request.urlopen(
        f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
    )
    data = json.loads(response.read())
    return dataclass_from_dict(Repo, data)


def list_releases(owner: str, repo: str) -> List[Repo]:
    response = request.urlopen(f"https://api.github.com/repos/{owner}/{repo}/releases")
    data = json.loads(response.read())
    assert isinstance(data, list)
    return [dataclass_from_dict(Repo, item) for item in data]


def template(variant: str = "provider", select_version: Union[bool, str] = False):
    yield f"YA_INSTALLER_VARIANT={variant}"
    if select_version == True:
        versions = list_releases("golemfactory", "yagna")[:5]
        yield "select_version() {"
        yield '  echo "available versions:"'
        for (i, version) in enumerate(versions):
            yield f'  echo "{i}) {version.name}"'
        yield "  while true; do"
        yield '    read -r -u 2 -p "Select version: " ANS || exit 1'
        yield '    case "$ANS" in'
        for (i, version) in enumerate(versions):
            ver_name = version.tag_name.lstrip("pre-rel-").lstrip("v")
            yield f"    {i})"
            yield f'    YA_INSTALLER_COREV="{ver_name}"'
            yield f'    YA_INSTALLER_CORE="{version.tag_name}"'
            yield "     return"
            yield ";;"
        yield "    esac"
        yield "  done"
        yield "}"
        yield "select_version || exit 1"
    else:
        last_version: str = (
            latest_release("golemfactory", "yagna").tag_name
            if not isinstance(select_version, str)
            else select_version
        )
        yield 'YA_INSTALLER_CORE="${YA_INSTALLER_CORE:-' + last_version + '}"'
        yield 'name=${YA_INSTALLER_CORE#pre-rel-}'
        yield 'YA_INSTALLER_COREV="${YA_INSTALLER_COREV:-${name#v}}"'


def emit_installer(variant: str = "provider", select_version: Union[bool, str] = False):
    with open("installer.sh", "r") as f:
        in_template = False
        for line in f.readlines():
            if line.startswith("## @@BEGIN@@"):
                in_template = True
                yield from template(variant, select_version)
                continue
            if line.startswith("## @@END@@"):
                in_template = False
                continue
            if not in_template:
                yield line.rstrip()


def gen_installer(variant: str = "provider", select_version: Union[bool, str] = False):
    prefix = "dist/dev/" if select_version == True else "dist/"
    name = f"as-{variant}"
    print(f" generating {prefix}{name}")
    Path(f"{prefix}").mkdir(parents=True, exist_ok=True)
    with open(f"{prefix}{name}", "wt") as f:
        f.writelines((l + "\n" for l in emit_installer(variant, select_version)))


if __name__ == "__main__":
    gen_installer("provider", select_version=True)
    gen_installer("requestor", select_version=True)
    gen_installer("provider")
    gen_installer("requestor")
