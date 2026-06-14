// Deep shelf analysis — Google Gemini (gemini-2.5-flash) with structured
// JSON output via responseSchema. Monthly quota; result persisted to
// ai_analyses and returned to the client. Falls back to a deterministic
// demo result when GEMINI_API_KEY is unset.

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

const MODEL = "gemini-2.5-flash";
const ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

// Gemini Schema dialect: uppercase types, no additionalProperties / $ref.
// theme_edges modelled as {a,b} objects (nested string-arrays are flaky in
// the schema dialect); converted to [a,b] pairs before returning.
const RESULT_SCHEMA = {
  type: "OBJECT",
  properties: {
    reading_profile: { type: "STRING" },
    personality: {
      type: "OBJECT",
      properties: {
        archetype: { type: "STRING" },
        traits: { type: "ARRAY", items: { type: "STRING" } },
      },
      required: ["archetype", "traits"],
    },
    blind_spots: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: { area: { type: "STRING" }, why: { type: "STRING" } },
        required: ["area", "why"],
      },
    },
    read_next: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          book_id: { type: "STRING" },
          reason: { type: "STRING" },
        },
        required: ["book_id", "reason"],
      },
    },
    theme_edges: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: { a: { type: "STRING" }, b: { type: "STRING" } },
        required: ["a", "b"],
      },
    },
  },
  required: [
    "reading_profile",
    "personality",
    "blind_spots",
    "read_next",
    "theme_edges",
  ],
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

    const apiKey = Deno.env.get("GEMINI_API_KEY");
    let result: Record<string, unknown>;
    let model = MODEL;

    if (!apiKey) {
      result = demoResult(books);
      model = "demo";
    } else {
      const prompt =
        `You are BookDNA's shelf analyst. Study the library below and produce ` +
        `an honest, specific analysis. Constraints: exactly 3 blind_spots; ` +
        `exactly 3 read_next picks whose book_id values come from the library ` +
        `list and whose status is u (unread); 5-15 theme_edges pairing books ` +
        `(by short id) that share a meaningful theme, preferring pairs that ` +
        `cross genres.\n\n${context}`;

      const res = await fetch(ENDPOINT, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: prompt }] },
          contents: [
            { role: "user", parts: [{ text: "Analyze my library." }] },
          ],
          generationConfig: {
            responseMimeType: "application/json",
            responseSchema: RESULT_SCHEMA,
            maxOutputTokens: 8192,
            // gemini-2.5-flash "thinks" by default and thinking tokens count
            // against maxOutputTokens — disable so the JSON body fits.
            thinkingConfig: { thinkingBudget: 0 },
          },
        }),
      });

      if (!res.ok) {
        const detail = await res.text().catch(() => "");
        console.error("gemini error", res.status, detail);
        return jsonResponse(
          {
            error: "upstream_error",
            message: res.status === 429
              ? "The analyst is busy — try again in a few minutes."
              : "Analysis failed — try again.",
          },
          502,
        );
      }

      const payload = await res.json();
      const finishReason = payload?.candidates?.[0]?.finishReason;
      const text = (payload?.candidates?.[0]?.content?.parts ?? [])
        .map((p: { text?: string }) => p.text ?? "")
        .join("");
      if (!text) {
        console.error("empty result", finishReason, JSON.stringify(payload));
        return jsonResponse(
          { error: "empty_result", finishReason },
          502,
        );
      }
      let raw: Record<string, unknown>;
      try {
        raw = JSON.parse(text);
      } catch (parseErr) {
        console.error("parse failed", finishReason, text.slice(0, 200));
        return jsonResponse(
          { error: "parse_failed", finishReason, sample: text.slice(0, 200) },
          502,
        );
      }
      result = {
        ...raw,
        // {a,b} objects → [a,b] pairs the client + graph expect.
        theme_edges: (raw.theme_edges ?? [])
          .map((e: { a?: string; b?: string }) => [e.a, e.b])
          .filter((p: unknown[]) => p[0] && p[1]),
      };

      const um = payload?.usageMetadata;
      if (um) {
        await logTokens(
          admin,
          user.id,
          um.promptTokenCount ?? 0,
          um.candidatesTokenCount ?? 0,
        );
      }
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

/// Deterministic stand-in when no API key is configured, built from the real
/// library so the downstream UI (analysis cards, knowledge graph) is fully
/// exercisable. Labelled via model="demo".
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
      `(Demo analysis — set GEMINI_API_KEY for the real one.) A ` +
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
