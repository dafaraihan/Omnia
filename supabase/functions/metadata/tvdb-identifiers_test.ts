import { tvdbExternalIDs } from "./tvdb-identifiers.ts"

function assertEquals(actual: unknown, expected: unknown) {
  const actualJSON = JSON.stringify(actual)
  const expectedJSON = JSON.stringify(expected)
  if (actualJSON !== expectedJSON) {
    throw new Error(`Expected ${expectedJSON}, received ${actualJSON}`)
  }
}

Deno.test("TVDB remote IDs preserve the canonical ID and expose IMDb/TMDB IDs", () => {
  const actual = tvdbExternalIDs("121361", [
    { id: "tt0944947", type: 2, sourceName: "IMDB" },
    { id: "1399", type: 10, sourceName: "TheMovieDB.com" },
    { id: "game-of-thrones", type: 5, sourceName: "Official Website" },
  ])

  assertEquals(actual, {
    tvdb: "121361",
    imdb: "tt0944947",
    tmdb: "1399",
  })
})

Deno.test("TVDB remote IDs tolerate malformed records and infer IMDb from its stable prefix", () => {
  const actual = tvdbExternalIDs("42", [
    null,
    { id: "", sourceName: "IMDB" },
    { id: "tt1234567" },
    { id: 99, sourceName: "TheMovieDB.com" },
  ])

  assertEquals(actual, {
    tvdb: "42",
    imdb: "tt1234567",
  })
})
