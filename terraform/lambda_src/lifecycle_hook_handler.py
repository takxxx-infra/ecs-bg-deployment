from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore.exceptions import ClientError

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

# ECS の poll 型 lifecycle hook は同じ deployment に対して複数回呼ばれるため、
# 承認状態は deployment ごとの SSM パラメータで管理する。
SNS_TOPIC_ARN = os.environ["APPROVAL_SNS_TOPIC_ARN"]
APPROVAL_PARAMETER_PREFIX = os.environ["APPROVAL_PARAMETER_PREFIX"].rstrip("/")
CALLBACK_DELAY_SECONDS = int(os.environ["CALLBACK_DELAY_SECONDS"])
ACTION_GROUP = os.environ.get("ACTION_GROUP", "ecs-bg-approval")
APPROVAL_VALUE = os.environ.get("APPROVAL_VALUE", "approved")
ROLLBACK_VALUE = os.environ.get("ROLLBACK_VALUE", "rollback")

SSM = boto3.client("ssm")
SNS = boto3.client("sns")
ECS = boto3.client("ecs")


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    LOGGER.info("Received event: %s", json.dumps(event, default=str))

    try:
        # EventBridge / Lambda direct invoke / JSON 文字列ネストなど、
        # ECS から渡される event 形式の揺れをここで吸収する。
        payload = _event_payload(event)
        hook_details = _coerce_mapping(_find_first(event, "hookDetails") or {})

        service_arn = _first_non_empty(
            _find_first(payload, "serviceArn"),
            _find_first(event, "serviceArn"),
        )
        target_revision_arn = _first_non_empty(
            _find_first(payload, "targetServiceRevisionArn"),
            _find_first(event, "targetServiceRevisionArn"),
        )
        cluster_arn = _first_non_empty(
            _find_first(payload, "clusterArn"),
            _find_first(event, "clusterArn"),
        )

        if not service_arn and target_revision_arn:
            service_arn = _service_arn_from_service_revision_arn(target_revision_arn)

        if not cluster_arn and target_revision_arn:
            cluster_arn = _cluster_arn_from_service_revision_arn(target_revision_arn)

        if not service_arn:
            service_name = _first_non_empty(hook_details.get("ServiceName"))
            cluster_arn_from_hook = _first_non_empty(hook_details.get("ClusterArn"))
            if service_name and cluster_arn_from_hook:
                service_arn = _service_arn_from_cluster_arn(cluster_arn_from_hook, service_name)
                cluster_arn = cluster_arn or cluster_arn_from_hook

        if not service_arn:
            raise ValueError("serviceArn is required in the lifecycle hook event")

        if not cluster_arn:
            cluster_arn = _cluster_arn_from_service_arn(service_arn)

        cluster_name, service_name = _parse_service_identity(service_arn)
        deployment = _resolve_service_deployment(cluster_arn, service_arn, target_revision_arn)

        if deployment is None:
            raise RuntimeError("Could not resolve the active ECS service deployment")

        service_deployment_arn = deployment["serviceDeploymentArn"]
        deployment_id = service_deployment_arn.rsplit("/", 1)[-1]
        action_group = hook_details.get("ActionGroup", ACTION_GROUP)

        approval_parameter_name = _parameter_name(
            cluster_name,
            service_name,
            deployment_id,
            "approved",
        )
        rollback_parameter_name = _parameter_name(
            cluster_name,
            service_name,
            deployment_id,
            "rollback",
        )
        notification_marker_name = _parameter_name(
            cluster_name,
            service_name,
            deployment_id,
            "notification-sent",
        )
        parameter_names = (
            approval_parameter_name,
            rollback_parameter_name,
            notification_marker_name,
        )

        # ロールバック要求は承認より優先して扱う。
        if _parameter_exists(rollback_parameter_name):
            LOGGER.info(
                "Rollback parameter already exists. service=%s deployment=%s parameter=%s",
                service_name,
                deployment_id,
                rollback_parameter_name,
            )
            _cleanup_deployment_parameters(*parameter_names)
            return _response("FAILED")

        if _parameter_exists(approval_parameter_name):
            LOGGER.info(
                "Approval parameter already exists. service=%s deployment=%s parameter=%s",
                service_name,
                deployment_id,
                approval_parameter_name,
            )
            _cleanup_deployment_parameters(*parameter_names)
            return _response("SUCCEEDED")

        # 初回デプロイ時は比較対象の source revision が存在しないため、
        # 再ルーティング待ちにせずそのまま次の stage へ進める。
        deployment_detail = _describe_service_deployment(service_deployment_arn)
        if _is_initial_deployment(deployment_detail):
            LOGGER.info(
                "Initial deployment detected. service=%s deployment=%s",
                service_name,
                deployment_id,
            )
            _cleanup_deployment_parameters(*parameter_names)
            return _response("SUCCEEDED")

        should_notify = _create_notification_marker(notification_marker_name)
        if should_notify:
            try:
                _publish_notification(
                    cluster_arn=cluster_arn,
                    cluster_name=cluster_name,
                    service_arn=service_arn,
                    service_name=service_name,
                    deployment_id=deployment_id,
                    service_deployment_arn=service_deployment_arn,
                    approval_parameter_name=approval_parameter_name,
                    rollback_parameter_name=rollback_parameter_name,
                    action_group=action_group,
                )
            except Exception:
                _delete_parameter(notification_marker_name)
                raise
        else:
            LOGGER.info(
                "Notification already sent. service=%s deployment=%s marker=%s",
                service_name,
                deployment_id,
                notification_marker_name,
            )

        return _response("IN_PROGRESS", CALLBACK_DELAY_SECONDS)
    except Exception:
        LOGGER.exception("Lifecycle hook handler failed")
        return _response("FAILED")


def _event_payload(event: dict[str, Any]) -> dict[str, Any]:
    # ECS lifecycle hook event は detail / payload / body などに
    # 実データが入る場合があるため、先頭の dict payload を抽出する。
    if not isinstance(event, dict):
        return {}

    detail = event.get("detail")
    if isinstance(detail, dict):
        return detail

    for key in ("payload", "body", "input"):
        nested = event.get(key)
        if isinstance(nested, dict):
            return nested
        if isinstance(nested, str):
            try:
                decoded = json.loads(nested)
            except json.JSONDecodeError:
                continue
            if isinstance(decoded, dict):
                return decoded

    return event


def _first_non_empty(*values: Any) -> str | None:
    for value in values:
        if isinstance(value, str) and value:
            return value
    return None


def _coerce_mapping(value: Any) -> dict[str, str]:
    if isinstance(value, dict):
        return {str(key): str(item) for key, item in value.items()}
    if isinstance(value, str) and value:
        try:
            loaded = json.loads(value)
        except json.JSONDecodeError:
            return {}
        if isinstance(loaded, dict):
            return {str(key): str(item) for key, item in loaded.items()}
    return {}


def _find_first(value: Any, target_key: str) -> Any:
    if isinstance(value, dict):
        if target_key in value and value[target_key] not in (None, ""):
            return value[target_key]

        for nested in value.values():
            found = _find_first(nested, target_key)
            if found not in (None, ""):
                return found

    if isinstance(value, list):
        for item in value:
            found = _find_first(item, target_key)
            if found not in (None, ""):
                return found

    if isinstance(value, str):
        try:
            decoded = json.loads(value)
        except json.JSONDecodeError:
            return None
        return _find_first(decoded, target_key)

    return None


def _cluster_arn_from_service_arn(service_arn: str) -> str:
    arn_parts = service_arn.split(":", 5)
    if len(arn_parts) != 6:
        raise ValueError(f"Unexpected service ARN: {service_arn}")

    resource_parts = arn_parts[5].split("/")
    if len(resource_parts) < 3 or resource_parts[0] != "service":
        raise ValueError(f"Unexpected service ARN resource: {service_arn}")

    partition = arn_parts[1]
    region = arn_parts[3]
    account_id = arn_parts[4]
    cluster_name = resource_parts[1]
    return f"arn:{partition}:ecs:{region}:{account_id}:cluster/{cluster_name}"


def _cluster_arn_from_service_revision_arn(service_revision_arn: str) -> str:
    partition, region, account_id, cluster_name, _service_name = _parse_service_revision_identity(service_revision_arn)
    return f"arn:{partition}:ecs:{region}:{account_id}:cluster/{cluster_name}"


def _service_arn_from_service_revision_arn(service_revision_arn: str) -> str:
    partition, region, account_id, cluster_name, service_name = _parse_service_revision_identity(service_revision_arn)
    return f"arn:{partition}:ecs:{region}:{account_id}:service/{cluster_name}/{service_name}"


def _service_arn_from_cluster_arn(cluster_arn: str, service_name: str) -> str:
    arn_parts = cluster_arn.split(":", 5)
    if len(arn_parts) != 6:
        raise ValueError(f"Unexpected cluster ARN: {cluster_arn}")

    resource_parts = arn_parts[5].split("/")
    if len(resource_parts) < 2 or resource_parts[0] != "cluster":
        raise ValueError(f"Unexpected cluster ARN resource: {cluster_arn}")

    partition = arn_parts[1]
    region = arn_parts[3]
    account_id = arn_parts[4]
    cluster_name = resource_parts[1]
    return f"arn:{partition}:ecs:{region}:{account_id}:service/{cluster_name}/{service_name}"


def _region_and_account_from_arn(arn: str) -> tuple[str, str]:
    arn_parts = arn.split(":", 5)
    if len(arn_parts) != 6:
        raise ValueError(f"Unexpected ARN: {arn}")
    return arn_parts[3], arn_parts[4]


def _parse_service_identity(service_arn: str) -> tuple[str, str]:
    resource = service_arn.split(":", 5)[5]
    resource_parts = resource.split("/")
    if len(resource_parts) < 3 or resource_parts[0] != "service":
        raise ValueError(f"Unexpected service ARN resource: {service_arn}")
    return resource_parts[1], resource_parts[2]


def _parse_service_revision_identity(service_revision_arn: str) -> tuple[str, str, str, str, str]:
    arn_parts = service_revision_arn.split(":", 5)
    if len(arn_parts) != 6:
        raise ValueError(f"Unexpected service revision ARN: {service_revision_arn}")

    resource_parts = arn_parts[5].split("/")
    if len(resource_parts) < 3 or resource_parts[0] != "service-revision":
        raise ValueError(f"Unexpected service revision ARN resource: {service_revision_arn}")

    return arn_parts[1], arn_parts[3], arn_parts[4], resource_parts[1], resource_parts[2]


def _resolve_service_deployment(
    cluster_arn: str,
    service_arn: str,
    target_revision_arn: str | None,
) -> dict[str, Any] | None:
    # list_service_deployments は詳細情報が少ないため、
    # まず対象 deployment ARN を引く用途に限定して使う。
    deployments: list[dict[str, Any]] = []
    next_token: str | None = None

    while True:
        params: dict[str, Any] = {
            "cluster": cluster_arn,
            "service": service_arn,
            "status": ["IN_PROGRESS", "PENDING"],
        }
        if next_token:
            params["nextToken"] = next_token

        response = ECS.list_service_deployments(**params)
        deployments.extend(response.get("serviceDeployments", []))
        next_token = response.get("nextToken")
        if not next_token:
            break

    if not deployments:
        return None

    if target_revision_arn:
        for deployment in deployments:
            if deployment.get("targetServiceRevisionArn") == target_revision_arn:
                return deployment

    epoch = datetime(1970, 1, 1, tzinfo=timezone.utc)
    return max(deployments, key=lambda item: item.get("createdAt") or epoch)


def _describe_service_deployment(service_deployment_arn: str) -> dict[str, Any]:
    response = ECS.describe_service_deployments(serviceDeploymentArns=[service_deployment_arn])
    failures = response.get("failures", [])
    if failures:
        reason = failures[0].get("reason", "Unknown failure")
        raise RuntimeError(
            f"Could not describe service deployment {service_deployment_arn}: {reason}"
        )

    deployments = response.get("serviceDeployments", [])
    if not deployments:
        raise RuntimeError(f"Service deployment not found: {service_deployment_arn}")

    return deployments[0]


def _parameter_name(cluster_name: str, service_name: str, deployment_id: str, suffix: str) -> str:
    return f"{APPROVAL_PARAMETER_PREFIX}/{cluster_name}/{service_name}/{deployment_id}/{suffix}"


def _parameter_exists(name: str) -> bool:
    try:
        SSM.get_parameter(Name=name)
        return True
    except ClientError as error:
        if error.response["Error"]["Code"] == "ParameterNotFound":
            return False
        raise


def _create_notification_marker(name: str) -> bool:
    try:
        SSM.put_parameter(Name=name, Value="sent", Type="String", Overwrite=False)
        return True
    except ClientError as error:
        if error.response["Error"]["Code"] == "ParameterAlreadyExists":
            return False
        raise


def _delete_parameter(name: str) -> None:
    try:
        SSM.delete_parameter(Name=name)
    except ClientError as error:
        if error.response["Error"]["Code"] != "ParameterNotFound":
            LOGGER.warning("Failed to delete parameter %s: %s", name, error)


def _cleanup_deployment_parameters(*names: str) -> None:
    # hook が終端状態になった時点で deployment 単位の状態を消し、
    # 古い承認・ロールバック要求が次回デプロイへ残らないようにする。
    for name in dict.fromkeys(names):
        _delete_parameter(name)


def _is_initial_deployment(deployment: dict[str, Any]) -> bool:
    source_service_revisions = deployment.get("sourceServiceRevisions")
    if isinstance(source_service_revisions, list):
        return len(source_service_revisions) == 0

    # ドキュメントや SDK の表記差分に備えて単数形も許容する。
    legacy_source_revision = deployment.get("sourceServiceRevision")
    if isinstance(legacy_source_revision, dict):
        return len(legacy_source_revision) == 0

    return legacy_source_revision is None


def _publish_notification(
    *,
    cluster_arn: str,
    cluster_name: str,
    service_arn: str,
    service_name: str,
    deployment_id: str,
    service_deployment_arn: str,
    approval_parameter_name: str,
    rollback_parameter_name: str,
    action_group: str,
) -> None:
    # Slack の custom action から承認/ロールバック対象を引けるように、
    # deployment ごとの SSM パラメータ名を additionalContext に載せる。
    region, account_id = _region_and_account_from_arn(service_arn)

    message = {
        "version": "1.0",
        "source": "custom",
        "content": {
            "textType": "client-markdown",
            "title": "ECS Blue/Green 再ルーティング承認待ち",
            "description": (
                f"AccountId: `{account_id}`\n"
                f"Region: `{region}`\n"
                f"ClusterName: `{cluster_name}`\n"
                f"ServiceName: `{service_name}`\n"
                f"DeploymentId: `{deployment_id}`"
            ),
            "nextSteps": [
                "問題がなければ `再ルーティング` を選択してください。",
                "切り戻す場合は `ロールバック` を選択してください。",
            ],
            "keywords": [
                "ecs",
                "blue-green",
                "approval",
            ],
        },
        "metadata": {
            "summary": f"ECS deployment {deployment_id} is waiting for approval.",
            "threadId": f"ecs-bg-approval:{deployment_id}",
            "enableCustomActions": True,
            "additionalContext": {
                "ActionGroup": action_group,
                "ClusterArn": cluster_arn,
                "ClusterName": cluster_name,
                "DeploymentId": deployment_id,
                "ParameterName": approval_parameter_name,
                "RollbackParameterName": rollback_parameter_name,
                "ServiceArn": service_arn,
                "ServiceDeploymentArn": service_deployment_arn,
                "ServiceName": service_name,
                "ApprovalValue": APPROVAL_VALUE,
                "RollbackValue": ROLLBACK_VALUE,
            },
        },
    }

    SNS.publish(TopicArn=SNS_TOPIC_ARN, Message=json.dumps(message, ensure_ascii=False))


def _response(hook_status: str, callback_delay: int | None = None) -> dict[str, Any]:
    response: dict[str, Any] = {"hookStatus": hook_status}
    # 0 以下は「独自 delay を返さず、ECS の既定間隔に任せる」扱いにする。
    if callback_delay is not None and callback_delay > 0:
        response["callBackDelay"] = callback_delay
    return response
