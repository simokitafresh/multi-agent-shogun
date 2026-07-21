"""Contract tests for the F1 post-delivery shard.

test_necessity: protects notification idempotency and persistence/delivery
classification, which are the owned invariants of this shard.
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parents[2] / "scripts" / "lib"))

from deploy_task_post_delivery_fast import (  # noqa: E402
    DeliveryAttempt,
    DeliveryLedger,
    DeliveryRequest,
    publish_notification,
)


def request(message_id="msg-1"):
    return DeliveryRequest("hanzo", "start", "task_assigned", "karo", "task_start", message_id)


def test_normal_delivery_preserves_target_and_message_id():
    calls = []
    result = publish_notification(
        request(),
        lambda item: (calls.append(item) or DeliveryAttempt(True, send_succeeded=True)),
    )
    assert result.classification == "delivered"
    assert result.message_id == "msg-1"
    assert result.target == "hanzo"
    assert len(calls) == 1


def test_duplicate_is_not_sent_twice():
    calls = []
    ledger = DeliveryLedger()
    send = lambda item: (calls.append(item) or DeliveryAttempt(True, send_succeeded=True))
    first = ledger.publish(request(), send)
    second = ledger.publish(request(), send)
    assert first.classification == "delivered"
    assert second.classification == "duplicate"
    assert len(calls) == 1


def test_watcher_delay_keeps_persisted_notification_retry_safe():
    calls = []
    ledger = DeliveryLedger()
    result = ledger.publish(
        request(),
        lambda item: (calls.append(item) or DeliveryAttempt(True, watcher_delayed=True)),
    )
    retry = ledger.publish(
        request(),
        lambda item: (calls.append(item) or DeliveryAttempt(True, send_succeeded=True)),
    )
    assert result.classification == "watcher_delayed"
    assert retry.classification == "duplicate"
    assert len(calls) == 1


def test_failed_send_is_distinct_from_persisted_delivery():
    ledger = DeliveryLedger()
    result = ledger.publish(request(), lambda _: DeliveryAttempt(False))
    assert result.classification == "failed"
    assert result.persisted is False
    assert result.send_attempted is True
