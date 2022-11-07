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


def select_version_template(variant: str = "provider", select_version: Union[bool, str] = False):
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
            yield f"    {i})"
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


def setup_provider_template():
    commands = open('commands.json')
    commands = json.load(commands)
    default_command = None
    first_if = True
    for command in commands['commands']:
        if 'default' in command and command['default'] == True:
            default_command = command
        version_patterns = version_patterns_str(command)
        if_or_elif = "if" if first_if else "elif"
        first_if = False
        yield       f"  {if_or_elif} {version_patterns}; then"
        if 'add_certs' in command or 'whitelist_regex' in command or 'whitelist_strict' in command:
            yield   from run_command(command)
        else:
            yield   "    :"
    if default_command != None:
        yield       "  else"
        yield       from run_command(default_command)
    yield           "  fi"

def version_patterns_str(command):
    version_patterns = []  
    for version in command['versions']:
        version_patterns.append(version_pattern(version))
    return " || ".join(version_patterns)

def version_pattern(version):
    return f"[[ \"${{YA_INSTALLER_CORE}}\" =~ .*{version}.* ]]"

def run_command(command):
    if 'add_certs' in command:
        yield f"    $_bin_dir/{command['add_certs']} >/dev/null 2>&1"
    if 'whitelist_regex' in command:
        yield f"    $_bin_dir/{command['whitelist_regex']} >/dev/null 2>&1"
    if 'whitelist_strict' in command:
        yield f"    $_bin_dir/{command['whitelist_strict']} >/dev/null 2>&1"

def emit_installer(variant: str = "provider", select_version: Union[bool, str] = False):
    with open("installer.sh", "r") as f:
        in_template = False
        for line in f.readlines():
            if line.startswith("## @@BEGIN_SELECT_VERSION@@"):
                in_template = True
                yield from select_version_template(variant, select_version)
                continue
            if line.startswith("## @@END_SELECT_VERSION@@"):
                in_template = False
                continue
            if line.startswith("## @@BEGIN_SETUP_PROVIDER@@"):
                in_template = True
                yield from setup_provider_template()
                continue
            if line.startswith("## @@END_SETUP_PROVIDER@@"):
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
