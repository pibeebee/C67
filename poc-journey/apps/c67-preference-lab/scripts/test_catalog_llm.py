import json
import tempfile
import unittest
from pathlib import Path

from catalog_llm import CatalogLLMClient


class CatalogLLMTests(unittest.TestCase):
    def settings(self, folder, key='test-key', cap=3):
        path = Path(folder) / '.env.catalog.local'
        path.write_text('CATALOG_LLM_BASE_URL=https://luna-provider.example/v1\n'
                        'CATALOG_LLM_MODEL=cx/gpt-6-luna(max)\n'
                        'CATALOG_LLM_API_KEY=' + key + '\nCATALOG_LLM_MAX_CALLS=' + str(cap))
        return path

    def test_missing_key_never_calls_transport(self):
        with tempfile.TemporaryDirectory() as folder:
            client = CatalogLLMClient(lambda *args: self.fail('network request'), self.settings(folder, key=''), folder)
            value, meta = client.complete({})
            self.assertIsNone(value)
            self.assertEqual(meta['errorCode'], 'missing_catalog_api_key')
            self.assertEqual(meta['attempts'], 0)

    def test_exact_model_and_base_url_without_openrouter_fields(self):
        calls = []
        def transport(url, payload, headers, timeout):
            calls.append((url, payload, headers))
            return {'choices': [{'message': {'content': '{"ok":true}'}}], 'usage': {'prompt_tokens': 4}}
        with tempfile.TemporaryDirectory() as folder:
            client = CatalogLLMClient(transport, self.settings(folder), folder)
            value, meta = client.complete({'messages': [], 'provider': {'data_collection': 'deny'},
                                           'reasoning': {'effort': 'low'}, 'temperature': 0})
            self.assertEqual(value, {'ok': True})
            self.assertEqual(calls[0][0], 'https://luna-provider.example/v1/chat/completions')
            self.assertEqual(calls[0][1]['model'], 'cx/gpt-6-luna(max)')
            self.assertNotIn('provider', calls[0][1])
            self.assertNotIn('reasoning', calls[0][1])
            self.assertNotIn('test-key', json.dumps(meta))
            self.assertIsNone(meta['costUSD'])

    def test_quota_persists_between_client_instances(self):
        def transport(*args):
            return {'choices': [{'message': {'content': '{}'}}]}
        with tempfile.TemporaryDirectory() as folder:
            path = self.settings(folder, cap=1)
            first = CatalogLLMClient(transport, path, folder)
            self.assertEqual(first.complete({})[1]['attempts'], 1)
            second = CatalogLLMClient(lambda *args: self.fail('over budget'), path, folder)
            self.assertEqual(second.complete({})[1]['errorCode'], 'campaign_budget')

    def test_schema_compatibility_retry_is_bounded(self):
        calls = []
        def transport(url, payload, headers, timeout):
            calls.append(payload)
            if len(calls) == 1:
                raise RuntimeError('provider_http_400')
            return {'choices': [{'message': {'content': '{}'}}]}
        with tempfile.TemporaryDirectory() as folder:
            client = CatalogLLMClient(transport, self.settings(folder), folder)
            _, meta = client.complete({'messages': [], 'response_format': {
                'type': 'json_schema', 'json_schema': {'schema': {'type': 'object'}}}})
            self.assertEqual(meta['attempts'], 2)
            self.assertEqual(calls[1]['response_format'], {'type': 'json_object'})
            self.assertIn('Return ONLY a valid JSON object', calls[0]['messages'][0]['content'])
            self.assertIn('"type": "object"', calls[0]['messages'][0]['content'])

    def test_markdown_from_proxy_is_failure_and_keeps_usage(self):
        with tempfile.TemporaryDirectory() as folder:
            def transport(*args):
                return {'model': 'reported-model', 'choices': [{'finish_reason': 'stop', 'message': {'content': '| labels | unknown |'}}],
                        'usage': {'prompt_tokens': 12, 'completion_tokens': 8}}
            client = CatalogLLMClient(transport, self.settings(folder), folder)
            value, meta = client.complete({})
            self.assertIsNone(value)
            self.assertEqual(meta['mode'], 'llm_unavailable')
            self.assertEqual(meta['promptTokens'], 12)
            self.assertEqual(meta['model'], 'reported-model')

    def test_authentication_failure_does_not_retry(self):
        with tempfile.TemporaryDirectory() as folder:
            def transport(*args):
                raise RuntimeError('provider_http_401')
            client = CatalogLLMClient(transport, self.settings(folder), folder)
            _, meta = client.complete({})
            self.assertEqual(meta['attempts'], 1)
            self.assertEqual(meta['errorCode'], 'provider_http_401')

    def test_key_added_after_startup_is_loaded_without_exposing_it(self):
        with tempfile.TemporaryDirectory() as folder:
            path = self.settings(folder, key='')
            client = CatalogLLMClient(lambda *args: {'choices': [{'message': {'content': '{}'}}]}, path, folder)
            self.assertFalse(client.status()['configured'])
            self.settings(folder, key='new-secret')
            self.assertTrue(client.status()['configured'])
            self.assertEqual(client.complete({})[1]['mode'], 'llm')
            self.assertNotIn('new-secret', json.dumps(client.status()))


if __name__ == '__main__':
    unittest.main()
