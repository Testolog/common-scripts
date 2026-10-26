"""Context-size tracking and the token-limit handoff."""

from __future__ import annotations

import math
import re
from typing import Any

from .adapters.base import total_tokens
from .state import (
    TRANSCRIPT,
    Agent,
    agentic_home_of,
    append_event,
    create_agent,
    mark_read_only,
    now_iso,
)

TASK = re.compile(r"^\s*[-*]\s+\[( |x|X)\]\s+(.+?)\s*$")
SUMMARY_TAIL_CHARS = 6000


def estimate_tokens(text: str) -> int:
    return math.ceil(len(text) / 4)


def update_tokens(agent: Agent, usage: dict[str, Any] | None, transcript_text: str) -> int:
    """Prefer usage reported by the stream; else estimate from the transcript."""
    reported = total_tokens(usage)
    if reported is not None:
        agent.meta["tokens"] = reported
        agent.meta["tokens_source"] = "usage"
    else:
        agent.meta["tokens"] = estimate_tokens(transcript_text)
        agent.meta["tokens_source"] = "estimate"
    return agent.meta["tokens"]


def at_limit(agent: Agent) -> bool:
    limit = agent.meta.get("context_limit")
    return bool(limit) and agent.meta.get("tokens", 0) >= limit


def open_tasks(transcript: str) -> list[str]:
    """Markdown checkboxes still unchecked at the end of the transcript, in first-seen order."""
    state: dict[str, bool] = {}
    for line in transcript.splitlines():
        m = TASK.match(line)
        if m:
            state[m.group(2)] = m.group(1).lower() == "x"
    return [task for task, done in state.items() if not done]


def handoff_summary(agent: Agent, transcript: str, tasks: list[str]) -> str:
    tail = transcript[-SUMMARY_TAIL_CHARS:]
    task_lines = "\n".join(f"- [ ] {t}" for t in tasks) or "- (none)"
    return (
        f"# Handoff from {agent.meta.get('name')} ({agent.id})\n\n"
        f"- created: {now_iso()}\n"
        f"- project_root: {agent.meta['project_root']}\n"
        f"- branch: {agent.meta['branch']}\n"
        f"- manager: {agent.meta['manager']}\n"
        f"- tokens: {agent.meta.get('tokens')} / {agent.meta.get('context_limit')}\n\n"
        f"## Open tasks\n\n{task_lines}\n\n"
        f"## Recent transcript\n\n{tail}\n"
    )


def handoff(agent: Agent) -> Agent:
    """Hand an agent at its token limit to a child under the same manager.

    Writes the summary into the manager folder, creates the child with the open task
    list and summary in its system preamble, marks the old transcript read-only, and
    emits a tree event. It never switches a visible buffer.
    """
    transcript = agent.path(TRANSCRIPT).read_text()
    tasks = open_tasks(transcript)
    summary = handoff_summary(agent, transcript, tasks)
    summary_path = agent.manager_dir / f"handoff-{agent.id}.md"
    summary_path.write_text(summary)

    task_lines = "\n".join(f"- [ ] {t}" for t in tasks) or "- (none)"
    preamble = (
        f"You continue the work of agent {agent.id}, which reached its context limit.\n\n"
        f"## Open tasks\n\n{task_lines}\n\n## Handoff summary\n\n{summary}"
    )
    child = create_agent(
        agent.meta["project_root"],
        name=f"{agent.meta.get('name', agent.id)} (cont.)",
        mode=agent.meta["mode"],
        model=agent.meta["model"],
        manager=agent.meta["manager"],
        prompts=agent.meta.get("prompts"),
        skills=agent.meta.get("skills"),
        preamble=preamble,
        parent=agent.id,
        home=agentic_home_of(agent),
        branch=agent.meta["branch"],
        project=agent.meta["project_name"],
    )
    child.meta["handoff_summary"] = str(summary_path)
    child.save()

    agent.meta.setdefault("children", []).append(child.id)
    agent.meta["handoff_to"] = child.id
    agent.meta["handoff_summary"] = str(summary_path)
    agent.meta["status"] = "handed_off"
    agent.meta["read_only"] = True
    agent.save()
    mark_read_only(agent.path(TRANSCRIPT))

    append_event(
        agent,
        {
            "type": "tree",
            "action": "handoff",
            "child_id": child.id,
            "manager": agent.meta["manager"],
            "summary": str(summary_path),
            "switch_buffer": False,
        },
    )
    return child
