import hmac
import ipaddress
import json
import os
import time

import boto3
from botocore.exceptions import ClientError

WAF = boto3.client("wafv2")
SSM = boto3.client("ssm")
DDB = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])

IP_SET_ID = os.environ["IP_SET_ID"]
IP_SET_NAME = os.environ["IP_SET_NAME"]
SCOPE = os.environ.get("SCOPE", "REGIONAL")
TOKEN_PARAM = os.environ["TOKEN_PARAM"]
DRY_RUN = os.environ.get("DRY_RUN", "true").lower() == "true"
TTL_SECONDS = int(os.environ.get("TTL_HOURS", "24")) * 3600
MAX_PER_HOUR = int(os.environ.get("MAX_PER_HOUR", "10"))
ALLOWLIST = [
    ipaddress.ip_network(x.strip())
    for x in os.environ.get("ALLOWLIST", "").split(",")
    if x.strip()
]

_token_cache = None


def log(**kw):
    print(json.dumps(kw, ensure_ascii=False))


def get_token():
    global _token_cache
    if _token_cache is None:
        r = SSM.get_parameter(Name=TOKEN_PARAM, WithDecryption=True)
        _token_cache = r["Parameter"]["Value"]
    return _token_cache


def resp(code, body):
    return {"statusCode": code, "body": json.dumps(body)}


def update_ip_set(mutate):
    """LockToken 충돌 시 3번까지 재시도. mutate(set) -> set"""
    for _ in range(3):
        cur = WAF.get_ip_set(Name=IP_SET_NAME, Scope=SCOPE, Id=IP_SET_ID)
        addrs = mutate(set(cur["IPSet"]["Addresses"]))
        try:
            WAF.update_ip_set(
                Name=IP_SET_NAME, Scope=SCOPE, Id=IP_SET_ID,
                Addresses=sorted(addrs), LockToken=cur["LockToken"],
            )
            return
        except ClientError as e:
            if e.response["Error"]["Code"] != "WAFOptimisticLockException":
                raise
    raise RuntimeError("update_ip_set: lock retry exhausted")


def validate(ip_str):
    try:
        ip = ipaddress.ip_address(ip_str)
    except ValueError:
        return None, "invalid ip"
    if ip.version != 4:
        return None, "ipv4 only"
    if not ip.is_global:
        return None, "not public ip"
    if any(ip in net for net in ALLOWLIST):
        return None, "allowlisted"
    return ip, None


def handle_block(event):
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    if not hmac.compare_digest(headers.get("x-auth-token", ""), get_token()):
        log(action="reject", reason="bad token")
        return resp(403, {"error": "forbidden"})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return resp(400, {"error": "bad json"})

    ip, err = validate(str(body.get("ip", "")))
    if err:
        log(action="reject", ip=body.get("ip"), reason=err)
        return resp(400, {"error": err})

    cidr = f"{ip}/32"
    now = int(time.time())

    recent = DDB.scan(
        FilterExpression="created_at > :t",
        ExpressionAttributeValues={":t": now - 3600},
    )["Count"]
    if recent >= MAX_PER_HOUR:
        log(action="reject", ip=str(ip), reason="hourly cap")
        return resp(429, {"error": "hourly cap reached"})

    if DDB.get_item(Key={"ip": cidr}).get("Item"):
        log(action="skip", ip=str(ip), reason="already blocked")
        return resp(200, {"status": "already_blocked"})

    if DRY_RUN:
        log(action="dry_run_block", ip=str(ip), reason=body.get("reason"),
            source_rule=body.get("source_rule"))
        return resp(200, {"status": "dry_run", "ip": str(ip)})

    update_ip_set(lambda s: s | {cidr})
    DDB.put_item(Item={
        "ip": cidr, "created_at": now, "expires_at": now + TTL_SECONDS,
        "reason": str(body.get("reason", ""))[:200],
        "source_rule": str(body.get("source_rule", ""))[:50],
    })
    log(action="block", ip=str(ip), reason=body.get("reason"),
        expires_at=now + TTL_SECONDS)
    return resp(200, {"status": "blocked", "ip": str(ip)})


def handle_cleanup():
    now = int(time.time())
    expired = DDB.scan(
        FilterExpression="expires_at < :n",
        ExpressionAttributeValues={":n": now},
    )["Items"]
    if not expired:
        return {"removed": 0}
    cidrs = {i["ip"] for i in expired}
    update_ip_set(lambda s: s - cidrs)
    for c in cidrs:
        DDB.delete_item(Key={"ip": c})
    log(action="unblock_expired", ips=sorted(cidrs))
    return {"removed": len(cidrs)}


def lambda_handler(event, context):
    if event.get("source") == "aws.events":
        return handle_cleanup()
    return handle_block(event)