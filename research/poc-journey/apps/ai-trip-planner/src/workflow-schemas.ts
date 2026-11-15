import { dayProposalSchema, type PlaceContext } from "./untimed.ts";
import { researchClaimSchema } from "./research-agent.ts";
export const string = { type: "string" };
export const strings = { type: "array", items: string };
export const objectSchema = (properties: Record<string, unknown>) => ({
  type: "object",
  additionalProperties: false,
  required: Object.keys(properties),
  properties,
});
export const claimSchema = objectSchema({
  ...researchClaimSchema.properties,
  applicability: objectSchema({
    kind: {
      type: "string",
      enum: [
        "general",
        "daily",
        "weekdays",
        "weekends",
        "date_range",
        "specific_date",
        "unknown",
      ],
    },
    weekdays: {
      type: "array",
      items: { type: "integer", minimum: 0, maximum: 6 },
    },
    validFrom: { type: ["string", "null"] },
    validThrough: { type: ["string", "null"] },
    exceptionNote: string,
  }),
});
export function proposalSchema(context: PlaceContext) {
  const base = dayProposalSchema(context);
  const item = base.properties.rows.items;
  return {
    ...base,
    properties: {
      ...base.properties,
      rows: {
        ...base.properties.rows,
        items: {
          ...item,
          required: [...item.required, "waitPurpose", "evidenceIds"],
          properties: {
            ...item.properties,
            evidenceIds: strings,
            waitPurpose: {
              type: ["string", "null"],
              enum: [
                null,
                "transfer_buffer",
                "queue",
                "opening",
                "event",
                "personal",
                "unclassified",
              ],
            },
          },
        },
      },
    },
  };
}
export const researchFinishSchema = objectSchema({
  summary: string,
  blocked: {
    type: "array",
    items: objectSchema({
      requirementId: string,
      reason: string,
      evidenceIds: strings,
      needsUserInput: { type: "boolean" },
    }),
  },
});
export const reviewSchema = objectSchema({
  summary: string,
  assessments: {
    type: "array",
    items: objectSchema({
      requirementId: string,
      verdict: {
        type: "string",
        enum: ["supported", "contradicted", "unknown"],
      },
      evidenceIds: strings,
      explanation: string,
    }),
  },
  findings: {
    type: "array",
    items: objectSchema({
      subject: string,
      severity: { type: "string", enum: ["conflict", "unknown", "advisory"] },
      explanation: string,
      evidenceIds: strings,
      nextAction: {
        type: "string",
        enum: ["research", "replan", "user_input", "none"],
      },
    }),
  },
});
