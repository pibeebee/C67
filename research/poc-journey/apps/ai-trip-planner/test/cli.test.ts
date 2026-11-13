import test from "node:test";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const exec = promisify(execFile);
const cwd = fileURLToPath(new URL("..", import.meta.url));
const env = {
  ...process.env,
  C67_POC_HTTP_STUB: "1",
  GOOGLE_MAPS_API_KEY: "synthetic-google-key",
  OPENROUTER_API_KEY: "synthetic-openrouter-key",
  OPENROUTER_MODEL: "test/stub-model",
  OPENROUTER_MAX_TOKENS: "2500",
};

test("full live CLI path produces inspectable reports using HTTP stubs only", async () => {
  const out = await mkdtemp(join(tmpdir(), "c67-poc-cli-"));
  try {
    const { stdout } = await exec(
      process.execPath,
      [
        "--import",
        "./test/http-stub.ts",
        "src/cli.ts",
        "--mode",
        "live",
        "--out",
        out,
      ],
      { cwd, env },
    );
    const report = JSON.parse(await readFile(join(out, "report.json"), "utf8"));
    assert.equal(report.ai.called, true);
    assert.equal(report.ai.model, "test/stub-model");
    assert.equal(report.diagnostics.httpCalls.OpenRouter, 1);
    assert.equal(report.diagnostics.httpCalls["Google Routes matrix"], 1);
    assert.equal(report.diagnostics.httpCalls["Open-Meteo"], 3);
    assert.deepEqual([...report.recommendation.order].sort(), ["B", "C", "D"]);
    assert.ok(report.checks.timelineArithmeticChecked);
    assert.ok(stdout.includes("TEST STUB ONLY"));
    assert.ok(
      (await readFile(join(out, "report.md"), "utf8")).includes("Comparison"),
    );
  } finally {
    await rm(out, { recursive: true, force: true });
  }
});

test("fixture-ai CLI calls only the AI adapter and does not require Google credentials", async () => {
  const out = await mkdtemp(join(tmpdir(), "c67-poc-cli-ai-"));
  try {
    await exec(
      process.execPath,
      [
        "--import",
        "./test/http-stub.ts",
        "src/cli.ts",
        "--mode",
        "fixture-ai",
        "--date",
        "2026-11-03",
        "--out",
        out,
      ],
      { cwd, env: { ...env, GOOGLE_MAPS_API_KEY: "" } },
    );
    const report = JSON.parse(await readFile(join(out, "report.json"), "utf8"));
    assert.equal(report.mode, "fixture-ai");
    assert.deepEqual(report.diagnostics.httpCalls, { OpenRouter: 1 });
    assert.equal(report.checks.allProviderDataLive, false);
  } finally {
    await rm(out, { recursive: true, force: true });
  }
});

test("invalid model configuration is rejected before any data-provider request", async () => {
  await assert.rejects(
    exec(
      process.execPath,
      ["--import", "./test/http-stub.ts", "src/cli.ts", "--mode", "live"],
      { cwd, env: { ...env, OPENROUTER_MAX_TOKENS: "256.5" } },
    ),
    (error: unknown) => {
      const e = error as { stderr: string };
      return (
        e.stderr.includes("must be an integer") &&
        !e.stderr.includes("evaluating")
      );
    },
  );
});
