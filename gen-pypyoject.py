import sys, argparse, re

parser = argparse.ArgumentParser(description='pyproject generator for golem-node')
parser.add_argument('tag', type=str, help='release tag')

args = parser.parse_args()

p = re.compile(r"^(pre-rel-)?v([0-9]+\.[0-9]+\.[0-9]+)(-rc([0-9]+))?$")
x = p.match(args.tag)

if x is None:
    sys.exit(f'invalid version tag: {args.tag}')

rc = x.group(4)
if rc:
    py_ver = f"{x.group(2)}a{x.group(4)}"
else:
    py_ver = x.group(2)


print(f"""
[build-system]
requires = ["maturin>=1.0,<2.0"]
build-backend = "maturin"

[project]
name = "golem-node"
version = "{ py_ver }"
description = "golem-node"
readme = "README.md"
requires-python = ">=3.7"
license = {{ file = "LICENSE" }}
keywords = ["Golem"]
classifiers = [
  "Development Status :: 3 - Alpha",
  "Environment :: Console",
  "Intended Audience :: Developers",
  "License :: OSI Approved :: GNU General Public License v3 (GPLv3)",
  "Operating System :: OS Independent",
  "Programming Language :: Python",
  "Programming Language :: Python :: 3.7",
  "Programming Language :: Python :: 3.8",
  "Programming Language :: Python :: 3.9",
  "Programming Language :: Python :: 3.10",
  "Programming Language :: Python :: 3.11",
  "Programming Language :: Python :: 3 :: Only",
  "Programming Language :: Rust",
]
urls = {{ repository = "https://github.com/golemfactory/yagna" }}

[tool.maturin]
bindings = "bin"
manifest-path = "Cargo.toml"
python-source = "python"
strip = true

""")





