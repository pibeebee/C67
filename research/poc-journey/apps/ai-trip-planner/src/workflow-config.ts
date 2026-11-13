import { aiConfig } from "./ai.ts";
import { ensure } from "./domain.ts";
import type { ModelConfig } from "./model-session.ts";
export type WorkflowRole = "researcher" | "planner" | "reviewer";
export function bounded(
  raw: string | undefined,
  fallback: number,
  min: number,
  max: number,
) {
  const n = Number(raw ?? fallback);
  ensure(
    Number.isSafeInteger(n) && n >= min && n <= max,
    `Configuration must be an integer in ${min}..${max}.`,
  );
  return n;
}
export function workflowConfig(env: NodeJS.ProcessEnv) {
  const base = aiConfig(env);
  const role = (name: WorkflowRole): ModelConfig => {
    const prefix = `OPENROUTER_${name.toUpperCase()}`;
    const maxTokens = bounded(
      env[`${prefix}_MAX_TOKENS`],
      Math.max(32768, base.maxTokens),
      1024,
      131072,
    );
    ensure(
      maxTokens + 8192 < base.contextLimit,
      "Role completion reserve is too large for its context cap.",
    );
    return {
      ...base,
      model: env[`${prefix}_MODEL`]?.trim() || base.model,
      maxTokens,
      timeoutMs: bounded(
        env[`${prefix}_TIMEOUT_MS`],
        Math.max(300000, base.timeoutMs),
        1000,
        600000,
      ),
    };
  };
  return {
    base,
    roles: {
      researcher: role("researcher"),
      planner: role("planner"),
      reviewer: role("reviewer"),
    },
    maxCalls: bounded(env.POC_MAX_MODEL_CALLS, 48, 3, 128),
    maxRunTokens: bounded(env.POC_MAX_RUN_TOKENS, 1000000, 65536, 10000000),
    maxTurns: bounded(env.POC_AGENT_MAX_TURNS, 24, 3, 128),
    maxCycles: bounded(env.POC_QUALITY_MAX_CYCLES, 8, 1, 32),
    maxRouteRequests: bounded(env.POC_MAX_ROUTE_REQUESTS, 150, 6, 500),
    walkingBuffer: bounded(env.POC_WALK_BUFFER_MINUTES, 5, 1, 30),
    transitBuffer: bounded(env.POC_TRANSIT_BUFFER_MINUTES, 10, 1, 60),
  };
}
