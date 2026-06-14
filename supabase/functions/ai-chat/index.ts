// Library GPT — streaming chat over the caller's own bookshelf.
// Google Gemini (gemini-2.5-flash, free tier). Gemini's native SSE is
// translated into the Anthropic-style {content_block_delta} envelope the
// Flutter client already parses, so the app needs no changes.
// Falls back to a clearly-labelled demo reply when GEMINI_API_KEY is unset.

import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import {
  adminClient,
  consumeChatQuota,
  isPremium,
  logTokens,
  requireUser,
} from "../_shared/auth_quota.ts";
import { fetchBooks, renderLibraryContext } from "../_shared/context.ts";

const MODEL = "gemini-2.5-flash";
const ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:streamGenerateContent?alt=sse`;
const MAX_TURNS = 20;
const MAX_CHARS_PER_TURN = 1000;

const PERSONA = `You are Library GPT inside the BookDNA app: a sharp, warm \
librarian who knows every book on the user's shelf (provided below) and \
nothing else about their collection. Rules:
- Recommend only from books in the library list; cite titles exactly.
- Be concrete and brief: 2-5 sentences, no headers or lists unless asked.
- Use the stats line for streaks/velocity claims; use en-IN conventions.
- If asked about a book not on the shelf, say it's not in the library and \
suggest the closest owned alternative.`;

interface ChatTurn {
  role: "user" | "assistant";
  content: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const admin = adminClient();
    const user = await requireUser(admin, req);
    if (!user) return jsonResponse({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => null);
    const turns = (body?.messages ?? []) as ChatTurn[];
    if (
      !Array.isArray(turns) ||
      turns.length === 0 ||
      turns.length > MAX_TURNS ||
      turns.some(
        (t) =>
          (t.role !== "user" && t.role !== "assistant") ||
          typeof t.content !== "string" ||
          t.content.length === 0 ||
          t.content.length > MAX_CHARS_PER_TURN,
      ) ||
      turns[turns.length - 1].role !== "user"
    ) {
      return jsonResponse({ error: "invalid_messages" }, 400);
    }

    const premium = await isPremium(admin, user.id);
    const quota = await consumeChatQuota(admin, user.id, premium);
    if (!quota.ok) {
      return jsonResponse(
        {
          error: "quota_exceeded",
          used: quota.used,
          limit: quota.limit,
          message: premium
            ? "Daily fair-use limit reached — resets at midnight."
            : "Free plan limit reached (10 messages/day). Premium unlocks 200.",
        },
        429,
      );
    }

    const books = await fetchBooks(admin, user.id);
    const context = renderLibraryContext(books, {
      maxBooks: premium ? 1000 : 100,
      ownerName: (user.user_metadata?.full_name as string) ?? undefined,
    });

    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      return demoStream(books.length);
    }

    const contents = turns.map((t) => ({
      role: t.role === "assistant" ? "model" : "user",
      parts: [{ text: t.content }],
    }));

    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: `${PERSONA}\n\n${context}` }] },
        contents,
        generationConfig: {
          maxOutputTokens: 1024,
          temperature: 0.7,
          // Disable 2.5-flash thinking: faster replies, no thinking-token spend.
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
    });

    if (!res.ok || !res.body) {
      const detail = await res.text().catch(() => "");
      console.error("gemini error", res.status, detail);
      return jsonResponse(
        {
          error: "upstream_error",
          message: res.status === 429
            ? "The assistant is busy right now — try again in a moment."
            : "The assistant hit a snag — try again.",
        },
        502,
      );
    }

    // Translate Gemini SSE → the client's {content_block_delta} envelope.
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    const reader = res.body.getReader();
    let buffer = "";
    let tokensIn = 0;
    let tokensOut = 0;

    const stream = new ReadableStream({
      async pull(controller) {
        const { done, value } = await reader.read();
        if (done) {
          controller.enqueue(
            encoder.encode(
              `event: message_stop\ndata: {"type":"message_stop"}\n\n`,
            ),
          );
          if (tokensIn || tokensOut) {
            await logTokens(admin, user.id, tokensIn, tokensOut);
          }
          controller.close();
          return;
        }
        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";
        for (const line of lines) {
          const t = line.trim();
          if (!t.startsWith("data:")) continue;
          const payload = t.slice(5).trim();
          if (!payload || payload === "[DONE]") continue;
          try {
            const obj = JSON.parse(payload);
            const text = (obj?.candidates?.[0]?.content?.parts ?? [])
              .map((p: { text?: string }) => p.text ?? "")
              .join("");
            if (text) {
              controller.enqueue(
                encoder.encode(
                  `event: content_block_delta\ndata: ${
                    JSON.stringify({
                      type: "content_block_delta",
                      delta: { type: "text_delta", text },
                    })
                  }\n\n`,
                ),
              );
            }
            const um = obj?.usageMetadata;
            if (um) {
              tokensIn = um.promptTokenCount ?? tokensIn;
              tokensOut = um.candidatesTokenCount ?? tokensOut;
            }
          } catch {
            // partial / non-JSON keepalive line — ignore
          }
        }
      },
      cancel() {
        reader.cancel();
      },
    });

    return new Response(stream, {
      headers: {
        ...corsHeaders,
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
      },
    });
  } catch (e) {
    console.error(e);
    return jsonResponse({ error: "internal_error" }, 500);
  }
});

/// Demo mode: no GEMINI_API_KEY configured. Emits a short, clearly labelled
/// reply in the same SSE shape the client expects.
function demoStream(bookCount: number): Response {
  const text =
    `(Demo reply — set GEMINI_API_KEY on the server for real answers.) ` +
    `I can see all ${bookCount} books on your shelf and once connected I'll ` +
    `answer questions about them, pick next reads, and find blind spots.`;
  const events = [
    `event: message_start\ndata: {"type":"message_start"}\n\n`,
    ...text.split(/(?<= )/).map(
      (word) =>
        `event: content_block_delta\ndata: ${
          JSON.stringify({
            type: "content_block_delta",
            delta: { type: "text_delta", text: word },
          })
        }\n\n`,
    ),
    `event: message_stop\ndata: {"type":"message_stop"}\n\n`,
  ];
  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    async start(controller) {
      for (const e of events) {
        controller.enqueue(encoder.encode(e));
        await new Promise((r) => setTimeout(r, 18));
      }
      controller.close();
    },
  });
  return new Response(stream, {
    headers: {
      ...corsHeaders,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
    },
  });
}
