import type { aiConfig } from "./ai.ts";
import { contextBudget, checkUsage } from "./context.ts";
import { ensure, object, text } from "./domain.ts";
import { Http } from "./http.ts";

export type ModelConfig = ReturnType<typeof aiConfig>;
export class ModelSession {
  readonly calls: {
    purpose: string;
    elapsedMs: number;
    chargedTokens: number;
    usage: unknown;
    model: unknown;
    error: string | null;
  }[] = [];
  private charged = 0;
  readonly config: ModelConfig;
  readonly maxCalls: number;
  readonly totalTokenLimit: number;
  constructor(config: ModelConfig, maxCalls = 8, totalTokenLimit = 1_000_000) {
    this.config = config;
    this.maxCalls = maxCalls;
    this.totalTokenLimit = totalTokenLimit;
  }
  async send(
    payload: Record<string, unknown>,
    purpose = "proposal",
    roleConfig: ModelConfig = this.config,
  ): Promise<unknown> {
    const reserve = contextBudget(
      payload,
      roleConfig.maxTokens,
      roleConfig.contextLimit,
    );
    ensure(this.calls.length < this.maxCalls, "Run AI call budget exhausted.");
    ensure(
      this.charged + reserve.estimatedTotalTokens <= this.totalTokenLimit,
      "Run AI token budget exhausted before request.",
    );
    const record = {
      purpose,
      elapsedMs: 0,
      chargedTokens: reserve.estimatedTotalTokens,
      usage: null as unknown,
      model: null as unknown,
      error: null as string | null,
    };
    this.calls.push(record);
    this.charged += record.chargedTokens;
    const started = Date.now();
    try {
      const raw = object(
        await new Http(
          fetch,
          AbortSignal.timeout(roleConfig.timeoutMs + 1000),
        ).json(
          `OpenRouter ${purpose}`,
          "https://openrouter.ai/api/v1/chat/completions",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${roleConfig.key}`,
            },
            body: JSON.stringify(payload),
          },
          roleConfig.timeoutMs,
        ),
        "model response",
      );
      const usage = checkUsage(raw.usage, roleConfig.contextLimit);
      record.usage = raw.usage ?? null;
      record.model = raw.model ?? null;
      if (usage) {
        this.charged += usage.totalTokens - record.chargedTokens;
        record.chargedTokens = usage.totalTokens;
      }
      ensure(
        this.charged <= this.totalTokenLimit,
        "Provider-reported run token usage exceeded the run cap.",
      );
      return raw;
    } catch (error) {
      // A failed request may have consumed tokens; keep the conservative reservation.
      record.error =
        error instanceof Error ? error.message : "Model request failed.";
      throw error;
    } finally {
      record.elapsedMs = Date.now() - started;
    }
  }
  async json(
    name: string,
    schema: unknown,
    instruction: string,
    data: unknown,
  ): Promise<unknown> {
    const payload = {
      model: this.config.model,
      max_tokens: this.config.maxTokens,
      reasoning: { enabled: this.config.reasoningMode === "on" },
      stream: false,
      provider: { require_parameters: true },
      response_format: {
        type: "json_schema",
        json_schema: { name, strict: true, schema },
      },
      messages: [
        { role: "system", content: instruction },
        { role: "user", content: JSON.stringify(data) },
      ],
    };
    const raw = object(await this.send(payload, name), "model response");
    ensure(
      Array.isArray(raw.choices) && raw.choices.length > 0,
      "Model returned no choices.",
    );
    const choice = object(raw.choices[0], "model choice");
    ensure(
      choice.finish_reason === "stop",
      "Model final was truncated or incomplete; no simulated answer was substituted.",
    );
    try {
      return JSON.parse(
        text(
          object(choice.message, "model message").content,
          "model JSON",
          200000,
        ),
      );
    } catch {
      throw new Error("Model did not return valid final JSON.");
    }
  }
  summary() {
    return {
      calls: this.calls,
      maxCalls: this.maxCalls,
      chargedTokens: this.charged,
      totalTokenLimit: this.totalTokenLimit,
      missingUsageChargedAtConservativeReservation: true,
      internalReasoningStored: false,
    };
  }
}
