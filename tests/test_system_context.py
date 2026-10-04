import pytest


@pytest.fixture
def linux(agent, tmp_path, monkeypatch):
    """Pretend to be a Linux box described by a given os-release."""
    def make(os_release, which=(), systemd=True, wsl=False):
        rel = tmp_path / "os-release"
        rel.write_text(os_release)
        monkeypatch.setattr(agent, "OS_RELEASE", str(rel))
        monkeypatch.setattr(agent.sys, "platform", "linux")
        monkeypatch.setattr(agent.shutil, "which", lambda name: f"/usr/bin/{name}" if name in which else None)
        real_isdir, real_open = agent.os.path.isdir, open
        monkeypatch.setattr(agent.os.path, "isdir",
                            lambda p: systemd if p == "/run/systemd/system" else real_isdir(p))
        version = tmp_path / "version"
        version.write_text("Linux version 5.15 microsoft-standard-WSL2" if wsl else "Linux version 6.8")
        monkeypatch.setattr(agent, "open", lambda p, *a, **k: real_open(version if p == "/proc/version" else p, *a, **k),
                            raising=False)
        monkeypatch.setenv("TUXAIDE_SHELL", "bash")
        return agent.detect_system()
    return make


@pytest.mark.parametrize("os_release,which,pkg", [
    ('PRETTY_NAME="Ubuntu 24.04 LTS"\nID=ubuntu\nID_LIKE=debian\n', ["apt", "brew"], "apt"),
    ('PRETTY_NAME="Fedora Linux 40"\nID=fedora\n', ["dnf"], "dnf"),
    ('PRETTY_NAME="CentOS Linux 7"\nID=centos\nID_LIKE="rhel fedora"\n', ["yum"], "yum"),   # no dnf yet
    ('PRETTY_NAME="Arch Linux"\nID=arch\n', ["pacman"], "pacman"),
    ('PRETTY_NAME="Linux Mint 22"\nID=linuxmint\nID_LIKE="ubuntu debian"\n', ["apt"], "apt"),
    ('PRETTY_NAME="openSUSE Tumbleweed"\nID=opensuse-tumbleweed\nID_LIKE="opensuse suse"\n', ["zypper"], "zypper"),
    ('PRETTY_NAME="Some Distro"\nID=whatever\n', ["apk"], "apk"),                          # falls back to PATH
])
def test_package_manager_detection(linux, os_release, which, pkg):
    assert linux(os_release, which)["pkg"] == pkg


def test_wsl_and_init(linux):
    info = linux('PRETTY_NAME="Ubuntu 22.04"\nID=ubuntu\n', ["apt"], systemd=False, wsl=True)
    assert info["os"] == "Ubuntu 22.04 (WSL)" and info["init"] == ""


def test_summary_line(agent, linux):
    linux('PRETTY_NAME="Fedora Linux 40"\nID=fedora\n', ["dnf"])
    summary = agent.system_summary({})
    assert summary.startswith("Fedora Linux 40, package manager dnf, shell bash, init systemd, ")
    assert agent.system_summary({"system_context": False}) == ""


def test_summary_has_no_personal_details(agent, home, monkeypatch):
    monkeypatch.setenv("USER", "secretuser")
    summary = agent.system_summary({})
    import socket
    for private in ("secretuser", str(home), socket.gethostname()):
        assert private not in summary


def test_system_is_in_the_prompt_and_cache_key(run_agent, ollama, agent):
    run_agent("--ask", "how do I install htop")
    system_prompt = ollama.chat_requests()[-1]["messages"][0]["content"]
    assert f"The user's system: {agent.system_summary({})}" in system_prompt
    run_agent("--ask", "how do I install htop", config={"system_context": False})
    system_prompt = ollama.chat_requests()[-1]["messages"][0]["content"]
    assert "The user's system" not in system_prompt and "differs by distro" in system_prompt
    assert len(ollama.chat_requests()) == 2          # different system context → not the cached answer


def test_tuxaide_system_command(run_agent, agent):
    assert agent.system_summary({}) in run_agent("system").stdout
    assert "off" in run_agent("system", config={"system_context": False}).stdout
