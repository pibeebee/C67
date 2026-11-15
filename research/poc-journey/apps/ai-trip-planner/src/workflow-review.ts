import { ensure, object, text } from "./domain.ts";
import type { Requirement } from "./evidence-ledger.ts";
export type SemanticReview = {
  summary: string;
  assessments: {
    requirementId: string;
    verdict: "supported" | "contradicted" | "unknown";
    evidenceIds: string[];
    explanation: string;
  }[];
  findings: {
    subject: string;
    severity: "conflict" | "unknown" | "advisory";
    explanation: string;
    evidenceIds: string[];
    nextAction: "research" | "replan" | "user_input" | "none";
  }[];
};
export function validateReview(
  raw: unknown,
  requirements: Requirement[],
  knownIds: Set<string>,
  rowIndices: number[],
): SemanticReview {
  const v = object(raw, "semantic review");
  ensure(
    Array.isArray(v.assessments) &&
      v.assessments.length === requirements.length,
    "Reviewer must assess every requirement exactly once.",
  );
  const seen = new Set<string>();
  const citations = (raw: unknown) => {
    ensure(
      Array.isArray(raw) &&
        raw.length <= 30 &&
        raw.every((id) => typeof id === "string" && knownIds.has(id)),
      "Review cites unknown evidence.",
    );
    return raw as string[];
  };
  const assessments = v.assessments.map((item) => {
    const a = object(item, "assessment"),
      req = requirements.find((r) => r.id === a.requirementId);
    ensure(req && !seen.has(req.id), "Unknown or repeated review requirement.");
    seen.add(req.id);
    ensure(
      ["supported", "contradicted", "unknown"].includes(String(a.verdict)),
      "Invalid review verdict.",
    );
    const ids = citations(a.evidenceIds);
    if (a.verdict === "contradicted")
      ensure(
        ids.length > 0,
        "Contradicted requires evidence; missing data must be unknown.",
      );
    if (a.verdict === "supported") {
      ensure(
        ["provided", "supported"].includes(req.status),
        "Reviewer cannot promote missing, conditional or unavailable evidence to supported.",
      );
      ensure(
        ids.length > 0 && ids.some((id) => req.evidenceIds.includes(id)),
        "Supported verdict requires evidence belonging to this requirement.",
      );
    }
    return {
      requirementId: req.id,
      verdict: a.verdict as SemanticReview["assessments"][number]["verdict"],
      evidenceIds: ids,
      explanation: text(a.explanation, "review explanation", 3000),
    };
  });
  ensure(
    Array.isArray(v.findings) && v.findings.length <= 100,
    "Invalid semantic findings.",
  );
  const findings = v.findings.map((item) => {
    const f = object(item, "review finding");
    const subject = text(f.subject, "review subject", 150);
    ensure(
      subject === "summary" ||
        requirements.some((r) => r.id === subject) ||
        (/^row:\d+$/.test(subject) &&
          rowIndices.includes(Number(subject.slice(4)))),
      "Review subject is not a known requirement or simulation row.",
    );
    ensure(
      ["conflict", "unknown", "advisory"].includes(String(f.severity)) &&
        ["research", "replan", "user_input", "none"].includes(
          String(f.nextAction),
        ),
      "Invalid review action.",
    );
    const ids = citations(f.evidenceIds);
    ensure(
      f.severity !== "conflict" || ids.length > 0,
      "A factual contradiction must cite evidence; missing information is unknown.",
    );
    return {
      subject,
      severity: f.severity as SemanticReview["findings"][number]["severity"],
      explanation: text(f.explanation, "semantic explanation", 3000),
      evidenceIds: ids,
      nextAction:
        f.nextAction as SemanticReview["findings"][number]["nextAction"],
    };
  });
  return {
    summary: text(v.summary, "review summary", 6000),
    assessments,
    findings,
  };
}
