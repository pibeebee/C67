import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock


spec = importlib.util.spec_from_file_location('destination_scope', Path(__file__).with_name('benchmark-destination-scope.py'))
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class DestinationScopeTests(unittest.TestCase):
    def prepare(self, folder):
        source = folder / 'source'
        output = folder / 'output'
        for path in (source / 'google', source / 'rich', output / 'scope', output / 'labels'):
            path.mkdir(parents=True)
        place = {'id': 'test-place', 'displayName': {'text': 'Example Cafe'},
                 'types': ['cafe'], 'primaryTypeDisplayName': {'text': 'Kafe'}}
        description = scope.baseline.description(place, True)
        (source / 'google/test-place.json').write_text(json.dumps({'place': place}))
        (source / 'rich/test-place.json').write_text(json.dumps({'description': description, 'labels': ['cafe']}))
        return source, output, place

    def gate_answer(self, probability):
        return {'eligibility': {'type': 'choice', 'choice': 'include',
                               'probabilities': {'include': probability, 'exclude': 0, 'unknown': 1 - probability}},
                'reason': {'type': 'choice', 'choice': 'visitor_activity',
                           'probabilities': {r: int(r == 'visitor_activity') for r in scope.REASONS}}}

    def test_unknown_and_excluded_candidates_never_call_labelling_or_emit_cached_labels(self):
        with tempfile.TemporaryDirectory() as folder:
            source, _, _ = self.prepare(Path(folder))
            for status in ('exclude', 'unknown'):
                with self.subTest(status=status):
                    campaign = Mock()
                    campaign.decide_scope.return_value = {'status': status}
                    result = scope.process('test-place', source, campaign, {}, {}, {})
                    campaign.label.assert_not_called()
                    self.assertEqual(result['labels'], [])
                    self.assertEqual(result['previousLabels'], ['cafe'])

    def test_label_failure_resumes_without_repeating_completed_scope_call(self):
        with tempfile.TemporaryDirectory() as folder:
            source, output, _ = self.prepare(Path(folder))
            campaign = scope.Campaign(output, 'unused-test-key')
            _, definitions, parents = scope.jev.taxonomy()
            labels = {label: {'type': 'noul', 'noul': .95 if label == 'cafe' else .01} for label in definitions}
            campaign.send = Mock(side_effect=[(self.gate_answer(.95), {}), RuntimeError('provider_timeout'), (labels, {})])
            with self.assertRaises(RuntimeError):
                scope.process('test-place', source, campaign, {}, definitions, parents)
            self.assertTrue((output / 'scope/test-place.json').exists())
            self.assertFalse((output / 'labels/test-place.json').exists())
            result = scope.process('test-place', source, campaign, {}, definitions, parents)
            self.assertEqual(result['labels'], ['cafe'])
            self.assertEqual(campaign.send.call_count, 3)
            self.assertEqual(set(campaign.send.call_args_list[0].args[1]), {'eligibility', 'reason'})
            self.assertEqual(len(campaign.send.call_args_list[2].args[1]), 62)

    def test_low_probability_include_is_held_as_unknown(self):
        with tempfile.TemporaryDirectory() as folder:
            _, output, place = self.prepare(Path(folder))
            campaign = scope.Campaign(output, 'unused-test-key')
            campaign.send = Mock(return_value=(self.gate_answer(.79), {}))
            result = campaign.decide_scope('test-place', place, 'example', {})
            self.assertEqual(result['modelChoice'], 'include')
            self.assertEqual(result['status'], 'unknown')

    def test_changed_baseline_description_fails_before_any_provider_call(self):
        with tempfile.TemporaryDirectory() as folder:
            source, _, _ = self.prepare(Path(folder))
            (source / 'rich/test-place.json').write_text(json.dumps({'description': 'different', 'labels': ['cafe']}))
            campaign = Mock()
            with self.assertRaises(ValueError):
                scope.process('test-place', source, campaign, {}, {}, {})
            campaign.decide_scope.assert_not_called()


if __name__ == '__main__':
    unittest.main()
