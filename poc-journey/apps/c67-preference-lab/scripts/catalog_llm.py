"""Configured OpenAI-compatible transport. A missing key makes no request.

The evidence pipeline and preference advisor share the configured provider.
Credentials stay server-side. Settings are re-read on every invocation.
"""
import fcntl
import json
import os
import threading
import time
from pathlib import Path
from urllib.parse import urlsplit

from catalog_engine import ROOT, digest

ENV_PATH = ROOT / '.env.catalog.local'


def read_settings(path=ENV_PATH):
    values = {}
    if Path(path).exists():
        for line in Path(path).read_text().splitlines():
            if not line.strip() or line.lstrip().startswith('#') or '=' not in line:
                continue
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip().strip('"\'')
    for key in ['CATALOG_LLM_BASE_URL', 'CATALOG_LLM_MODEL', 'CATALOG_LLM_API_KEY',
                'CATALOG_LLM_MAX_CALLS', 'CATALOG_LLM_TIMEOUT_SECONDS']:
        if key in os.environ:
            values[key] = os.environ[key]
    return values


class CatalogLLMClient:
    def __init__(self, transport, settings_path=ENV_PATH, local=None):
        self.transport = transport
        self.settings_path = settings_path
        self.local = Path(local) if local else ROOT / '.local'
        self.lock = threading.Lock()

    @property
    def identity(self):
        settings = read_settings(self.settings_path)
        return {'baseURL': settings.get('CATALOG_LLM_BASE_URL', '').rstrip('/'),
                'model': settings.get('CATALOG_LLM_MODEL', '')}

    def status(self):
        settings = read_settings(self.settings_path)
        return dict(self.identity, configured=bool(settings.get('CATALOG_LLM_API_KEY')),
                    maxCalls=int(settings.get('CATALOG_LLM_MAX_CALLS', '72')))

    def reserve(self, identity, cap):
        self.local.mkdir(parents=True, exist_ok=True)
        usage_path = self.local / ('catalog-provider-usage-' + digest(identity)[:12] + '.json')
        with self.lock, usage_path.with_suffix('.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            count = json.loads(usage_path.read_text())['attempts'] if usage_path.exists() else 0
            if count >= cap:
                return False
            temporary = usage_path.with_suffix('.tmp')
            temporary.write_text(json.dumps({'attempts': count + 1, 'cap': cap, **identity}))
            temporary.replace(usage_path)
        return True

    def complete(self, payload, total_budget=60, campaign=None):
        began = time.monotonic()
        settings = read_settings(self.settings_path)
        identity = self.identity
        base = identity['baseURL']
        model = identity['model']
        meta = {'mode': 'llm_unavailable', 'model': model, 'provider': urlsplit(base).hostname,
                'seconds': 0, 'attempts': 0, 'costUSD': None, 'errorCode': None,
                'promptTokens': None, 'completionTokens': None}
        if not settings.get('CATALOG_LLM_API_KEY'):
            return None, dict(meta, errorCode='missing_catalog_api_key')
        parsed = urlsplit(base)
        if parsed.scheme != 'https' or parsed.username or parsed.password or parsed.query or parsed.fragment or not parsed.hostname:
            return None, dict(meta, errorCode='invalid_catalog_base_url')
        if not model or len(model) > 200:
            return None, dict(meta, errorCode='invalid_catalog_model')
        timeout = min(total_budget, float(settings.get('CATALOG_LLM_TIMEOUT_SECONDS', '60')))
        request = {k: v for k, v in payload.items() if k not in ['provider', 'reasoning', 'temperature']}
        request['model'] = model
        request['max_tokens'] = min(int(request.get('max_tokens', 1600)), 3200)
        # Some compatible proxies accept response_format without enforcing it.
        # Make the JSON contract explicit in the prompt as well, then validate
        # the parsed result in the caller. Never parse a Markdown table as facts.
        response_format = request.get('response_format', {})
        if response_format.get('type') == 'json_schema':
            schema = response_format['json_schema']['schema']
            request['messages'] = [{'role': 'system', 'content':
                'Return ONLY a valid JSON object matching this schema. No Markdown, table, code fence, or explanation. '
                + json.dumps(schema)}] + request.get('messages', [])
        errors = []
        for attempt in range(2):
            remaining = timeout - (time.monotonic() - began)
            if remaining < .3:
                break
            if not self.reserve(identity, int(settings.get('CATALOG_LLM_MAX_CALLS', '72'))):
                errors.append('campaign_budget')
                break
            meta['attempts'] += 1
            try:
                response = self.transport(base + '/chat/completions', request,
                    {'Authorization': 'Bearer ' + settings['CATALOG_LLM_API_KEY']}, remaining)
                usage = response.get('usage', {})
                meta.update(model=response.get('model', model), promptTokens=usage.get('prompt_tokens'),
                            completionTokens=usage.get('completion_tokens'), costUSD=usage.get('cost'),
                            finishReason=response['choices'][0].get('finish_reason'))
                content = response['choices'][0]['message'].get('content')
                if not isinstance(content, str) or not content.strip():
                    raise RuntimeError('empty_model_content')
                result = json.loads(content)
                return result, dict(meta, mode='llm', model=response.get('model', model),
                    seconds=time.monotonic() - began, errorCode=','.join(errors) or None,
                    promptTokens=usage.get('prompt_tokens'), completionTokens=usage.get('completion_tokens'),
                    costUSD=usage.get('cost'), responseFormat=request.get('response_format', {}).get('type'))
            except (RuntimeError, ValueError, KeyError, TypeError, IndexError) as error:
                code = str(error) if isinstance(error, RuntimeError) else type(error).__name__
                errors.append(code[:80])
                # One compatibility retry, confined to schema rejection. No retry
                # for authentication, quota, or transport failure.
                if attempt == 0 and code in ['provider_http_400', 'provider_http_422'] and request.get('response_format', {}).get('type') == 'json_schema':
                    request = dict(request, response_format={'type': 'json_object'})
                    continue
                break
        return None, dict(meta, seconds=time.monotonic() - began, errorCode=','.join(errors) or 'provider_timeout')
