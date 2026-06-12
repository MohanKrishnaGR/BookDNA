// Deep shelf analysis — claude-fable-5 with structured (JSON schema) output.
// Monthly quota; result persisted to ai_analyses and returned to the client.
// Falls back to a deterministic demo result when ANTHROPIC_API_KEY is unset.

import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import {
  adminClient,
  consumeAnalyzeQuota,
  isPremium,
  logTokens,
  requireUser,
} from "../_shared/auth_quota.ts";
import {
  type BookRow,
  fetchBooks,
  renderLibraryContext,
} from "../_shared/context.ts";

const MODEL = "claude-fable-5";

const RESULT_SCHEMA = {
  type: "object",
  properties: {
    reading_profile: {
      type: "string",
      description:
        "2-3 sentence portrait of this reader inferred from the shelf",
    },
    personality: {
      type: "object",
      properties: {
        archetype: {
          type: "string",
          description: 'Short evocative label, e.g. "The Builder"',
        },
        traits: { type: "array", items: { type: "string" } },
      },
      required: ["archetype", "traits"],
      additionalProperties: false,
    },
    blind_spots: {
      type: "array",
      items: {
        type: "object",
        properties: {
          area: { type: "string" },
          why: { type: "string" },
        },
        required: ["area", "why"],
        additionalProperties: false,
      },
    },
    read_next: {
      type: "array",
      items: {
        type: "object",
        properties: {
          book_id: {
            type: "string",
            description: "MUST be an id from the library list (short form)",
          },
          reason: { type: "string" },
        },
        required: ["book_id", "reason"],
        additionalProperties: false,
      },
    },
    theme_edges: {
      type: "array",
      description:
        "Pairs of book ids (short form) that share a strong cross-book theme",
      items: { type: "array", items: { type: "string" } },
    },
  },
  required: [
    "reading_profile",
    "personality",
    "blind_spots",
    "read_next",
    "theme_edges",
  ],
  additionalProperties: false,
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const admin = adminClient();
    const user = await requireUser(admin, req);
    if (!user) return jsonResponse({ error: "unauthorized" }, 401);

    const premium = await isPremium(admin, user.id);
    const quota = await consumeAnalyzeQuota(admin, user.id, premium);
    if (!quota.ok) {
      return jsonResponse(
        {
          error: "quota_exceeded",
          used: quota.used,
          limit: quota.limit,
          message: premium
            ? "Monthly analysis limit reached."
            : "Free plan includes 1 analysis per month. Premium unlocks 8.",
        },
        429,
      );
    }

    const books = await fetchBooks(admin, user.id);
    if (books.length < 3) {
      return jsonResponse(
        { error: "library_too_small", message: "Add a few books first." },
        422,
      );
    }
    const context = renderLibraryContext(books, { maxBooks: 1000 });

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    let result: Record<string, unknown>;
    let model = MODEL;

    if (!apiKey) {
      result = demoResult(books);
      model = "demo";
    } else {
      const res = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: MODEL,
          max_tokens: 4000,
          thinking: { type: "adaptive" },
          system: [
            {
              type: "text",
              text:
                `You are BookDNA's shelf analyst. Study the library below and ` +
                `produce an honest, specific analysis. Constraints: exactly 3 ` +
                `blind_spots; exactly 3 read_next picks whose book_id values ` +
                `come from the library list and whose status is u (unread); ` +
                `5-15 theme_edges pairing books that share a meaningful theme, ` +
                `preferring pairs that cross genres.\n\n${context}`,
              cache_control: { type: "ephemeral" },
            },
          ],
          messages: [
            { role: "user", content: "Analyze my library." },
          ],
          output_config: { format: { type: "json_schema", schema: RESULT_SCHEMA } },
        }),
      });

      if (!res.ok) {
        const detail = await res.text().catch(() => "");
        console.error("anthropic error", res.status, detail);
        return jsonResponse(
          {
            error: "upstream_error",
            message: res.status === 429 || res.status === 529
              ? "The analyst is busy — try again in a few minutes."
              : "Analysis failed — try again.",
          },
          502,
        );
      }

      const payload = await res.json();
      const text = (payload.content as Array<{ type: string; text?: string }>)
        .find((b) => b.type === "text")?.text;
      if (!text) {
        return jsonResponse({ error: "empty_result" }, 502);
      }
      result = JSON.parse(text);

      const usage = payload.usage ?? {};
      logTokens(
        admin,
        user.id,
        usage.input_tokens ?? 0,
        usage.output_tokens ?? 0,
      ).catch((e) => console.error("usage log failed", e));
    }

    const { error: insertError } = await admin.from("ai_analyses").insert({
      user_id: user.id,
      model,
      result,
    });
    if (insertError) console.error("persist failed", insertError);

    return jsonResponse({ model, result });
  } catch (e) {
    console.error(e);
    return jsonResponse({ error: "internal_error" }, 500);
  }
});

/// Deterministic stand-in used when no API key is configured, built from the
/// real library so the downstream UI (analysis cards, knowledge graph) is
/// fully exercisable. Clearly labelled via model="demo".
function demoResult(books: BookRow[]): Record<string, unknown> {
  const sid = (b: BookRow) => b.id.slice(0, 8);
  const byGenre = new Map<string, BookRow[]>();
  for (const b of books) {
    byGenre.set(b.genre, [...(byGenre.get(b.genre) ?? []), b]);
  }
  const topGenres = [...byGenre.entries()].sort(
    (a, b) => b[1].length - a[1].length,
  );
  const unread = books.filter((b) => b.status === "unread");

  // Theme edges: same-author pairs, then a few cross-genre year-neighbours.
  const edges: string[][] = [];
  const byAuthor = new Map<string, BookRow[]>();
  for (const b of books) {
    byAuthor.set(b.author, [...(byAuthor.get(b.author) ?? []), b]);
  }
  for (const list of byAuthor.values()) {
    for (let i = 1; i < list.length; i++) {
      edges.push([sid(list[0]), sid(list[i])]);
    }
  }
  const sortedByYear = [...books].sort(
    (a, b) => (a.year ?? 0) - (b.year ?? 0),
  );
  for (let i = 1; i < sortedByYear.length && edges.length < 12; i++) {
    const a = sortedByYear[i - 1];
    const b = sortedByYear[i];
    if (a.genre !== b.genre) edges.push([sid(a), sid(b)]);
  }

  return {
    demo: true,
    reading_profile:
      `(Demo analysis — set ANTHROPIC_API_KEY for the real one.) A ` +
      `${topGenres[0]?.[0] ?? "nonfiction"}-leaning shelf of ${books.length} ` +
      `books with a healthy unread frontier of ${unread.length}.`,
    personality: {
      archetype: "The Builder",
      traits: ["Deep-diver", "Serial finisher", "Future-focused"],
    },
    blind_spots: topGenres.slice(0, 3).map(([genre]) => ({
      area: `Beyond ${genre}`,
      why: `Your ${genre} cluster is strong — branching out would widen the radar.`,
    })),
    read_next: unread.slice(0, 3).map((b) => ({
      book_id: sid(b),
      reason: `Already on your shelf and adjacent to your ${b.genre} momentum.`,
    })),
    theme_edges: edges.slice(0, 12),
  };
}
