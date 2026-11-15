import unittest
from guards import render_fact, validate_intent

CONTEXT = {'stateRevision': 7, 'currentStopID': 'B', 'endPointID': 'O', 'now': '2026-11-05T09:00:00+07:00',
           'stops': [{'id': 'A', 'status': 'completed'}, {'id': 'B', 'status': 'visiting'}, {'id': 'C', 'status': 'pending'}],
           'proposal': {'id': 'P-OLD', 'basedOnRevision': 6, 'valid': False, 'complete': True, 'feasible': True}}


class GuardsTests(unittest.TestCase):
    def test_valid_proposal_still_needs_confirmation(self):
        self.assertIn('requires confirmation', validate_intent({'intent': 'extend', 'target': 'B', 'minutes': 30}, CONTEXT, 7))

    def test_revision_and_old_proposal_are_rejected(self):
        self.assertTrue(validate_intent({'intent': 'skip', 'target': 'C'}, CONTEXT, 8).startswith('reject'))
        self.assertTrue(validate_intent({'intent': 'apply', 'proposalID': 'P-OLD'}, CONTEXT, 7).startswith('reject'))

    def test_completed_stop_and_out_of_range_are_rejected(self):
        self.assertTrue(validate_intent({'intent': 'skip', 'target': 'A'}, CONTEXT, 7).startswith('reject'))
        self.assertTrue(validate_intent({'intent': 'extend', 'target': 'B', 'minutes': -1}, CONTEXT, 7).startswith('reject'))
        self.assertTrue(validate_intent({'intent': 'extend', 'target': 'B', 'minutes': True}, CONTEXT, 7).startswith('reject'))
        self.assertTrue(validate_intent({'intent': 'skip', 'target': 'C', 'question': 'Which stop?'}, CONTEXT, 7).startswith('reject'))
        self.assertTrue(validate_intent({'intent': 'skip', 'target': 'C', 'minutes': 0}, CONTEXT, 7).startswith('reject'))

    def test_template_uses_structured_values_and_uncertainty(self):
        text = render_fact({'kind': 'weather', 'stop': 'C', 'probability': 60, 'evidenceID': 'E-WEATHER'})
        self.assertIn('60%', text)
        self.assertIn('not certain', text)
        self.assertIn('E-WEATHER', text)


if __name__ == '__main__': unittest.main()
