# Preference quick-pick selection

- Outcome: a selected quick pick is shown in the selected chips and removed from Quick picks; deselecting it restores it in its original position. Search results retain their existing toggle behavior.
- Verification: the targeted UI test passed on iPhone 18 Pro Max / iOS 27.2 with mock data, including selection, removal, and selection count. A Simulator snapshot also showed Matcha only among selected chips after selection.

- Motion update: selected quick-pick chips use a short matched transition, disabled when Reduce Motion is enabled. Two focused Simulator UI tests passed; the selection transition was inspected from a Simulator recording.
