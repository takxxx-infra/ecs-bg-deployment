import os
import sys
import types
import unittest
from unittest.mock import MagicMock, call, patch


TEST_ENV = {
    "APPROVAL_SNS_TOPIC_ARN": "arn:aws:sns:ap-northeast-1:123456789012:approval-topic",
    "APPROVAL_PARAMETER_PREFIX": "/ecs-bg-approval",
    "CALLBACK_DELAY_SECONDS": "0",
    "ACTION_GROUP": "ecs-bg-approval",
    "APPROVAL_VALUE": "approved",
    "ROLLBACK_VALUE": "rollback",
    "AWS_DEFAULT_REGION": "ap-northeast-1",
}

with patch.dict(os.environ, TEST_ENV, clear=False):
    boto3_stub = types.ModuleType("boto3")
    boto3_stub.client = MagicMock(side_effect=lambda service_name: MagicMock(name=f"{service_name}_client"))

    botocore_stub = types.ModuleType("botocore")
    botocore_exceptions_stub = types.ModuleType("botocore.exceptions")

    class FakeClientError(Exception):
        def __init__(self, error_response, operation_name):
            super().__init__(operation_name)
            self.response = error_response
            self.operation_name = operation_name

    botocore_exceptions_stub.ClientError = FakeClientError

    with patch.dict(
        sys.modules,
        {
            "boto3": boto3_stub,
            "botocore": botocore_stub,
            "botocore.exceptions": botocore_exceptions_stub,
        },
    ):
        import lambda_src.lifecycle_hook_handler as handler


SERVICE_ARN = "arn:aws:ecs:ap-northeast-1:123456789012:service/sample-cluster/sample-service"
TARGET_REVISION_ARN = (
    "arn:aws:ecs:ap-northeast-1:123456789012:service-revision/"
    "sample-cluster/sample-service/1234567890"
)
SERVICE_DEPLOYMENT_ARN = (
    "arn:aws:ecs:ap-northeast-1:123456789012:service-deployment/"
    "sample-cluster/sample-service/dep-123"
)
APPROVAL_PARAMETER_NAME = "/ecs-bg-approval/sample-cluster/sample-service/dep-123/approved"
ROLLBACK_PARAMETER_NAME = "/ecs-bg-approval/sample-cluster/sample-service/dep-123/rollback"
NOTIFICATION_MARKER_NAME = "/ecs-bg-approval/sample-cluster/sample-service/dep-123/notification-sent"

EVENT = {
    "detail": {
        "serviceArn": SERVICE_ARN,
        "targetServiceRevisionArn": TARGET_REVISION_ARN,
    }
}


class LifecycleHookHandlerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.resolve_patcher = patch.object(
            handler,
            "_resolve_service_deployment",
            return_value={"serviceDeploymentArn": SERVICE_DEPLOYMENT_ARN},
        )
        self.describe_patcher = patch.object(
            handler,
            "_describe_service_deployment",
            return_value={"sourceServiceRevisions": [{"arn": "source-revision"}]},
        )
        self.parameter_exists_patcher = patch.object(
            handler,
            "_parameter_exists",
            side_effect=[False, False],
        )
        self.create_marker_patcher = patch.object(
            handler,
            "_create_notification_marker",
            return_value=True,
        )
        self.publish_patcher = patch.object(handler, "_publish_notification")
        self.delete_parameter_patcher = patch.object(handler, "_delete_parameter")

        self.mock_resolve = self.resolve_patcher.start()
        self.mock_describe = self.describe_patcher.start()
        self.mock_parameter_exists = self.parameter_exists_patcher.start()
        self.mock_create_marker = self.create_marker_patcher.start()
        self.mock_publish = self.publish_patcher.start()
        self.mock_delete_parameter = self.delete_parameter_patcher.start()

    def tearDown(self) -> None:
        patch.stopall()

    def test_returns_failed_and_cleans_up_when_rollback_parameter_exists(self) -> None:
        self.mock_parameter_exists.side_effect = [True]

        response = handler.lambda_handler(EVENT, None)

        self.assertEqual(response, {"hookStatus": "FAILED"})
        self.mock_describe.assert_not_called()
        self.mock_publish.assert_not_called()
        self.mock_delete_parameter.assert_has_calls(
            [
                call(APPROVAL_PARAMETER_NAME),
                call(ROLLBACK_PARAMETER_NAME),
                call(NOTIFICATION_MARKER_NAME),
            ]
        )
        self.assertEqual(self.mock_delete_parameter.call_count, 3)

    def test_returns_succeeded_and_cleans_up_when_approval_parameter_exists(self) -> None:
        self.mock_parameter_exists.side_effect = [False, True]

        response = handler.lambda_handler(EVENT, None)

        self.assertEqual(response, {"hookStatus": "SUCCEEDED"})
        self.mock_describe.assert_not_called()
        self.mock_publish.assert_not_called()
        self.mock_delete_parameter.assert_has_calls(
            [
                call(APPROVAL_PARAMETER_NAME),
                call(ROLLBACK_PARAMETER_NAME),
                call(NOTIFICATION_MARKER_NAME),
            ]
        )
        self.assertEqual(self.mock_delete_parameter.call_count, 3)

    def test_initial_deployment_skips_notification_and_succeeds(self) -> None:
        self.mock_parameter_exists.side_effect = [False, False]
        self.mock_describe.return_value = {"sourceServiceRevisions": []}

        response = handler.lambda_handler(EVENT, None)

        self.assertEqual(response, {"hookStatus": "SUCCEEDED"})
        self.mock_create_marker.assert_not_called()
        self.mock_publish.assert_not_called()
        self.mock_delete_parameter.assert_has_calls(
            [
                call(APPROVAL_PARAMETER_NAME),
                call(ROLLBACK_PARAMETER_NAME),
                call(NOTIFICATION_MARKER_NAME),
            ]
        )
        self.assertEqual(self.mock_delete_parameter.call_count, 3)

    def test_normal_deployment_uses_ecs_default_retry_interval_when_delay_is_zero(self) -> None:
        self.mock_parameter_exists.side_effect = [False, False]
        self.mock_describe.return_value = {"sourceServiceRevisions": [{"arn": "source-revision"}]}

        response = handler.lambda_handler(EVENT, None)

        self.assertEqual(response, {"hookStatus": "IN_PROGRESS"})
        self.mock_create_marker.assert_called_once_with(NOTIFICATION_MARKER_NAME)
        self.mock_publish.assert_called_once()
        self.mock_delete_parameter.assert_not_called()

    def test_normal_deployment_includes_callback_delay_when_positive(self) -> None:
        self.mock_parameter_exists.side_effect = [False, False]
        self.mock_describe.return_value = {"sourceServiceRevisions": [{"arn": "source-revision"}]}

        with patch.object(handler, "CALLBACK_DELAY_SECONDS", 45):
            response = handler.lambda_handler(EVENT, None)

        self.assertEqual(
            response,
            {
                "hookStatus": "IN_PROGRESS",
                "callBackDelay": 45,
            },
        )
        self.mock_create_marker.assert_called_once_with(NOTIFICATION_MARKER_NAME)
        self.mock_publish.assert_called_once()
        self.mock_delete_parameter.assert_not_called()

    def test_publish_failure_rolls_back_notification_marker_only(self) -> None:
        self.mock_parameter_exists.side_effect = [False, False]
        self.mock_describe.return_value = {"sourceServiceRevisions": [{"arn": "source-revision"}]}
        self.mock_publish.side_effect = RuntimeError("publish failed")

        response = handler.lambda_handler(EVENT, None)

        self.assertEqual(response, {"hookStatus": "FAILED"})
        self.mock_create_marker.assert_called_once_with(NOTIFICATION_MARKER_NAME)
        self.mock_delete_parameter.assert_called_once_with(NOTIFICATION_MARKER_NAME)

    def test_cleanup_helper_deletes_duplicate_names_once(self) -> None:
        handler._cleanup_deployment_parameters(
            APPROVAL_PARAMETER_NAME,
            ROLLBACK_PARAMETER_NAME,
            APPROVAL_PARAMETER_NAME,
        )

        self.mock_delete_parameter.assert_has_calls(
            [
                call(APPROVAL_PARAMETER_NAME),
                call(ROLLBACK_PARAMETER_NAME),
            ]
        )
        self.assertEqual(self.mock_delete_parameter.call_count, 2)


if __name__ == "__main__":
    unittest.main()
