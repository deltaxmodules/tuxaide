"""One version everywhere: agent.py's __version__ is the source of truth."""
import os
import re

from conftest import REPO


def read(name):
    with open(os.path.join(REPO, name), encoding="utf-8") as f:
        return f.read()


def version():
    return re.search(r'^__version__ = "([^"]+)"', read("agent.py"), re.M).group(1)


def test_installer_matches():
    assert re.search(r'^TUXAIDE_VERSION="([^"]+)"', read("install.sh"), re.M).group(1) == version()


def test_readme_matches():
    assert f"version-{version()}-" in read("README.md")


def test_no_stale_versions():
    for name in ("agent.py", "hook.sh", "install.sh", "README.md"):
        stale = [v for v in re.findall(r"\bv?2\.\d+(?:\.\d+)?\b", read(name)) if v.lstrip("v") != version()]
        assert not stale, f"{name}: {stale}"
