import { createHash } from "node:crypto";
import { ensure, object, text } from "./domain.ts";
import { ModelSession, type ModelConfig } from "./model-session.ts";

export type NativeTool = {
  name: string;
  description: string;
  schema: unknown;
  terminal?: boolean;
  execute: (args: unknown) => Promise<unknown>;
};
export type AgentResult = {
  status: "submitted" | "turn_limit" | "stalled" | "request_failed";
  submission: unknown;
  error: string | null;
  turns: number;
};
type Message = Record<string, unknown>;
export class NativeAgent {
  private messages: Message[];
  private toolIds = new Set<string>();
  private observedResults = new Set<string>();
  constructor(privateOptions: {
    role: string;
    instruction: string;
    input: unknown;
    config: ModelConfig;
    session: ModelSession;
    tools: NativeTool[];
    maxTurns: number;
    checkpoint: (value: unknown) => Promise<void>;
  }) {
    this.options = privateOptions;
    this.messages = [
      { role: "system", content: privateOptions.instruction },
      { role: "user", content: JSON.stringify(privateOptions.input) },
    ];
  }
  private options: {
    role: string;
    instruction: string;
    input: unknown;
    config: ModelConfig;
    session: ModelSession;
    tools: NativeTool[];
    maxTurns: number;
    checkpoint: (value: unknown) => Promise<void>;
  };
  add(data: unknown) {
    this.messages.push({ role: "user", content: JSON.stringify(data) });
  }
  private async persist(extra: unknown) {
    // Reasoning blocks may be required for the next API turn, but are never saved.
    await this.options.checkpoint({
      role: this.options.role,
      messages: this.messages.map(
        ({ reasoning, reasoning_details, reasoning_content, ...message }) =>
          message,
      ),
      extra,
      internalReasoningStored: false,
    });
  }
  async run(): Promise<AgentResult> {
    let stalls = 0;
    for (let turn = 1; turn <= this.options.maxTurns; turn++) {
      const { config, session, tools } = this.options;
      let raw: Record<string, unknown>;
      try {
        raw = object(
          await session.send(
            {
              model: config.model,
              max_tokens: config.maxTokens,
              reasoning: { enabled: config.reasoningMode === "on" },
              stream: false,
              provider: { require_parameters: true },
              tool_choice: "auto",
              tools: tools.map((t) => ({
                type: "function",
                function: {
                  name: t.name,
                  description: t.description,
                  parameters: t.schema,
                },
              })),
              messages: this.messages,
            },
            this.options.role,
            config,
          ),
          "agent response",
        );
      } catch (error) {
        const result: AgentResult = {
          status: "request_failed",
          submission: null,
          error:
            error instanceof Error ? error.message : "Model request failed.",
          turns: turn,
        };
        await this.persist(result);
        return result;
      }
      try {
        ensure(
          Array.isArray(raw.choices) && raw.choices.length > 0,
          "No model choice.",
        );
        const choice = object(raw.choices[0], "choice");
        if (!["stop", "tool_calls"].includes(String(choice.finish_reason))) {
          stalls++;
          this.add({
            error:
              "The preceding response did not complete. No partial tool arguments were executed. Complete one focused tool call, or a complete terminal submission.",
          });
          await this.persist({
            turn,
            error: "incomplete_final",
            finishReason: choice.finish_reason,
          });
          if (stalls >= 3)
            return {
              status: "stalled",
              submission: null,
              error: "Repeated incomplete responses.",
              turns: turn,
            };
          continue;
        }
        const message = object(choice.message, "assistant message");
        if (
          !Array.isArray(message.tool_calls) ||
          message.tool_calls.length === 0
        ) {
          if (typeof message.content === "string")
            this.messages.push({ role: "assistant", content: message.content });
          this.add({
            instruction:
              "Use a supplied tool. Free text cannot finish this stage. Terminal submission must be the only tool call in its response.",
          });
          await this.persist({ turn, error: "missing_tool_call" });
          if (++stalls >= 3)
            return {
              status: "stalled",
              submission: null,
              error: "Model did not use the required tools.",
              turns: turn,
            };
          continue;
        }
        ensure(
          message.tool_calls.length <= 12,
          "Too many tool calls in a response.",
        );
        const calls = message.tool_calls.map((item) => {
          const call = object(item, "tool call"),
            fn = object(call.function, "tool function");
          const id = text(call.id, "tool ID", 200);
          ensure(!this.toolIds.has(id), "Duplicate tool call ID.");
          this.toolIds.add(id);
          return {
            id,
            type: "function",
            function: {
              name: text(fn.name, "tool name", 100),
              arguments: text(fn.arguments, "tool arguments", 300000),
            },
          };
        });
        this.messages.push({
          role: "assistant",
          content: typeof message.content === "string" ? message.content : null,
          tool_calls: calls,
          ...(Array.isArray(message.reasoning_details)
            ? { reasoning_details: message.reasoning_details }
            : typeof message.reasoning === "string"
              ? { reasoning: message.reasoning }
              : {}),
        });
        let terminal: unknown = null,
          accepted = false,
          progress = false;
        // Execute every call in order. A mixed batch never commits a terminal result.
        for (const call of calls) {
          const tool = tools.find((t) => t.name === call.function.name);
          let output: unknown;
          try {
            ensure(tool, "Unknown tool.");
            ensure(
              !tool.terminal || calls.length === 1,
              "Terminal submission must be alone; other tool requests in this batch will still execute.",
            );
            const args = JSON.parse(call.function.arguments);
            output = await tool.execute(args);
            const fingerprint = createHash("sha256")
              .update(JSON.stringify({ tool: tool.name, args, output }))
              .digest("hex");
            if (!this.observedResults.has(fingerprint)) progress = true;
            this.observedResults.add(fingerprint);
            if (tool.terminal) {
              terminal = output;
              accepted = true;
            }
          } catch (error) {
            output = {
              error: error instanceof Error ? error.message : "Tool failed.",
              accepted: false,
            };
          }
          this.messages.push({
            role: "tool",
            tool_call_id: call.id,
            content: JSON.stringify(output),
          });
          await this.persist({
            turn,
            tool: call.function.name,
            acceptedTerminal: accepted,
          });
        }
        if (accepted)
          return {
            status: "submitted",
            submission: terminal,
            error: null,
            turns: turn,
          };
        stalls = progress ? 0 : stalls + 1;
        if (stalls >= 3)
          return {
            status: "stalled",
            submission: null,
            error: "Repeated invalid tool actions.",
            turns: turn,
          };
      } catch (error) {
        const result: AgentResult = {
          status: "stalled",
          submission: null,
          error:
            error instanceof Error
              ? error.message
              : "Invalid provider tool protocol.",
          turns: turn,
        };
        await this.persist(result);
        return result;
      }
    }
    const result: AgentResult = {
      status: "turn_limit",
      submission: null,
      error: "Agent turn guard reached before a validated submission.",
      turns: this.options.maxTurns,
    };
    await this.persist(result);
    return result;
  }
}
