import { ensure, object } from "./domain.ts";

export const DEFAULT_CONTEXT_LIMIT = 1_000_000;
export function contextBudget(
  payload: unknown,
  outputTokens: number,
  limit = DEFAULT_CONTEXT_LIMIT,
) {
  const body = JSON.stringify(payload);
  // Conservative preflight, not the model's exact tokenizer. Provider enforces its
  // actual context window; returned usage is checked independently after the call.
  const estimatedInputTokens = Buffer.byteLength(body, "utf8") + 8192;
  ensure(
    Number.isSafeInteger(limit) &&
      limit >= 1024 &&
      limit <= DEFAULT_CONTEXT_LIMIT,
    "Context limit must be an integer between 1024 and 1000000.",
  );
  ensure(
    Number.isSafeInteger(outputTokens) && outputTokens > 0,
    "Output token reserve must be a positive integer.",
  );
  ensure(
    estimatedInputTokens + outputTokens <= limit,
    "Request exceeds the configured context budget before any AI call. Reduce input or output reserve.",
  );
  return {
    limitTokens: limit,
    reservedOutputTokens: outputTokens,
    estimatedInputTokens,
    estimatedTotalTokens: estimatedInputTokens + outputTokens,
    estimateMethod:
      "UTF-8 request bytes + 8192 overhead reserve; conservative estimate, not exact model tokenization.",
  };
}
export function contextCheckedBody(
  payload: unknown,
  outputTokens: number,
  limit = DEFAULT_CONTEXT_LIMIT,
): string {
  contextBudget(payload, outputTokens, limit);
  return JSON.stringify(payload);
}
export function checkUsage(usage: unknown, limit = DEFAULT_CONTEXT_LIMIT) {
  if (!usage || typeof usage !== "object") return null;
  const u = object(usage, "AI usage");
  if (
    typeof u.prompt_tokens !== "number" ||
    typeof u.completion_tokens !== "number"
  )
    return null;
  ensure(
    Number.isFinite(u.prompt_tokens) &&
      u.prompt_tokens >= 0 &&
      Number.isFinite(u.completion_tokens) &&
      u.completion_tokens >= 0,
    "Invalid token usage from provider.",
  );
  const total = u.prompt_tokens + u.completion_tokens;
  ensure(
    total <= limit,
    "Provider-reported input plus completion exceeds the configured context cap.",
  );
  return {
    inputTokens: u.prompt_tokens,
    completionTokens: u.completion_tokens,
    totalTokens: total,
    withinLimit: true,
  };
}
