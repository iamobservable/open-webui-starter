"""
title: OpenAI Assistant Integration
author: ERNI-KI System
author_url: https://ki.erni-gruppe.ch
funding_url: https://github.com/sponsors/erni-ki
version: 1.0.0
license: MIT
requirements: requests, openai
"""

import json
import os
import time
from typing import Dict, Generator, List, Optional

import requests
from pydantic import BaseModel, Field


class Pipe:
    class Valves(BaseModel):
        LITELLM_BASE_URL: str = Field(
            default="http://litellm:4000",
            description="Base URL for LiteLLM service"
        )
        LITELLM_API_KEY: str = Field(
            default="sk-7b788d5ee69638c94477f639c91f128911bdf0e024978d4ba1dbdf678eba38bb",
            description="API key for LiteLLM service"
        )
        OPENAI_API_KEY: str = Field(
            default="",
            description="OpenAI API key for direct Assistant API calls"
        )
        ASSISTANT_ID: str = Field(
            default="asst_C8dUl6EKuR41O9sddVVuhTGn",
            description="OpenAI Assistant ID to use"
        )
        ASSISTANT_NAME: str = Field(
            default="OpenAI Assistant",
            description="Display name for the Assistant"
        )
        MAX_WAIT_TIME: int = Field(
            default=60,
            description="Maximum time to wait for Assistant response (seconds)"
        )

    def __init__(self):
        self.type = "manifold"
        self.valves = self.Valves()
        self.name = "OpenAI Assistant"

    def pipes(self) -> List[Dict[str, str]]:
        """Return available Assistant models"""
        return [
            {
                "id": f"assistant/{self.valves.ASSISTANT_ID}",
                "name": f"{self.valves.ASSISTANT_NAME} ({self.valves.ASSISTANT_ID})"
            }
        ]

    def create_thread(self) -> Optional[str]:
        """Create a new thread for conversation with Assistant"""
        try:
            headers = {
                "Authorization": f"Bearer {self.valves.LITELLM_API_KEY}",
                "Content-Type": "application/json"
            }

            response = requests.post(
                f"{self.valves.LITELLM_BASE_URL}/v1/threads",
                headers=headers,
                json={},
                timeout=30
            )

            if response.status_code == 200:
                thread_data = response.json()
                return thread_data['id']
            else:
                print(f"Error creating thread: {response.status_code} - {response.text}")
                return None

        except Exception as e:
            print(f"Exception creating thread: {e}")
            return None

    def add_message(self, thread_id: str, content: str, role: str = "user") -> Optional[str]:
        """Add a message to the thread"""
        try:
            headers = {
                "Authorization": f"Bearer {self.valves.LITELLM_API_KEY}",
                "Content-Type": "application/json"
            }

            message_data = {
                "role": role,
                "content": content
            }

            response = requests.post(
                f"{self.valves.LITELLM_BASE_URL}/v1/threads/{thread_id}/messages",
                headers=headers,
                json=message_data,
                timeout=30
            )

            if response.status_code == 200:
                message = response.json()
                return message['id']
            else:
                print(f"Error adding message: {response.status_code} - {response.text}")
                return None

        except Exception as e:
            print(f"Exception adding message: {e}")
            return None

    def create_run(self, thread_id: str, instructions: str = None) -> Optional[str]:
        """Create a run for the Assistant"""
        try:
            headers = {
                "Authorization": f"Bearer {self.valves.LITELLM_API_KEY}",
                "Content-Type": "application/json"
            }

            run_data = {
                "assistant_id": self.valves.ASSISTANT_ID
            }

            if instructions:
                run_data["instructions"] = instructions

            response = requests.post(
                f"{self.valves.LITELLM_BASE_URL}/v1/threads/{thread_id}/runs",
                headers=headers,
                json=run_data,
                timeout=30
            )

            if response.status_code == 200:
                run = response.json()
                return run['id']
            else:
                print(f"Error creating run: {response.status_code} - {response.text}")
                return None

        except Exception as e:
            print(f"Exception creating run: {e}")
            return None

    def wait_for_run_completion(self, thread_id: str, run_id: str) -> Optional[str]:
        """Wait for run completion and return status"""
        try:
            openai_headers = {
                "Authorization": f"Bearer {self.valves.OPENAI_API_KEY}",
                "Content-Type": "application/json",
                "OpenAI-Beta": "assistants=v2"
            }

            for attempt in range(self.valves.MAX_WAIT_TIME):
                response = requests.get(
                    f"https://api.openai.com/v1/threads/{thread_id}/runs/{run_id}",
                    headers=openai_headers,
                    timeout=30
                )

                if response.status_code == 200:
                    run_status = response.json()
                    status = run_status.get('status')

                    if status == 'completed':
                        return 'completed'
                    elif status in ['failed', 'cancelled', 'expired']:
                        return status
                    else:
                        time.sleep(1)
                else:
                    time.sleep(1)

            return 'timeout'

        except Exception as e:
            print(f"Exception waiting for run: {e}")
            return None

    def get_messages(self, thread_id: str) -> List[Dict]:
        """Get all messages from the thread"""
        try:
            openai_headers = {
                "Authorization": f"Bearer {self.valves.OPENAI_API_KEY}",
                "Content-Type": "application/json",
                "OpenAI-Beta": "assistants=v2"
            }

            response = requests.get(
                f"https://api.openai.com/v1/threads/{thread_id}/messages",
                headers=openai_headers,
                timeout=30
            )

            if response.status_code == 200:
                messages = response.json()
                return messages.get('data', [])
            else:
                print(f"Error getting messages: {response.status_code} - {response.text}")
                return []

        except Exception as e:
            print(f"Exception getting messages: {e}")
            return []

    def pipe(self, body: dict, __user__: dict) -> Generator[str, None, None]:
        """Main pipe function for handling chat requests"""
        try:
            # Extract the user message
            messages = body.get("messages", [])
            if not messages:
                yield "data: " + json.dumps({"error": "No messages provided"}) + "\n\n"
                return

            user_message = messages[-1].get("content", "")
            if not user_message:
                yield "data: " + json.dumps({"error": "Empty message"}) + "\n\n"
                return

            # Check if OpenAI API key is configured
            if not self.valves.OPENAI_API_KEY:
                yield "data: " + json.dumps({
                    "error": "OpenAI API key not configured. Please set OPENAI_API_KEY in the function settings."
                }) + "\n\n"
                return

            # Start the Assistant workflow
            yield "data: " + json.dumps({
                "choices": [{
                    "delta": {
                        "content": "🤖 Starting OpenAI Assistant...\n\n"
                    }
                }]
            }) + "\n\n"

            # 1. Create thread
            thread_id = self.create_thread()
            if not thread_id:
                yield "data: " + json.dumps({
                    "choices": [{
                        "delta": {
                            "content": "❌ Failed to create thread"
                        }
                    }]
                }) + "\n\n"
                return

            yield "data: " + json.dumps({
                "choices": [{
                    "delta": {
                        "content": "✅ Thread created, adding message...\n\n"
                    }
                }]
            }) + "\n\n"

            # 2. Add user message
            message_id = self.add_message(thread_id, user_message)
            if not message_id:
                yield "data: " + json.dumps({
                    "choices": [{
                        "delta": {
                            "content": "❌ Failed to add message"
                        }
                    }]
                }) + "\n\n"
                return

            yield "data: " + json.dumps({
                "choices": [{
                    "delta": {
                        "content": "✅ Message added, starting Assistant...\n\n"
                    }
                }]
            }) + "\n\n"

            # 3. Create run
            run_id = self.create_run(thread_id)
            if not run_id:
                yield "data: " + json.dumps({
                    "choices": [{
                        "delta": {
                            "content": "❌ Failed to create run"
                        }
                    }]
                }) + "\n\n"
                return

            yield "data: " + json.dumps({
                "choices": [{
                    "delta": {
                        "content": "✅ Assistant started, waiting for response...\n\n"
                    }
                }]
            }) + "\n\n"

            # 4. Wait for completion
            status = self.wait_for_run_completion(thread_id, run_id)
            if status != 'completed':
                yield "data: " + json.dumps({
                    "choices": [{
                        "delta": {
                            "content": f"❌ Assistant run failed with status: {status}"
                        }
                    }]
                }) + "\n\n"
                return

            # 5. Get response
            messages_list = self.get_messages(thread_id)
            for msg in messages_list:
                if msg.get('role') == 'assistant':
                    content = msg.get('content', [])
                    if content and len(content) > 0:
                        text = content[0].get('text', {}).get('value', '')
                        if text:
                            # Stream the response
                            yield "data: " + json.dumps({
                                "choices": [{
                                    "delta": {
                                        "content": f"✅ **OpenAI Assistant Response:**\n\n{text}"
                                    }
                                }]
                            }) + "\n\n"
                            return

            yield "data: " + json.dumps({
                "choices": [{
                    "delta": {
                        "content": "❌ No response from Assistant"
                    }
                }]
            }) + "\n\n"

        except Exception as e:
            yield "data: " + json.dumps({
                "choices": [{
                    "delta": {
                        "content": f"❌ Exception: {str(e)}"
                    }
                }]
            }) + "\n\n"
