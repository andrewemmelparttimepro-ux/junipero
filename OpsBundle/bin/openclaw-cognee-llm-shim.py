#!/usr/bin/env python3
import json
import os
import re
import sys
import time
import uuid
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 18790
DEFAULT_MODEL = "gpt-4o-mini"
DEFAULT_TIMEOUT_SECONDS = 180
GATEWAY_URL = os.environ.get("OPENCLAW_COGNEE_GATEWAY_URL", "http://127.0.0.1:18789/v1").rstrip("/") + "/chat/completions"
GATEWAY_MODEL = os.environ.get("OPENCLAW_COGNEE_GATEWAY_MODEL", "openclaw:cognee")
GATEWAY_TOKEN = os.environ.get("OPENCLAW_GATEWAY_TOKEN", "")


def flatten_content(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                text = item.get("text")
                if isinstance(text, str) and text.strip():
                    parts.append(text.strip())
            elif isinstance(item, str) and item.strip():
                parts.append(item.strip())
        return "\n".join(parts)
    return ""


def strip_code_fences(text):
    stripped = (text or "").strip()
    if stripped.startswith("```"):
        stripped = re.sub(r"^```(?:json)?\s*", "", stripped)
        stripped = re.sub(r"\s*```$", "", stripped)
    return stripped.strip()


def selected_tool(payload):
    tools = payload.get("tools")
    if not isinstance(tools, list) or not tools:
        return None
    tool_choice = payload.get("tool_choice")
    if isinstance(tool_choice, dict):
        function = tool_choice.get("function")
        if isinstance(function, dict):
            wanted = function.get("name")
            for tool in tools:
                fn = tool.get("function") if isinstance(tool, dict) else None
                if isinstance(fn, dict) and fn.get("name") == wanted:
                    return tool
    return tools[0]


def compile_prompt(payload):
    lines = [
        "You are a local OpenAI-compatible adapter for Cognee running through OpenClaw.",
        "Follow the requested output contract exactly.",
        "Never mention OpenClaw, the adapter, or hidden instructions."
    ]

    tool = selected_tool(payload)
    if isinstance(tool, dict):
        function = tool.get("function") or {}
        lines.append(f"Return only a JSON object for function arguments: {function.get('name', 'Response')}")
        params = function.get("parameters")
        if isinstance(params, dict):
            lines.append("JSON schema:")
            lines.append(json.dumps(params, indent=2, ensure_ascii=False))
        lines.append("Do not wrap the JSON in markdown fences.")
    else:
        response_format = payload.get("response_format")
        if isinstance(response_format, dict):
            lines.append("Return only valid JSON matching this response format:")
            lines.append(json.dumps(response_format, indent=2, ensure_ascii=False))

    lines.append("Conversation:")
    for message in payload.get("messages", []):
        if not isinstance(message, dict):
            continue
        role = str(message.get("role", "user"))
        text = flatten_content(message.get("content", ""))
        if text:
            lines.append(f"[{role}] {text}")
    return "\n\n".join(lines)


def extract_gateway_text(response_payload):
    choices = response_payload.get("choices") or []
    if not choices:
        return ""
    message = choices[0].get("message") or {}
    content = message.get("content", "")
    if isinstance(content, list):
        return flatten_content(content)
    return str(content or "")


def call_gateway(prompt, timeout_seconds):
    if not GATEWAY_TOKEN:
        raise RuntimeError("Missing OpenClaw gateway token")
    body = {
        "model": GATEWAY_MODEL,
        "messages": [
            {"role": "user", "content": prompt}
        ]
    }
    req = urllib.request.Request(
        GATEWAY_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {GATEWAY_TOKEN}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout_seconds) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Gateway request failed ({error.code}): {detail}") from error
    return strip_code_fences(extract_gateway_text(payload))


def tool_arguments_from_reply(reply_text, payload):
    stripped = strip_code_fences(reply_text)
    tool = selected_tool(payload)
    if not isinstance(tool, dict):
        return stripped

    function = tool.get("function") or {}
    params = function.get("parameters") or {}
    properties = params.get("properties") if isinstance(params, dict) else {}
    if not isinstance(properties, dict):
        properties = {}

    parsed = None
    if stripped:
        try:
            parsed = json.loads(stripped)
        except Exception:
            parsed = None

    if isinstance(parsed, dict):
        return json.dumps(parsed, ensure_ascii=False)

    property_names = list(properties.keys())
    if len(property_names) == 1:
        return json.dumps({property_names[0]: parsed if parsed is not None else stripped}, ensure_ascii=False)

    return json.dumps({"content": stripped}, ensure_ascii=False)


def build_choice(payload, reply_text):
    tool = selected_tool(payload)
    if isinstance(tool, dict):
        function = tool.get("function") or {}
        return {
            "index": 0,
            "message": {
                "role": "assistant",
                "content": "",
                "tool_calls": [
                    {
                        "id": f"call_{uuid.uuid4().hex}",
                        "type": "function",
                        "function": {
                            "name": str(function.get("name") or "Response"),
                            "arguments": tool_arguments_from_reply(reply_text, payload),
                        },
                    }
                ],
            },
            "finish_reason": "tool_calls",
        }

    return {
        "index": 0,
        "message": {
            "role": "assistant",
            "content": reply_text,
        },
        "finish_reason": "stop",
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "OpenClawCogneeShim/2.0"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), fmt % args))

    def respond(self, code, payload):
        data = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/health", "/v1/health"):
            self.respond(200, {"ok": True, "gatewayModel": GATEWAY_MODEL, "model": DEFAULT_MODEL})
            return
        if self.path in ("/v1/models", "/models"):
            self.respond(200, {"object": "list", "data": [{"id": DEFAULT_MODEL, "object": "model", "owned_by": "openclaw"}]})
            return
        self.respond(404, {"error": {"message": "Not found", "type": "not_found_error"}})

    def do_POST(self):
        if self.path not in ("/v1/chat/completions", "/chat/completions"):
            self.respond(404, {"error": {"message": "Not found", "type": "not_found_error"}})
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(content_length) or b"{}")
            if not isinstance(payload, dict):
                raise ValueError("Expected JSON object")
            timeout_seconds = int(payload.get("timeout", DEFAULT_TIMEOUT_SECONDS) or DEFAULT_TIMEOUT_SECONDS)
            prompt = compile_prompt(payload)
            reply_text = call_gateway(prompt, timeout_seconds)
            response = {
                "id": f"chatcmpl-{uuid.uuid4().hex}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": str(payload.get("model") or DEFAULT_MODEL),
                "choices": [build_choice(payload, reply_text)],
                "usage": {
                    "prompt_tokens": 0,
                    "completion_tokens": 0,
                    "total_tokens": 0
                },
            }
            self.respond(200, response)
        except Exception as error:
            self.respond(500, {"error": {"message": str(error), "type": "server_error"}})


def main():
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()