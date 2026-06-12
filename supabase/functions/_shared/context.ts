import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

export interface BookRow {
  id: string;
  title: string;
  author: string;
  genre: string;
  pages: number;
  year: number | null;
  status: string;
  rating: number | null;
  current_page: number;
}

/// Compact, token-efficient library context (~22 tokens per book).
/// Deterministically ordered so the rendered prefix is byte-stable across
/// requests — required for Anthropic prompt caching to engage.
export async function fetchBooks(
  admin: SupabaseClient,
  userId: string,
): Promise<BookRow[]> {
  const { data, error } = await admin
    .from("books")
    .select("id,title,author,genre,pages,year,status,rating,current_page")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .order("id", { ascending: true });
  if (error) throw error;
  return (data ?? []) as BookRow[];
}

export function renderLibraryContext(
  books: BookRow[],
  opts: { maxBooks: number; ownerName?: string },
): string {
  // Deterministic truncation for the free tier: reading first, then rated,
  // then the rest — each group ordered by id.
  let selected = books;
  if (books.length > opts.maxBooks) {
    const score = (b: BookRow) =>
      b.status === "reading" ? 0 : b.rating != null ? 1 : 2;
    selected = [...books]
      .sort((a, b) => score(a) - score(b) || a.id.localeCompare(b.id))
      .slice(0, opts.maxBooks)
      .sort((a, b) => a.id.localeCompare(b.id));
  }

  const statusChar = (s: string) =>
    s === "read" ? "r" : s === "reading" ? "c" : "u";

  const lines = selected.map((b) =>
    [
      b.id.slice(0, 8), // short id — enough to disambiguate, saves tokens
      b.title,
      b.author,
      b.genre,
      b.pages,
      b.year ?? "",
      statusChar(b.status),
      b.rating ?? "",
      b.status === "reading" ? b.current_page : "",
    ].join("|")
  );

  const genreCounts = new Map<string, number>();
  for (const b of books) {
    genreCounts.set(b.genre, (genreCounts.get(b.genre) ?? 0) + 1);
  }
  const topGenres = [...genreCounts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 4)
    .map(([g, n]) => `${g} ${Math.round((n / books.length) * 100)}%`)
    .join(", ");

  const read = books.filter((b) => b.status === "read").length;
  const reading = books.filter((b) => b.status === "reading").length;

  return [
    `LIBRARY OF ${opts.ownerName ?? "THE READER"} (n=${books.length}${
      selected.length < books.length ? `, showing ${selected.length}` : ""
    }).`,
    `cols: id|title|author|genre|pages|year|status(r=read,c=reading,u=unread)|rating|curPage`,
    ...lines,
    `STATS: owned=${books.length} read=${read} reading=${reading} topGenres=${topGenres}`,
  ].join("\n");
}
