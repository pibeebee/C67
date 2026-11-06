// Imported only by CLI integration tests; makes real network access impossible.
import { at } from "../src/domain.ts";
if (process.env.C67_POC_HTTP_STUB !== "1")
  throw new Error("Test-only HTTP stub requires C67_POC_HTTP_STUB=1.");
globalThis.fetch = async (resource, init) => {
  const url = String(resource);
  const body = init?.body ? JSON.parse(String(init.body)) : {};
  let data: unknown;
  if (
    url === "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix"
  ) {
    data = body.origins.flatMap((_from: unknown, oi: number) =>
      body.destinations.map((_to: unknown, di: number) => ({
        originIndex: oi,
        destinationIndex: di,
        status: {},
        condition: "ROUTE_EXISTS",
        duration: "600s",
        distanceMeters: 1000,
      })),
    );
  } else if (
    url === "https://routes.googleapis.com/directions/v2:computeRoutes"
  ) {
    data = { routes: [{ duration: "600s", distanceMeters: 1000 }] };
  } else if (url.startsWith("https://api.open-meteo.com/v1/forecast?")) {
    const date = new URL(url).searchParams.get("start_date")!;
    data = {
      hourly: {
        time: Array.from({ length: 24 }, (_, h) =>
          at(date, `${String(h).padStart(2, "0")}:00`),
        ),
        precipitation_probability: Array(24).fill(10),
        temperature_2m: Array(24).fill(29),
        cloud_cover: Array(24).fill(40),
      },
      daily: { sunrise: [at(date, "05:30")], sunset: [at(date, "18:00")] },
    };
  } else if (url === "https://openrouter.ai/api/v1/chat/completions") {
    const context = JSON.parse(body.messages[1].content);
    const candidate = context.candidates[0];
    const decision = {
      candidateId: candidate.id,
      summary: "TEST STUB ONLY — no real AI/provider calls.",
      rationale: candidate.stops.map(
        (s: { placeId: string; evidenceIds: string[] }) => ({
          placeId: s.placeId,
          reason: "Stubbed integration response.",
          evidenceIds: s.evidenceIds,
        }),
      ),
      tradeoffs: [],
      uncertainties: ["All HTTP responses in this test were stubbed."],
    };
    data = {
      model: "test/stub-model",
      choices: [
        {
          finish_reason: "stop",
          message: { content: JSON.stringify(decision) },
        },
      ],
      usage: { prompt_tokens: 1, completion_tokens: 1 },
    };
  } else throw new Error("Unexpected test URL. Network access prohibited.");
  return new Response(JSON.stringify(data), {
    headers: { "Content-Type": "application/json" },
  });
};
