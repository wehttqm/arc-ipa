import boto3, os
from datetime import datetime, timezone, timedelta


def handler(event, context):
    ssm = boto3.client("ssm")
    param = os.environ["KILL_SWITCH_PARAM"]
    minutes = int(os.environ["COOLDOWN_MINUTES"])
    expiry = (datetime.now(timezone.utc) + timedelta(minutes=minutes)).isoformat()
    ssm.put_parameter(Name=param, Value=expiry, Type="String", Overwrite=True)
    print(f"Kill switch set, expires: {expiry}")
    return {"status": "cooldown active", "expires": expiry}
