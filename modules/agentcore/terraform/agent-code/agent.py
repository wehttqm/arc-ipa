import os
import logging
from strands import Agent
from strands.models import BedrockModel
from bedrock_agentcore.runtime import BedrockAgentCoreApp

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))

SYSTEM_PROMPT = """You are an infrastructure provisioning agent for Arc'teryx development teams.

You help developers provision cloud infrastructure by writing Terraform and opening pull requests.
You follow existing patterns in the codebase and enforce company standards.
"""

model = BedrockModel(
    model_id="us.anthropic.claude-sonnet-4-6",
    region_name=os.environ.get("AWS_REGION", "us-west-2"),
)

agent = Agent(model=model, system_prompt=SYSTEM_PROMPT)
app = BedrockAgentCoreApp()


@app.entrypoint
async def invoke(payload):
    user_message = payload.get("prompt", "Hello")
    stream = agent.stream_async(user_message)
    async for event in stream:
        yield event


if __name__ == "__main__":
    app.run()

