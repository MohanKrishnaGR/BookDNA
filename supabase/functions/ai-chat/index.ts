// Library GPT — streaming chat over the caller's own bookshelf.
// claude-haiku-4-5, SSE passthrough, prompt-cached library context,
// daily quotas. Falls back to a clearly-labelled demo reply when
// ANTHROPIC_API_KEY is not configured (keeps dev/E2E unblocked).

import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import {
  adminClient,
  consumeChatQuota,
  isPremium,
  logTokens,
  requireUser,
} from "../_shared/auth_quota.ts";
import { fetchBooks, renderLibraryContext } from "../_shared/context.ts";

const MODEL = "claude-haiku-4-5";
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

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return demoStream(books.length);
    }

    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 1024,
        stream: true,
        system: [
          {
            type: "text",
            text: `${PERSONA}\n\n${context}`,
            cache_control: { type: "ephemeral" },
          },
        ],
        messages: turns,
      }),
    });

    if (!anthropicRes.ok || !anthropicRes.body) {
      const detail = await anthropicRes.text().catch(() => "");
      console.error("anthropic error", anthropicRes.status, detail);
      return jsonResponse(
        {
          error: "upstream_error",
          message: anthropicRes.status === 429 || anthropicRes.status === 529
            ? "The assistant is busy right now — try again in a moment."
            : "The assistant hit a snag — try again.",
        },
        502,
      );
    }

    // Pipe the SSE bytes through unchanged while scanning message_delta
    // for usage, logged after the stream finishes.
    let tail = "";
    let tokensIn = 0;
    let tokensOut = 0;
    const decoder = new TextDecoder();
    const usageScanner = new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        controller.enqueue(chunk);
        tail = (tail + decoder.decode(chunk, { stream: true })).slice(-8192);
        const inMatch = tail.match(/"input_tokens"\s*:\s*(\d+)/g)?.pop();
        const outMatch = tail.match(/"output_tokens"\s*:\s*(\d+)/g)?.pop();
        if (inMatch) tokensIn = parseInt(inMatch.match(/\d+/)![0]);
        if (outMatch) tokensOut = parseInt(outMatch.match(/\d+/)![0]);
      },
      flush() {
        if (tokensIn || tokensOut) {
          // Fire-and-forget: usage logging must not delay the response end.
          logTokens(admin, user.id, tokensIn, tokensOut).catch((e) =>
            console.error("usage log failed", e)
          );
        }
      },
    });

    return new Response(anthropicRes.body.pipeThrough(usageScanner), {
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

/// Demo mode: no ANTHROPIC_API_KEY configured. Emits a short, clearly
/// labelled reply in the same SSE shape the client expects.
function demoStream(bookCount: number): Response {
  const text =
    `(Demo reply — set ANTHROPIC_API_KEY on the server for real answers.) ` +
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
