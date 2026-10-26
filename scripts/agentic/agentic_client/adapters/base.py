"""One interface for every vendor: run a turn (streaming events), pause, resume, stop, kill."""

from __future__ import annotations

import abc
from dataclasses import dataclass, field
from typing import Any, Callable

Event = dict[str, Any]
EmitFn = Callable[[Event], None]


class AdapterError(RuntimeError):
    pass


@dataclass
class TurnResult:
    text: str = ""
    aborted: bool = False
    error: str | None = None
    usage: dict[str, Any] | None = None
    extra: dict[str, Any] = field(default_factory=dict)


class Adapter(abc.ABC):
    #: True when resume must send the transcript again (no live process to continue).
    resume_reissues: bool = False

    @abc.abstractmethod
    def run_turn(self, system: str, messages: list[dict[str, str]], emit: EmitFn) -> TurnResult:
        """Send one turn and stream events through ``emit`` until it ends, aborts, or fails."""

    @abc.abstractmethod
    def pause(self) -> None: ...

    @abc.abstractmethod
    def resume(self) -> None: ...

    @abc.abstractmethod
    def stop(self) -> None: ...

    def kill(self) -> None:
        self.stop()


def total_tokens(usage: dict[str, Any] | None) -> int | None:
    """Pick a context size from a usage object, whatever the vendor calls it."""
    if not usage:
        return None
    for key in ("total_tokens", "totalTokens"):
        if isinstance(usage.get(key), int):
            return usage[key]
    parts = [
        usage.get(k)
        for k in ("prompt_tokens", "completion_tokens", "input_tokens", "output_tokens", "inputTokens", "outputTokens")
    ]
    nums = [p for p in parts if isinstance(p, int)]
    return sum(nums) if nums else None
