type TVDBRemoteID = {
  id?: unknown
  sourceName?: unknown
}

/** Converts TVDB's extended `remoteIds` records into Omnia's ID namespace. */
export function tvdbExternalIDs(providerID: string, remoteIDs: unknown): Record<string, string> {
  const identifiers: Record<string, string> = { tvdb: providerID }
  if (!Array.isArray(remoteIDs)) return identifiers

  for (const value of remoteIDs) {
    if (!value || typeof value !== "object") continue
    const remote = value as TVDBRemoteID
    if (typeof remote.id !== "string") continue
    const identifier = remote.id.trim()
    if (!identifier) continue

    const source = typeof remote.sourceName === "string"
      ? remote.sourceName.toLowerCase().replace(/[^a-z0-9]/g, "")
      : ""

    if (!identifiers.imdb && (source.includes("imdb") || /^tt\d+$/i.test(identifier))) {
      identifiers.imdb = identifier
    } else if (!identifiers.tmdb && (source === "tmdb" || source.includes("themoviedb"))) {
      identifiers.tmdb = identifier
    }
  }

  return identifiers
}
