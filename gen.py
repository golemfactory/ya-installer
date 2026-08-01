import argparse
import json
import re
from pathlib import Path


VERSION_PATTERN = re.compile(
    r"^(?:pre-rel-)?v[0-9]+\.[0-9]+\.[0-9]+"
    r"(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?$"
)


def installer_config_template(version: str, variant: str = "provider"):
    yield f'YA_INSTALLER_VARIANT="${{YA_INSTALLER_VARIANT:-{variant}}}"'
    yield f'YA_INSTALLER_CORE="${{YA_INSTALLER_CORE:-{version}}}"'


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
        if 'cmds' in command:
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
    for cmd in command['cmds']:
        yield f"    $_bin_dir/{cmd} >/dev/null 2>&1"

def emit_installer(version: str, variant: str = "provider"):
    with open("installer.sh", "r") as f:
        in_template = False
        for line in f.readlines():
            if line.startswith("## @@BEGIN_SELECT_VERSION@@"):
                in_template = True
                yield from installer_config_template(version, variant)
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


def gen_installer(version: str, variant: str = "provider"):
    prefix = "dist/"
    name = f"as-{variant}"
    print(f" generating {prefix}{name}")
    Path(f"{prefix}").mkdir(parents=True, exist_ok=True)
    with open(f"{prefix}{name}", "wt") as f:
        f.writelines((l + "\n" for l in emit_installer(version, variant)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate provider and requestor installers for one Yagna release"
    )
    parser.add_argument("version", help="Yagna release tag, for example v0.17.7")
    args = parser.parse_args()

    if VERSION_PATTERN.fullmatch(args.version) is None:
        parser.error(f"invalid Yagna release tag: {args.version}")

    gen_installer(args.version, "provider")
    gen_installer(args.version, "requestor")
