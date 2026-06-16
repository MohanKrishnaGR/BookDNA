// ISBN → book metadata lookup, server-side so the Google Books API key stays
// a secret (GOOGLE_BOOKS_API_KEY) instead of shipping in the app.
//
// Google Books (keyed) first, then Open Library. Returns a normalized envelope
// the client maps into BookMetadata. Self-contained (no _shared imports) so it
// deploys as a single file. Returns { found: false } (HTTP 200) when neither
// catalogue has the ISBN — the client then offers manual entry.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const payload = await req.json().catch(() => ({}));
    const isbn = String(payload?.isbn ?? "")
      .replace(/[^0-9Xx]/g, "")
      .toUpperCase();
    if (isbn.length < 10) return json({ found: false, error: "invalid_isbn" });

    const key = Deno.env.get("GOOGLE_BOOKS_API_KEY");
    let result = key ? await fromGoogle(isbn, key) : null;
    result ??= await fromOpenLibrary(isbn);

    return json(result ? { found: true, ...result } : { found: false });
  } catch (e) {
    console.error("isbn-lookup", e);
    return json({ error: "internal_error" }, 500);
  }
});

async function fromGoogle(isbn: string, key: string) {
  const url =
    `https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}&country=IN&key=${key}`;
  const res = await fetch(url);
  if (!res.ok) return null;
  const j = await res.json();
  const item = j.items?.[0];
  if (!item) return null;
  const info = item.volumeInfo ?? {};
  const sale = item.saleInfo ?? {};
  const lp = sale.listPrice;
  const listPriceInr = lp && lp.currencyCode === "INR" ? lp.amount ?? null : null;
  return {
    source: "google",
    title: info.title ?? null,
    authors: info.authors ?? [],
    publisher: info.publisher ?? null,
    publishedDate: info.publishedDate ?? null,
    pageCount: info.pageCount ?? null,
    categories: info.categories ?? [],
    description: info.description ?? null,
    language: info.language ?? null,
    coverUrl: (info.imageLinks?.thumbnail ?? null)?.replace(
      "http://",
      "https://",
    ) ?? null,
    listPriceInr,
  };
}

async function fromOpenLibrary(isbn: string) {
  const res = await fetch(`https://openlibrary.org/isbn/${isbn}.json`);
  if (!res.ok) return null;
  const j = await res.json();
  let author = "";
  const key = j.authors?.[0]?.key;
  if (key) {
    try {
      const ar = await fetch(`https://openlibrary.org${key}.json`);
      if (ar.ok) author = (await ar.json()).name ?? "";
    } catch (_) { /* author is optional */ }
  }
  const desc = j.description;
  return {
    source: "openlibrary",
    title: j.title ?? null,
    authors: author ? [author] : [],
    publisher: j.publishers?.[0] ?? null,
    publishedDate: j.publish_date ?? null,
    pageCount: j.number_of_pages ?? null,
    categories: j.subjects ?? [],
    description: typeof desc === "string" ? desc : desc?.value ?? null,
    language: null,
    coverUrl: `https://covers.openlibrary.org/b/isbn/${isbn}-M.jpg`,
  };
}
