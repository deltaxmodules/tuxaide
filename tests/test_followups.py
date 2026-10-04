import json
import time

import pytest


@pytest.mark.parametrize("text", [
    "e por tamanho?", "and sorted by size", "what about hidden ones", "y para ordenar al revés",
    "et si je veux les trier", "und rekursiv?", "how do I reverse it", "isso funciona no mac?",
])
def test_followups_are_recognised(agent, text):
    assert agent.looks_like_followup(text)


@pytest.mark.parametrize("text", [
    "how do I list hidden files", "o que é o grep", "como ver o espaço em disco",
    "what is the difference between chmod and chown",
])
def test_new_questions_are_not_followups(agent, text):
    assert not agent.looks_like_followup(text)


@pytest.mark.parametrize("text,expected", [
    ("why did this fail", True),          # error word
    ("porque deu este erro?", True),
    ("why did that happen", True),        # why + pronoun
    ("and reverse it", False),            # a pronoun alone is a conversation follow-up
    ("isso funciona no mac?", False),
])
def test_last_error_detector_needs_more_than_a_pronoun(agent, text, expected):
    assert agent.ContextIntentDetector.looks_like_context_followup(text) is expected


def write_history(home, entries):
    (home / ".config" / "tuxaide" / "history.json").write_text(json.dumps(entries))


def test_recent_turns_respects_window_and_count(agent, home):
    now = time.time()
    write_history(home, [
        {"t": now - 3000, "q": "old", "a": "x"},                 # gap > window: conversation ended
        {"t": now - 400, "q": "q1", "a": "a1"},
        {"t": now - 300, "q": "q2", "a": "a2"},
        {"t": now - 200, "q": "q3", "a": "a3"},
        {"t": now - 100, "q": "q4", "a": "a4"},
    ])
    turns = agent.recent_turns({"followup_window": 600, "followup_turns": 3})
    assert [t["q"] for t in turns] == ["q2", "q3", "q4"]
    assert agent.recent_turns({"followup_window": 60}) == []     # last one too old
    assert agent.recent_turns({"followup_window": 0}) == []      # disabled


def test_history_file_is_private_and_bounded(agent, home):
    for i in range(25):
        agent.save_turn(f"q{i}", "a" * 1000)
    entries = json.loads((home / ".config" / "tuxaide" / "history.json").read_text())
    assert len(entries) == agent.HISTORY_KEEP and entries[-1]["q"] == "q24"
    assert len(entries[-1]["a"]) == agent.ANSWER_KEEP
    assert (home / ".config" / "tuxaide" / "history.json").stat().st_mode & 0o777 == 0o600


def test_followup_is_sent_with_previous_exchange(run_agent, ollama):
    ollama.answer = "```bash\nls -la\n```"
    run_agent("--ask", "how do I list hidden files")
    ollama.answer = "```bash\nls -laS\n```"
    p = run_agent("--ask", "e por tamanho?")
    assert "ls -laS" in p.stdout and "follow-up" in p.stdout
    msgs = ollama.chat_requests()[-1]["messages"]
    assert [m["role"] for m in msgs] == ["system", "user", "assistant", "user"]
    assert msgs[1]["content"] == "how do I list hidden files"
    assert "ls -la" in msgs[2]["content"]
    assert msgs[3]["content"] == "e por tamanho?"


def test_followups_are_not_cached(run_agent, ollama):
    run_agent("--ask", "how do I list hidden files")
    run_agent("--ask", "e por tamanho?")
    ollama.answer = "different"
    run_agent("--ask", "how do I list hidden files")             # cached: no new request
    p = run_agent("--ask", "e por tamanho?")                     # follow-up: asked again
    assert "different" in p.stdout
    assert len(ollama.chat_requests()) == 3


def test_new_question_is_sent_alone(run_agent, ollama):
    run_agent("--ask", "how do I list hidden files")
    run_agent("--ask", "how do I check disk space")
    assert len(ollama.chat_requests()[-1]["messages"]) == 2


def test_tuxaide_new_forgets_the_conversation(run_agent, ollama):
    run_agent("--ask", "how do I list hidden files")
    assert "New conversation" in run_agent("new").stdout
    run_agent("--ask", "e por tamanho?")
    assert len(ollama.chat_requests()[-1]["messages"]) == 2


def test_tuxaide_history_lists_questions(run_agent, ollama):
    assert "No questions yet" in run_agent("history").stdout
    run_agent("--ask", "how do I list hidden files")
    run_agent("--ask", "how do I check disk space")
    out = run_agent("history").stdout
    assert out.index("how do I list hidden files") < out.index("how do I check disk space")


def test_followup_without_question_mark_counts_only_in_open_conversation(run_agent, ollama, home):
    env = {"TUXAIDE_SHELL": "bash"}
    assert run_agent("--not-found", "and", "by", "size", env=env).returncode == 1   # nothing open
    run_agent("--ask", "how do I list hidden files")
    p = run_agent("--not-found", "and", "by", "size", env=env)
    assert p.returncode == 0
    assert ollama.chat_requests()[-1]["messages"][1]["content"] == "how do I list hidden files"


def test_question_mark_explanation_starts_a_conversation(run_agent, ollama, tmp_path):
    run_agent("--why", f"ls {tmp_path}/nope", "1", env={"SHELL": "/bin/sh"})
    run_agent("--ask", "and how do I fix it?")
    msgs = ollama.chat_requests()[-1]["messages"]
    assert len(msgs) == 4 and f"ls {tmp_path}/nope" in msgs[1]["content"]
