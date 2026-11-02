import { Failure, assertProposal, uuid, validateInput, type Input, type Result } from './domain.ts';
import { schedule, type Route } from './scheduler.ts';
import { type Context, type Providers } from './providers.ts';

export async function plan(
  input: Input,
  providers: Providers,
  purpose: 'plan' | 'suggest' | 'replan' = 'plan',
  signal?: AbortSignal,
): Promise<Result> {
  validateInput(input);
  signal?.throwIfAborted();
  const context: Context = { evidence: [], warnings: [], signal };
  if (purpose === 'suggest') {
    const candidates = await providers.suggest(input, context);
    if (
      !Array.isArray(candidates) ||
      candidates.length > 4 ||
      new Set(candidates.map((p) => p.id.toLowerCase())).size !== candidates.length
    )
      throw new Failure('INVALID_MODEL_OUTPUT', 502);
    for (const candidate of candidates)
      validateInput({ ...input, first_place_id: null, places: [candidate] });
    return {
      proposal: null,
      candidates,
      warnings: context.warnings,
      synthetic: providers.synthetic,
    };
  }
  // Weather is contextual, not a hard travel-safety decision. Missing data stays explicit.
  for (const place of input.places) {
    signal?.throwIfAborted();
    try {
      await providers.weather(place, input, context);
    } catch {
      context.warnings.push(
        `Weather could not be obtained for ${place.name}; no forecast was invented.`,
      );
    }
    await providers.research(place, context);
  }
  const cache = new Map<string, Route>();
  const orders = await providers.orders(input, context);
  const candidates = await schedule(
    input,
    async (from, to, departure) => {
      signal?.throwIfAborted();
      const start =
        from === 'origin' ? input.origin : input.places.find((p) => p.id === from)!.location;
      const end = input.places.find((p) => p.id === to)!.location;
      // Request-local cache only; no persistent provider dataset or cross-date reuse.
      const key = `${from}:${to}:${departure}:${input.mode}`;
      if (!cache.has(key))
        cache.set(key, await providers.route(start, end, departure, input.mode, context));
      return cache.get(key)!;
    },
    new Map(),
    orders,
  );
  const selection = await providers.choose(input, candidates, context);
  const selected = candidates.find((c) => c.id === selection.candidate_id);
  if (!selected || (candidates.some((candidate) => candidate.feasible) && !selected.feasible))
    throw new Failure('INVALID_MODEL_OUTPUT', 502);
  const proposal = {
    id: uuid(),
    input,
    stops: selected.stops,
    finishes_at: selected.finishes_at,
    feasible: selected.feasible,
    explanation: selection.explanation,
    warnings: [...context.warnings, ...selected.warnings],
    evidence: context.evidence,
    synthetic: providers.synthetic,
  };
  assertProposal(proposal, input);
  return { proposal, candidates: [], warnings: proposal.warnings, synthetic: providers.synthetic };
}
