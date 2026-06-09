import boto3
import json
import os
import subprocess
import sys


def get_agent_arn():
    arn = os.environ.get("AGENT_RUNTIME_ARN")
    if not arn:
        result = subprocess.run(
            ["terraform", "output", "-raw", "agent_runtime_arn"],
            capture_output=True, text=True
        )
        arn = result.stdout.strip()
    return arn


AGENT_ARN = get_agent_arn()
REGION = "us-west-2"

client = boto3.client("bedrock-agentcore", region_name=REGION)
prompt = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else "Hello, what can you do?"

response = client.invoke_agent_runtime(
    agentRuntimeArn=AGENT_ARN,
    qualifier="DEFAULT",
    runtimeSessionId="a" * 33,
    payload=json.dumps({"prompt": prompt}).encode(),
)

for line in response["response"].iter_lines():
    if not line:
        continue
    text = line.decode("utf-8")
    if not text.startswith("data: "):
        continue
    data = text[6:]
    try:
        parsed = json.loads(data)
        if not isinstance(parsed, dict):
            continue
        # Extract text deltas from the streaming events
        event = parsed.get("event", {})
        delta = event.get("contentBlockDelta", {}).get("delta", {})
        if "text" in delta:
            print(delta["text"], end="", flush=True)
    except json.JSONDecodeError:
        pass

print()
