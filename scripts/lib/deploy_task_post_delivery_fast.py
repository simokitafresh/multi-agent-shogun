"""Fast, deterministic post-delivery classification for deploy_task notifications.

The shell implementation persists an inbox row before it can know whether the
wake-up watcher delivered its nudge.  This module keeps those two facts
separate and makes the message id the idempotency key.  It deliberately has no
filesystem or YAML side effects; callers own persistence and provide the
single send attempt through ``send``.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from hashlib import sha256
from typing import Callable, Optional


@dataclass(frozen=True)
class DeliveryRequest:
    target: str
    message: str
    msg_type: str
    sender: str
    action: str = ""
    message_id: Optional[str] = None

    @property
    def idempotency_key(self) -> str:
        if self.message_id:
            return self.message_id
        payload = "\0".join(
            (self.target, self.message, self.msg_type, self.sender, self.action)
        ).encode()
        return "msg_" + sha256(payload).hexdigest()[:24]


@dataclass(frozen=True)
class DeliveryAttempt:
    """Facts returned by the persistence/wake-up adapter after one attempt."""

    persisted: bool
    watcher_delayed: bool = False
    send_succeeded: bool = False


@dataclass(frozen=True)
class DeliveryResult:
    message_id: str
    target: str
    classification: str
    persisted: bool
    send_attempted: bool


@dataclass
class DeliveryLedger:
    """In-memory idempotency ledger; persist it alongside the inbox if needed."""

    delivered: set[str] = field(default_factory=set)
    persisted: set[str] = field(default_factory=set)

    def publish(
        self,
        request: DeliveryRequest,
        send: Callable[[DeliveryRequest], DeliveryAttempt],
    ) -> DeliveryResult:
        key = request.idempotency_key
        if key in self.delivered or key in self.persisted:
            return DeliveryResult(key, request.target, "duplicate", True, False)

        attempt = send(request)
        if attempt.persisted:
            self.persisted.add(key)

        if not attempt.persisted:
            classification = "failed"
        elif attempt.send_succeeded:
            classification = "delivered"
            self.delivered.add(key)
        elif attempt.watcher_delayed:
            classification = "watcher_delayed"
        else:
            # The row exists even when post-write verification failed.  A
            # later watcher retry must not create a second inbox message.
            classification = "persisted"

        return DeliveryResult(
            key, request.target, classification, attempt.persisted, True
        )


def publish_notification(
    request: DeliveryRequest,
    send: Callable[[DeliveryRequest], DeliveryAttempt],
    ledger: Optional[DeliveryLedger] = None,
) -> DeliveryResult:
    """Publish one notification while preserving fixed-SHA delivery semantics."""

    return (ledger or DeliveryLedger()).publish(request, send)


__all__ = [
    "DeliveryAttempt",
    "DeliveryLedger",
    "DeliveryRequest",
    "DeliveryResult",
    "publish_notification",
]
