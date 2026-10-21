import "@supabase/functions-js/edge-runtime.d.ts"
import { withSupabase } from "@supabase/server"
import { createClient } from "@supabase/supabase-js"
import { tvdbExternalIDs } from "./tvdb-identifiers.ts"

type MediaType = "movie" | "series"
type Provider = "tmdb" | "tvdb"
type CatalogCategory = "trending" | "popular" | "now_playing" | "upcoming" | "top_rated" | "airing_today"

type MetadataRequest =
  | { action: "search"; query: string; type: MediaType; providers?: Provider[]; language?: string }
  | { action: "catalog"; type: MediaType; category?: CatalogCategory; genre_id?: number; page?: number; providers?: Provider[]; language?: string }
  | { action: "seed_catalog"; type: MediaType; page: number; seed_token: string; language?: string }
  | { action: "seed_status"; seed_token: string }
  | { action: "reindex_catalog"; type: MediaType; seed_token: string }
  | { action: "genres"; type: MediaType; language?: string }
  | { action: "details"; id: string; provider: Provider; type: MediaType; language?: string }
  | { action: "person"; id: string; language?: string }
  | { action: "entity"; kind: EntityKind; id: string; type: MediaType; page?: number; language?: string }
  | { action: "related"; id: string; type: MediaType; kind: RelatedKind; page?: number; language?: string }

/// Nuvio's company and network pages (TmdbEntityBrowseScreen).
type EntityKind = "company" | "network"
/// More Like This uses TMDB recommendations; Similar uses TMDB similar.
type RelatedKind = "recommendations" | "similar"

type NormalizedMetadata = {
  canonicalKey: string
  provider: Provider
  providerID: string
  type: MediaType
  title: string
  originalTitle?: string
  overview?: string
  releaseDate?: string
  posterPath?: string
  backdropPath?: string
  logoPath?: string
  genres: string[]
  externalIDs: Record<string, string>
  sourceURL: string
  metadataRecordID?: string
  details?: TitleDetails
}

type MetadataCredit = {
  id: string
  name: string
  role?: string
  character?: string
  profilePath?: string
}

type MetadataStudio = { id: string; name: string; logoPath?: string }
type MetadataGenre = { id: number; name: string }

type MetadataCollection = {
  id: string
  name: string
  members: NormalizedMetadata[]
}

type MetadataEpisode = {
  id: string
  seasonNumber: number
  episodeNumber: number
  title: string
  overview?: string
  runtimeMinutes?: number
  stillPath?: string
  airDate?: string
}

type MetadataSeason = {
  id: string
  seasonNumber: number
  title: string
  overview?: string
  posterPath?: string
  episodes: MetadataEpisode[]
}

/// TMDB video assets are deliberately represented as provider keys. Omnia can
/// use a native player only for a direct media URL; YouTube-hosted assets open
/// their official watch page rather than attempting to extract a stream.
type MetadataVideo = {
  id: string
  title: string
  type: string
  site: string
  key: string
  official: boolean
  publishedAt?: string
}

type TitleDetails = {
  ageRating?: string
  runtimeMinutes?: number
  status?: string
  budget?: number
  revenue?: number
  studios: MetadataStudio[]
  cast: MetadataCredit[]
  crew: MetadataCredit[]
  studioTitles: NormalizedMetadata[]
  collection?: MetadataCollection
  recommendations: NormalizedMetadata[]
  seasons: MetadataSeason[]
  trailers: MetadataVideo[]
  bonusContent: MetadataVideo[]
  // Added with detail payload version 5 (Nuvio detail page parity).
  productionCompanies?: MetadataStudio[]
  networks?: MetadataStudio[]
  creators?: MetadataCredit[]
  originCountries?: string[]
  originalLanguage?: string
  releaseDate?: string
  similar?: NormalizedMetadata[]
  recommendationsHaveMore?: boolean
  similarHaveMore?: boolean
}

type PersonCredit = {
  item: NormalizedMetadata
  character?: string
  job?: string
}

type PersonDetails = {
  id: string
  name: string
  biography?: string
  birthday?: string
  deathday?: string
  placeOfBirth?: string
  knownForDepartment?: string
  profilePath?: string
  imdbID?: string
  cast: PersonCredit[]
  crew: PersonCredit[]
}

const cacheLifetimeMilliseconds = 1000 * 60 * 60 * 24
const tvdbTokenLifetimeMilliseconds = 1000 * 60 * 60 * 24 * 25
let activeTVDBToken: { value: string; expiresAt: number } | null = null

function response(body: unknown, status = 200) {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "private, max-age=300" },
  })
}

function errorResponse(message: string, status: number) {
  return response({ error: { message } }, status)
}

function environment(name: string): string {
  const value = Deno.env.get(name)
  if (!value) throw new Error(`Missing ${name} Edge Function secret.`)
  return value
}

function isMediaType(value: unknown): value is MediaType {
  return value === "movie" || value === "series"
}

function isProvider(value: unknown): value is Provider {
  return value === "tmdb" || value === "tvdb"
}

function isProviderList(value: unknown): value is Provider[] {
  return Array.isArray(value)
    && value.length > 0
    && value.length <= 2
    && value.every(isProvider)
    && new Set(value).size === value.length
}

function isCatalogCategory(value: unknown): value is CatalogCategory {
  return value === "trending" || value === "popular" || value === "now_playing" || value === "upcoming" || value === "top_rated" || value === "airing_today"
}

function isRequest(value: unknown): value is MetadataRequest {
  if (!value || typeof value !== "object") return false
  const request = value as Record<string, unknown>
  if (request.action === "search") {
    return typeof request.query === "string" && isMediaType(request.type)
      && (request.providers === undefined || isProviderList(request.providers))
  }
  if (request.action === "catalog") {
    return isMediaType(request.type)
      && (request.category === undefined || isCatalogCategory(request.category))
      && (request.genre_id === undefined || (typeof request.genre_id === "number" && Number.isInteger(request.genre_id) && request.genre_id > 0))
      && (request.page === undefined || (typeof request.page === "number" && Number.isInteger(request.page) && request.page >= 1 && request.page <= 500))
      && (request.providers === undefined || isProviderList(request.providers))
  }
  if (request.action === "seed_catalog") {
    return isMediaType(request.type)
      && typeof request.page === "number" && Number.isInteger(request.page) && request.page >= 1 && request.page <= 100
      && typeof request.seed_token === "string" && request.seed_token.length >= 24
  }
  if (request.action === "seed_status") return typeof request.seed_token === "string" && request.seed_token.length >= 24
  if (request.action === "reindex_catalog") return isMediaType(request.type) && typeof request.seed_token === "string" && request.seed_token.length >= 24
  if (request.action === "genres") return isMediaType(request.type)
  if (request.action === "person") return isTMDBIdentifier(request.id)
  if (request.action === "entity") {
    return (request.kind === "company" || request.kind === "network")
      && isTMDBIdentifier(request.id) && isMediaType(request.type) && isPage(request.page)
  }
  if (request.action === "related") {
    return (request.kind === "recommendations" || request.kind === "similar")
      && isTMDBIdentifier(request.id) && isMediaType(request.type) && isPage(request.page)
  }
  return request.action === "details" && typeof request.id === "string" && isProvider(request.provider) && isMediaType(request.type)
}

function isTMDBIdentifier(value: unknown): value is string {
  return typeof value === "string" && /^\d{1,12}$/.test(value)
}

function isPage(value: unknown): boolean {
  return value === undefined || (typeof value === "number" && Number.isInteger(value) && value >= 1 && value <= 500)
}

function requestedProviders(request: { providers?: Provider[] }): Provider[] {
  return request.providers ?? ["tmdb", "tvdb"]
}

function canonicalKey(provider: Provider, type: MediaType, id: string) {
  return `${provider}:${type}:${id}`
}

function optionalText(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined
}

function isoDate(value: unknown): string | undefined {
  const date = optionalText(value)
  return date && /^\d{4}-\d{2}-\d{2}/.test(date) ? date.slice(0, 10) : undefined
}

function namedValues(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value.flatMap((entry) => {
    if (!entry || typeof entry !== "object") return []
    const name = optionalText((entry as Record<string, unknown>).name)
    return name ? [name] : []
  })
}

async function providerResponse(request: Response) {
  if (!request.ok) {
    throw new Error(`Provider returned ${request.status}.`)
  }
  return request.json()
}

async function tmdb(path: string, language: string, parameters: Record<string, string> = {}) {
  const token = environment("TMDB_READ_ACCESS_TOKEN")
  const url = new URL(`https://api.themoviedb.org/3${path}`)
  url.searchParams.set("language", language)
  for (const [name, value] of Object.entries(parameters)) {
    url.searchParams.set(name, value)
  }
  return providerResponse(await fetch(url, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  }))
}

/// TMDB's detail response can append its images endpoint. Prefer a logo in the
/// requested language, then a language-neutral transparent logo. The path is
/// intentionally preserved rather than exposing a provider URL to the client.
function tmdbLogoPath(value: Record<string, unknown>, language = "en"): string | undefined {
  const images = value.images
  if (!images || typeof images !== "object") return undefined
  const logos = (images as Record<string, unknown>).logos
  if (!Array.isArray(logos)) return undefined

  const records = logos.filter((logo): logo is Record<string, unknown> => Boolean(logo) && typeof logo === "object")
  const matchingLanguage = records.find((logo) => logo.iso_639_1 === language)
  const languageNeutral = records.find((logo) => logo.iso_639_1 === null)
  return optionalText((matchingLanguage ?? languageNeutral ?? records[0])?.file_path)
}

function tmdbExternalIDs(value: Record<string, unknown>, providerID: string): Record<string, string> {
  const identifiers: Record<string, string> = { tmdb: providerID }
  const external = value.external_ids
  if (!external || typeof external !== "object") return identifiers

  for (const key of ["imdb_id", "tvdb_id", "wikidata_id"]) {
    const identifier = optionalText((external as Record<string, unknown>)[key])
    if (identifier) identifiers[key === "imdb_id" ? "imdb" : key.replace("_id", "")] = identifier
  }
  return identifiers
}

function normalizeTMDB(value: Record<string, unknown>, type: MediaType): NormalizedMetadata | null {
  const id = value.id
  const title = type === "movie" ? value.title : value.name
  if ((typeof id !== "number" && typeof id !== "string") || typeof title !== "string") return null

  const providerID = String(id)
  return {
    canonicalKey: canonicalKey("tmdb", type, providerID),
    provider: "tmdb",
    providerID,
    type,
    title,
    originalTitle: optionalText(type === "movie" ? value.original_title : value.original_name),
    overview: optionalText(value.overview),
    releaseDate: isoDate(type === "movie" ? value.release_date : value.first_air_date),
    posterPath: optionalText(value.poster_path),
    backdropPath: optionalText(value.backdrop_path),
    logoPath: tmdbLogoPath(value),
    genres: namedValues(value.genres),
    externalIDs: tmdbExternalIDs(value, providerID),
    sourceURL: `https://www.themoviedb.org/${type === "movie" ? "movie" : "tv"}/${providerID}`,
  }
}

async function tmdbSearch(query: string, type: MediaType, language: string) {
  const endpoint = type === "movie" ? "/search/movie" : "/search/tv"
  const url = new URL(`https://api.themoviedb.org/3${endpoint}`)
  url.searchParams.set("query", query)
  url.searchParams.set("language", language)
  url.searchParams.set("include_adult", "false")
  const token = environment("TMDB_READ_ACCESS_TOKEN")
  const payload = await providerResponse(await fetch(url, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  })) as { results?: Record<string, unknown>[] }
  return (payload.results ?? []).flatMap((item) => {
    const normalized = normalizeTMDB(item, type)
    return normalized ? [normalized] : []
  }).slice(0, 20)
}

async function tmdbCatalog(type: MediaType, category: CatalogCategory, language: string, genreID?: number, page = 1) {
  if (genreID) {
    const endpoint = type === "movie" ? "/discover/movie" : "/discover/tv"
    const payload = await tmdb(endpoint, language, {
      with_genres: String(genreID),
      sort_by: "popularity.desc",
      include_adult: "false",
      page: String(page),
    }) as { results?: Record<string, unknown>[] }
    return (payload.results ?? []).flatMap((item) => {
      const normalized = normalizeTMDB(item, type)
      return normalized ? [normalized] : []
    }).slice(0, 20)
  }
  const endpoint = (() => {
    if (category === "trending") return type === "movie" ? "/trending/movie/week" : "/trending/tv/week"
    if (type === "movie") {
      if (category === "popular") return "/movie/popular"
      if (category === "now_playing") return "/movie/now_playing"
      if (category === "upcoming") return "/movie/upcoming"
      return "/movie/top_rated"
    }
    if (category === "popular") return "/tv/popular"
    if (category === "top_rated") return "/tv/top_rated"
    if (category === "airing_today") return "/tv/airing_today"
    return "/tv/popular"
  })()
  const payload = await tmdb(endpoint, language, { page: String(page) }) as { results?: Record<string, unknown>[] }
  return (payload.results ?? []).flatMap((item) => {
    const normalized = normalizeTMDB(item, type)
    return normalized ? [normalized] : []
  }).slice(0, 20)
}

async function tmdbGenres(type: MediaType, language: string): Promise<MetadataGenre[]> {
  const endpoint = type === "movie" ? "/genre/movie/list" : "/genre/tv/list"
  const payload = await tmdb(endpoint, language) as { genres?: { id?: unknown; name?: unknown }[] }
  return (payload.genres ?? []).flatMap((genre) => {
    return typeof genre.id === "number" && typeof genre.name === "string"
      ? [{ id: genre.id, name: genre.name }]
      : []
  })
}

async function tvdbToken() {
  if (activeTVDBToken && activeTVDBToken.expiresAt > Date.now()) {
    return activeTVDBToken.value
  }
  const body: Record<string, string> = { apikey: environment("TVDB_API_KEY") }
  const pin = Deno.env.get("TVDB_SUBSCRIBER_PIN")
  if (pin) body.pin = pin
  const payload = await providerResponse(await fetch("https://api4.thetvdb.com/v4/login", {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify(body),
  })) as { data?: { token?: string } }
  const token = payload.data?.token
  if (!token) throw new Error("TVDB did not return an access token.")
  activeTVDBToken = {
    value: token,
    expiresAt: Date.now() + tvdbTokenLifetimeMilliseconds,
  }
  return token
}

async function tvdb(path: string) {
  const token = await tvdbToken()
  return providerResponse(await fetch(`https://api4.thetvdb.com/v4${path}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  }))
}

function normalizeTVDB(value: Record<string, unknown>, type: MediaType): NormalizedMetadata | null {
  const id = value.tvdb_id ?? value.id ?? value.objectID
  const title = value.name ?? value.seriesName ?? value.movieName
  if ((typeof id !== "number" && typeof id !== "string") || typeof title !== "string") return null

  const providerID = String(id)
  return {
    canonicalKey: canonicalKey("tvdb", type, providerID),
    provider: "tvdb",
    providerID,
    type,
    title,
    overview: optionalText(value.overview),
    releaseDate: isoDate(value.firstAired ?? value.year),
    posterPath: optionalText(value.image_url ?? value.image),
    backdropPath: optionalText(value.thumbnail),
    genres: namedValues(value.genres),
    externalIDs: tvdbExternalIDs(providerID, value.remoteIds),
    sourceURL: `https://thetvdb.com/${type === "movie" ? "movies" : "series"}/${providerID}`,
  }
}

async function tvdbSearch(query: string, type: MediaType) {
  const url = new URL("https://api4.thetvdb.com/v4/search")
  url.searchParams.set("query", query)
  url.searchParams.set("type", type)
  const token = await tvdbToken()
  const payload = await providerResponse(await fetch(url, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  })) as { data?: Record<string, unknown>[] }
  return (payload.data ?? []).flatMap((item) => {
    const normalized = normalizeTVDB(item, type)
    return normalized ? [normalized] : []
  }).slice(0, 20)
}

async function tvdbCatalog(type: MediaType) {
  const endpoint = type === "movie" ? "/movies/filter" : "/series/filter"
  const url = new URL(`https://api4.thetvdb.com/v4${endpoint}`)
  url.searchParams.set("country", "usa")
  url.searchParams.set("lang", "eng")
  url.searchParams.set("sort", "score")
  url.searchParams.set("sortType", "desc")
  const token = await tvdbToken()
  const payload = await providerResponse(await fetch(url, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  })) as { data?: Record<string, unknown>[] }
  return (payload.data ?? []).flatMap((item) => {
    const normalized = normalizeTVDB(item, type)
    return normalized ? [normalized] : []
  }).slice(0, 20)
}

function records(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value)
    ? value.filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === "object")
    : []
}

function positiveInteger(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? Math.round(value) : undefined
}

function tmdbCredits(value: Record<string, unknown>, type: MediaType) {
  const creditContainer = (type === "series" ? value.aggregate_credits : value.credits) ?? value.credits
  const credits = creditContainer && typeof creditContainer === "object" ? creditContainer as Record<string, unknown> : {}
  const cast = records(credits.cast).flatMap((person) => {
    const id = person.id
    const name = optionalText(person.name)
    if ((typeof id !== "number" && typeof id !== "string") || !name) return []
    const roles = records(person.roles)
    const character = optionalText(person.character) ?? optionalText(roles[0]?.character)
    return [{ id: String(id), name, character, profilePath: optionalText(person.profile_path) }]
  }).slice(0, 18)
  const crew = records(credits.crew).flatMap((person) => {
    const id = person.id
    const name = optionalText(person.name)
    if ((typeof id !== "number" && typeof id !== "string") || !name) return []
    const roles = records(person.jobs ?? person.roles)
    const role = optionalText(person.job) ?? optionalText(roles[0]?.job) ?? optionalText(roles[0]?.character)
    return [{ id: String(id), name, role, profilePath: optionalText(person.profile_path) }]
  })
  return { cast, crew }
}

function tmdbStudios(value: Record<string, unknown>): MetadataStudio[] {
  const sources = records(value.production_companies)
  const fallback = sources.length > 0 ? sources : records(value.networks)
  return tmdbCompanies(fallback).slice(0, 4)
}

function tmdbCompanies(values: Record<string, unknown>[]): MetadataStudio[] {
  return values.flatMap((company) => {
    const id = company.id
    const name = optionalText(company.name)
    return (typeof id === "number" || typeof id === "string") && name
      ? [{ id: String(id), name, logoPath: optionalText(company.logo_path) }]
      : []
  })
}

function tmdbCreators(value: Record<string, unknown>): MetadataCredit[] {
  return records(value.created_by).flatMap((person) => {
    const id = person.id
    const name = optionalText(person.name)
    if ((typeof id !== "number" && typeof id !== "string") || !name) return []
    return [{ id: String(id), name, role: "Creator", profilePath: optionalText(person.profile_path) }]
  })
}

function tmdbHasMore(value: unknown): boolean {
  const container = value && typeof value === "object" ? value as Record<string, unknown> : {}
  const totalPages = positiveInteger(container.total_pages) ?? 1
  return totalPages > 1
}

function tmdbResultList(value: unknown, type: MediaType): NormalizedMetadata[] {
  const container = value && typeof value === "object" ? value as Record<string, unknown> : {}
  return records(container.results).flatMap((item) => {
    const normalized = normalizeTMDB(item, type)
    return normalized ? [normalized] : []
  })
}

async function tmdbStudioTitles(studio: MetadataStudio | undefined, type: MediaType, language: string, excludingID: string) {
  if (!studio) return []
  const endpoint = type === "movie" ? "/discover/movie" : "/discover/tv"
  const payload = await tmdb(endpoint, language, {
    with_companies: studio.id,
    sort_by: "popularity.desc",
    include_adult: "false",
  })
  return tmdbResultList(payload, type).filter((item) => item.providerID !== excludingID).slice(0, 16)
}

async function tmdbCollection(value: Record<string, unknown>, language: string): Promise<MetadataCollection | undefined> {
  const source = value.belongs_to_collection
  if (!source || typeof source !== "object") return undefined
  const collection = source as Record<string, unknown>
  const id = collection.id
  const name = optionalText(collection.name)
  if ((typeof id !== "number" && typeof id !== "string") || !name) return undefined

  const payload = await tmdb(`/collection/${id}`, language) as Record<string, unknown>
  return {
    id: String(id),
    name,
    members: records(payload.parts).flatMap((part) => {
      const item = normalizeTMDB(part, "movie")
      return item ? [item] : []
    }).slice(0, 20),
  }
}

function tmdbEpisode(value: Record<string, unknown>, fallbackSeasonNumber: number): MetadataEpisode | null {
  const id = value.id
  const episodeNumber = positiveInteger(value.episode_number)
  const seasonNumber = positiveInteger(value.season_number) ?? fallbackSeasonNumber
  const title = optionalText(value.name)
  if ((typeof id !== "number" && typeof id !== "string") || !episodeNumber || !title) return null

  return {
    id: String(id),
    seasonNumber,
    episodeNumber,
    title,
    overview: optionalText(value.overview),
    runtimeMinutes: positiveInteger(value.runtime),
    stillPath: optionalText(value.still_path),
    airDate: isoDate(value.air_date),
  }
}

async function tmdbSeasons(value: Record<string, unknown>, language: string, seriesID: string): Promise<MetadataSeason[]> {
  const summaries = records(value.seasons)
    .flatMap((season) => {
      const seasonNumber = positiveInteger(season.season_number)
      const id = season.id
      const title = optionalText(season.name)
      if (!seasonNumber || seasonNumber < 1 || (typeof id !== "number" && typeof id !== "string") || !title) return []
      return [{ id: String(id), seasonNumber, title, overview: optionalText(season.overview), posterPath: optionalText(season.poster_path) }]
    })
    .slice(0, 20)

  const resolved = await Promise.all(summaries.map(async (summary) => {
    const payload = await tmdb(`/tv/${seriesID}/season/${summary.seasonNumber}`, language) as Record<string, unknown>
    const episodes = records(payload.episodes)
      .flatMap((episode) => {
        const normalized = tmdbEpisode(episode, summary.seasonNumber)
        return normalized ? [normalized] : []
      })
    return { ...summary, episodes }
  }))

  return resolved.filter((season) => season.episodes.length > 0)
}

function tmdbVideos(value: Record<string, unknown>): { trailers: MetadataVideo[]; bonusContent: MetadataVideo[] } {
  const videos = records((value.videos as Record<string, unknown> | undefined)?.results)
    .flatMap((video) => {
      const id = video.id
      const title = optionalText(video.name)
      const type = optionalText(video.type)
      const site = optionalText(video.site)
      const key = optionalText(video.key)
      if ((typeof id !== "string" && typeof id !== "number") || !title || !type || !site || !key) return []
      // AVPlayer does not support YouTube watch pages. Keep only official
      // YouTube results, which can safely open the provider's own player.
      if (site.toLowerCase() !== "youtube") return []
      return [{
        id: String(id),
        title,
        type,
        site,
        key,
        official: video.official === true,
        publishedAt: isoDate(video.published_at),
      }]
    })
    .sort((lhs, rhs) => Number(rhs.official) - Number(lhs.official))

  return {
    trailers: videos.filter((video) => video.type === "Trailer" || video.type === "Teaser").slice(0, 12),
    bonusContent: videos.filter((video) => ["Behind the Scenes", "Featurette", "Bloopers", "Clip"].includes(video.type)).slice(0, 12),
  }
}

async function tmdbTitleDetails(value: Record<string, unknown>, type: MediaType, language: string, providerID: string): Promise<TitleDetails> {
  const studios = tmdbStudios(value)
  const [studioTitles, collection, seasons] = await Promise.all([
    tmdbStudioTitles(studios[0], type, language, providerID),
    type === "movie" ? tmdbCollection(value, language) : Promise.resolve(undefined),
    type === "series" ? tmdbSeasons(value, language, providerID) : Promise.resolve([]),
  ])
  const credits = tmdbCredits(value, type)
  const episodeRuntime = Array.isArray(value.episode_run_time)
    ? value.episode_run_time.find((minute): minute is number => typeof minute === "number" && minute > 0)
    : undefined
  const runtime = type === "movie" ? positiveInteger(value.runtime) : positiveInteger(episodeRuntime)
  const videos = tmdbVideos(value)
  return {
    ageRating: tmdbAgeRating(value, type),
    runtimeMinutes: runtime,
    status: optionalText(value.status),
    budget: positiveInteger(value.budget),
    revenue: positiveInteger(value.revenue),
    studios,
    cast: credits.cast,
    crew: credits.crew,
    studioTitles,
    collection,
    recommendations: tmdbResultList(value.recommendations, type).filter((item) => item.providerID !== providerID).slice(0, 20),
    seasons,
    trailers: videos.trailers,
    bonusContent: videos.bonusContent,
    productionCompanies: tmdbCompanies(records(value.production_companies)).slice(0, 8),
    networks: tmdbCompanies(records(value.networks)).slice(0, 8),
    creators: tmdbCreators(value),
    originCountries: originCountries(value),
    originalLanguage: optionalText(value.original_language),
    releaseDate: isoDate(type === "movie" ? value.release_date : value.first_air_date),
    similar: tmdbResultList(value.similar, type).filter((item) => item.providerID !== providerID).slice(0, 20),
    recommendationsHaveMore: tmdbHasMore(value.recommendations),
    similarHaveMore: tmdbHasMore(value.similar),
  }
}

function originCountries(value: Record<string, unknown>): string[] {
  const named = records(value.production_countries)
    .flatMap((country) => optionalText(country.iso_3166_1) ?? [])
  const codes = Array.isArray(value.origin_country)
    ? value.origin_country.filter((code): code is string => typeof code === "string" && code.length > 0)
    : []
  return [...new Set([...codes, ...named])].slice(0, 4)
}

/// A person's page (Nuvio's PersonDetailScreen): biography and every title
/// they acted in or worked on, most popular first.
async function tmdbPerson(id: string, language: string): Promise<PersonDetails> {
  const value = await tmdb(`/person/${id}`, language, {
    append_to_response: "combined_credits,external_ids",
  }) as Record<string, unknown>
  const name = optionalText(value.name)
  if (!name) throw new Error("Provider response did not contain a person.")
  const credits = value.combined_credits && typeof value.combined_credits === "object"
    ? value.combined_credits as Record<string, unknown>
    : {}
  const personCredits = (entries: Record<string, unknown>[], roleKey: "character" | "job") => {
    const seen = new Set<string>()
    return entries
      .filter((entry) => entry.media_type === "movie" || entry.media_type === "tv")
      .sort((lhs, rhs) => (Number(rhs.popularity) || 0) - (Number(lhs.popularity) || 0))
      .flatMap((entry) => {
        const item = normalizeTMDB(entry, entry.media_type === "tv" ? "series" : "movie")
        if (!item || !item.posterPath || seen.has(item.canonicalKey)) return []
        seen.add(item.canonicalKey)
        const role = optionalText(entry[roleKey])
        return [roleKey === "character" ? { item, character: role } : { item, job: role }]
      })
      .slice(0, 60)
  }
  const external = value.external_ids && typeof value.external_ids === "object"
    ? value.external_ids as Record<string, unknown>
    : {}
  return {
    id,
    name,
    biography: optionalText(value.biography),
    birthday: isoDate(value.birthday),
    deathday: isoDate(value.deathday),
    placeOfBirth: optionalText(value.place_of_birth),
    knownForDepartment: optionalText(value.known_for_department),
    profilePath: optionalText(value.profile_path),
    imdbID: optionalText(external.imdb_id),
    cast: personCredits(records(credits.cast), "character"),
    crew: personCredits(records(credits.crew), "job"),
  }
}

/// A production company's or TV network's titles (Nuvio's entity browse).
async function tmdbEntity(kind: EntityKind, id: string, type: MediaType, page: number, language: string) {
  const [info, listing] = await Promise.all([
    tmdb(`/${kind}/${id}`, language) as Promise<Record<string, unknown>>,
    tmdb(type === "movie" ? "/discover/movie" : "/discover/tv", language, {
      [kind === "network" ? "with_networks" : "with_companies"]: id,
      sort_by: "popularity.desc",
      include_adult: "false",
      page: String(page),
    }) as Promise<Record<string, unknown>>,
  ])
  return {
    entity: {
      id,
      kind,
      name: optionalText(info.name) ?? "",
      logoPath: optionalText(info.logo_path),
      headquarters: optionalText(info.headquarters),
      originCountry: optionalText(info.origin_country),
    },
    results: tmdbResultList(listing, type),
    page,
    totalPages: positiveInteger(listing.total_pages) ?? 1,
    providers: ["tmdb"],
  }
}

/// The full More Like This or Similar list behind a section's View All.
async function tmdbRelated(id: string, type: MediaType, kind: RelatedKind, page: number, language: string) {
  const listing = await tmdb(`/${type === "movie" ? "movie" : "tv"}/${id}/${kind}`, language, {
    page: String(page),
  }) as Record<string, unknown>
  return {
    results: tmdbResultList(listing, type),
    page,
    totalPages: positiveInteger(listing.total_pages) ?? 1,
    providers: ["tmdb"],
  }
}

function tmdbAgeRating(value: Record<string, unknown>, type: MediaType): string | undefined {
  if (type === "movie") {
    const releaseDates = value.release_dates
    if (!releaseDates || typeof releaseDates !== "object") return undefined
    const results = records((releaseDates as Record<string, unknown>).results)
    const preferred = results.find((result) => result.iso_3166_1 === "US") ?? results[0]
    return preferred ? records(preferred.release_dates)
      .map((release) => optionalText(release.certification))
      .find((rating): rating is string => Boolean(rating)) : undefined
  }

  const contentRatings = value.content_ratings
  if (!contentRatings || typeof contentRatings !== "object") return undefined
  const results = records((contentRatings as Record<string, unknown>).results)
  const preferred = results.find((result) => result.iso_3166_1 === "US") ?? results[0]
  return preferred ? optionalText(preferred.rating) : undefined
}

function serviceClient() {
  return createClient(
    environment("SUPABASE_URL"),
    environment("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  )
}

type MetadataRecordRow = {
  id: string
  canonical_key: string
  provider: string
  provider_id: string
  media_type: string
  title: string
  original_title?: string | null
  overview?: string | null
  release_date?: string | null
  poster_path?: string | null
  backdrop_path?: string | null
  external_ids: Record<string, string>
  payload?: unknown
}

function normalizedRecord(row: MetadataRecordRow): NormalizedMetadata {
  const payload = (row.payload ?? {}) as {
    sourceURL?: string
    logoPath?: string
    genres?: string[]
    detailVersion?: number
    detail?: TitleDetails
  }
  return {
    canonicalKey: row.canonical_key,
    provider: row.provider as Provider,
    providerID: row.provider_id,
    type: row.media_type as MediaType,
    title: row.title,
    originalTitle: row.original_title ?? undefined,
    overview: row.overview ?? undefined,
    releaseDate: row.release_date ?? undefined,
    posterPath: row.poster_path ?? undefined,
    backdropPath: row.backdrop_path ?? undefined,
    externalIDs: row.external_ids,
    sourceURL: payload.sourceURL ?? "",
    logoPath: payload.logoPath,
    genres: Array.isArray(payload.genres) ? payload.genres.filter((genre): genre is string => typeof genre === "string") : [],
    metadataRecordID: row.id,
    details: payload.detailVersion === 5 ? payload.detail : undefined,
  }
}

async function cachedRecord(key: string): Promise<NormalizedMetadata | null> {
  const { data, error } = await serviceClient()
    .from("metadata_records")
    .select("id, canonical_key, provider, provider_id, media_type, title, original_title, overview, release_date, poster_path, backdrop_path, external_ids, payload, expires_at")
    .eq("canonical_key", key)
    .gt("expires_at", new Date().toISOString())
    .maybeSingle()
  if (error) throw error
  if (!data) return null

  return normalizedRecord(data as MetadataRecordRow)
}

async function cacheRecord(item: NormalizedMetadata): Promise<NormalizedMetadata> {
  const now = new Date()
  const { data, error } = await serviceClient().from("metadata_records").upsert({
    canonical_key: item.canonicalKey,
    provider: item.provider,
    provider_id: item.providerID,
    media_type: item.type,
    title: item.title,
    original_title: item.originalTitle ?? null,
    overview: item.overview ?? null,
    release_date: item.releaseDate ?? null,
    poster_path: item.posterPath ?? null,
    backdrop_path: item.backdropPath ?? null,
    external_ids: item.externalIDs,
    payload: { sourceURL: item.sourceURL, logoPath: item.logoPath, genres: item.genres, detailVersion: 5, detail: item.details },
    source_updated_at: now.toISOString(),
    expires_at: new Date(now.getTime() + cacheLifetimeMilliseconds).toISOString(),
    updated_at: now.toISOString(),
  }, { onConflict: "canonical_key" }).select("id").single()
  if (error) throw error
  return { ...item, metadataRecordID: data.id }
}

/// The discovery index deliberately retains only normalized records and their
/// stable ordering. It is server-only; apps always read it through this
/// function, so provider credentials and database access remain private.
// TMDB's popular order changes daily. A stored page older than this is
// fetched again, so Home and Discover follow the current list instead of the
// order captured when the pool was first seeded.
const DISCOVERY_PAGE_MAX_AGE_MS = 24 * 60 * 60 * 1000

async function cachedCatalogPage(type: MediaType, page: number): Promise<{ items: NormalizedMetadata[]; isStale: boolean }> {
  const { data, error } = await serviceClient()
    .from("discovery_catalog_entries")
    .select("position, updated_at, metadata_records(id, canonical_key, provider, provider_id, media_type, title, original_title, overview, release_date, poster_path, backdrop_path, external_ids, payload)")
    .eq("media_type", type)
    .eq("catalog_category", "popular")
    .eq("source_page", page)
    .order("position", { ascending: true })
  if (error) throw error
  const isStale = (data ?? []).some((entry) => {
    const updatedAt = Date.parse(String(entry.updated_at ?? ""))
    return !Number.isFinite(updatedAt) || Date.now() - updatedAt > DISCOVERY_PAGE_MAX_AGE_MS
  })
  const items = (data ?? []).flatMap((entry) => {
    const record = entry.metadata_records
    return record && !Array.isArray(record) ? [normalizedRecord(record as MetadataRecordRow)] : []
  })
  return { items, isStale }
}

async function storeDiscoveryPage(type: MediaType, page: number, items: NormalizedMetadata[]) {
  const cached = await Promise.all(items.map(cacheRecord))
  const rows = cached.flatMap((item, index) => item.metadataRecordID ? [{
    media_type: type,
    catalog_category: "popular",
    source_page: page,
    position: index + 1,
    metadata_record_id: item.metadataRecordID,
    updated_at: new Date().toISOString(),
  }] : [])
  if (rows.length === 0) return cached
  const { error } = await serviceClient().from("discovery_catalog_entries").upsert(rows, {
    onConflict: "media_type,catalog_category,source_page,position",
  })
  if (error) throw error
  return cached
}

async function seedDiscoveryPage(type: MediaType, page: number, language: string) {
  return storeDiscoveryPage(type, page, await tmdbCatalog(type, "popular", language, undefined, page))
}

async function discoverySeedStatus() {
  const client = serviceClient()
  const [movieEntries, seriesEntries, movies, series] = await Promise.all([
    discoveryEntries("movie"),
    discoveryEntries("series"),
    client.from("discovery_catalog_entries").select("id", { count: "exact", head: true }).eq("media_type", "movie").eq("catalog_category", "popular"),
    client.from("discovery_catalog_entries").select("id", { count: "exact", head: true }).eq("media_type", "series").eq("catalog_category", "popular"),
  ])
  if (movies.error) throw movies.error
  if (series.error) throw series.error
  return {
    movies: { entries: movies.count ?? 0, titles: new Set(movieEntries.map((entry) => entry.metadata_record_id)).size },
    series: { entries: series.count ?? 0, titles: new Set(seriesEntries.map((entry) => entry.metadata_record_id)).size },
  }
}

type DiscoveryEntry = { source_page: number; position: number; metadata_record_id: string }

async function discoveryEntries(type: MediaType): Promise<DiscoveryEntry[]> {
  const entries: DiscoveryEntry[] = []
  for (let offset = 0; offset < 5000; offset += 1000) {
    const { data, error } = await serviceClient()
      .from("discovery_catalog_entries")
      .select("source_page, position, metadata_record_id")
      .eq("media_type", type)
      .eq("catalog_category", "popular")
      .order("source_page", { ascending: true })
      .order("position", { ascending: true })
      .range(offset, offset + 999)
    if (error) throw error
    const batch = (data ?? []) as DiscoveryEntry[]
    entries.push(...batch)
    if (batch.length < 1000) break
  }
  return entries
}

/// Compacts a moving provider ranking into stable first pages. The same title
/// can occur near multiple provider-page boundaries; Omnia's initial pool is
/// intentionally deduplicated before it is exposed as pages 1–50.
async function reindexDiscoveryCatalog(type: MediaType) {
  const client = serviceClient()
  const data = await discoveryEntries(type)

  const identifiers = new Set<string>()
  const unique = data.flatMap((entry) => {
    if (identifiers.has(entry.metadata_record_id)) return []
    identifiers.add(entry.metadata_record_id)
    return [entry.metadata_record_id]
  }).slice(0, 1000)
  if (unique.length < 1000) throw new Error(`Only ${unique.length} distinct ${type} titles are available to index.`)

  const { error: deleteError } = await client
    .from("discovery_catalog_entries")
    .delete()
    .eq("media_type", type)
    .eq("catalog_category", "popular")
    .lte("source_page", 50)
  if (deleteError) throw deleteError

  const rows = unique.map((metadataRecordID, index) => ({
    media_type: type,
    catalog_category: "popular",
    source_page: Math.floor(index / 20) + 1,
    position: (index % 20) + 1,
    metadata_record_id: metadataRecordID,
    updated_at: new Date().toISOString(),
  }))
  const { error: insertError } = await client.from("discovery_catalog_entries").insert(rows)
  if (insertError) throw insertError
  return { type, titles: unique.length, pages: 50 }
}

async function details(request: Extract<MetadataRequest, { action: "details" }>) {
  const key = canonicalKey(request.provider, request.type, request.id)
  const cached = await cachedRecord(key)
  // Cached compact records intentionally refresh once so every title detail
  // contains the richer metadata contract. Provider credentials stay here.
  if (cached?.details) return { item: cached, cached: true }

  const language = request.language ?? "en-US"
  const payload = request.provider === "tmdb"
    ? await tmdb(
      `/${request.type === "movie" ? "movie" : "tv"}/${request.id}`,
      language,
      {
        append_to_response: request.type === "movie"
          ? "images,external_ids,credits,similar,recommendations,release_dates,videos"
          : "images,external_ids,aggregate_credits,similar,recommendations,content_ratings,videos",
        include_image_language: `${language.split("-")[0]},null`,
      },
    )
    : await tvdb(`/${request.type === "movie" ? "movies" : "series"}/${request.id}/extended`)
  const rawItem = request.provider === "tvdb" ? (payload as { data?: Record<string, unknown> }).data : payload as Record<string, unknown>
  const normalized = rawItem && (request.provider === "tmdb" ? normalizeTMDB(rawItem, request.type) : normalizeTVDB(rawItem, request.type))
  const item = normalized && request.provider === "tmdb"
    ? { ...normalized, details: await tmdbTitleDetails(rawItem!, request.type, language, normalized.providerID) }
    : normalized
  if (!item) throw new Error("Provider response did not contain a usable media record.")
  return { item: await cacheRecord(item), cached: false }
}

export default {
  fetch: withSupabase({ auth: ["user", "publishable"] }, async (req) => {
    // Built-in discovery is readable with Omnia's verified publishable key.
    // User-owned library and playback rows remain protected by table RLS and
    // are not reachable through this endpoint.
    if (req.method !== "POST") return errorResponse("Use POST.", 405)

    let request: unknown
    try {
      request = await req.json()
    } catch {
      return errorResponse("The request body must be JSON.", 400)
    }
    if (!isRequest(request)) return errorResponse("Invalid metadata request.", 400)

    try {
      if (request.action === "seed_catalog") {
        // This is an operational endpoint, not a client capability. The
        // random server secret is never bundled into Omnia.
        if (request.seed_token !== environment("METADATA_SEED_TOKEN")) {
          return errorResponse("Not authorized to seed discovery.", 403)
        }
        const results = await seedDiscoveryPage(request.type, request.page, request.language ?? "en-US")
        return response({
          seeded: results.length,
          type: request.type,
          page: request.page,
        })
      }

      if (request.action === "seed_status") {
        if (request.seed_token !== environment("METADATA_SEED_TOKEN")) {
          return errorResponse("Not authorized to inspect discovery.", 403)
        }
        return response(await discoverySeedStatus())
      }

      if (request.action === "reindex_catalog") {
        if (request.seed_token !== environment("METADATA_SEED_TOKEN")) {
          return errorResponse("Not authorized to reindex discovery.", 403)
        }
        return response(await reindexDiscoveryCatalog(request.type))
      }

      if (request.action === "search") {
        const query = request.query.trim()
        if (query.length < 2 || query.length > 120) return errorResponse("Search text must be 2–120 characters.", 400)
        const language = request.language ?? "en-US"
        const providers = requestedProviders(request)
        const providerResults = await Promise.allSettled(providers.map((provider) =>
          provider === "tmdb"
            ? tmdbSearch(query, request.type, language)
            : tvdbSearch(query, request.type)
        ))
        const fulfilled = providerResults.flatMap((result) => result.status === "fulfilled" ? [result.value] : [])
        if (fulfilled.length === 0) throw new Error("All metadata providers failed.")
        return response({
          results: fulfilled.flat(),
          providers: providerResults.flatMap((result, index) => result.status === "fulfilled" ? [providers[index]] : []),
        })
      }

      if (request.action === "catalog") {
        const language = request.language ?? "en-US"
        const category = request.category ?? "trending"
        const page = request.page ?? 1
        const providers = requestedProviders(request)

        // The initial 1,000-title pool is served from Supabase. Once a user
        // scrolls beyond that pool, the same paged endpoint fetches and stores
        // the next provider page on demand.
        if (category === "popular" && !request.genre_id && providers[0] === "tmdb") {
          const indexed = await cachedCatalogPage(request.type, page)
          if (indexed.items.length > 0 && !indexed.isStale) {
            return response({ results: indexed.items, providers: ["tmdb"] })
          }
          try {
            const fetched = await seedDiscoveryPage(request.type, page, language)
            return response({ results: fetched, providers: ["tmdb"] })
          } catch (error) {
            // A stale page is still better than an empty shelf while TMDB is unreachable.
            if (indexed.items.length > 0) return response({ results: indexed.items, providers: ["tmdb"] })
            throw error
          }
        }

        const providerResults = await Promise.allSettled(providers.map((provider) =>
          provider === "tmdb"
            ? tmdbCatalog(request.type, category, language, request.genre_id, page)
            : tvdbCatalog(request.type)
        ))
        const fulfilled = providerResults.flatMap((result) => result.status === "fulfilled" ? [result.value] : [])
        if (fulfilled.length === 0) throw new Error("All metadata providers failed.")
        return response({
          results: fulfilled.flat(),
          providers: providerResults.flatMap((result, index) => result.status === "fulfilled" ? [providers[index]] : []),
        })
      }

      if (request.action === "genres") {
        const genres = await tmdbGenres(request.type, request.language ?? "en-US")
        return response({ genres, providers: ["tmdb"] })
      }

      if (request.action === "person") {
        return response({ person: await tmdbPerson(request.id, request.language ?? "en-US") })
      }

      if (request.action === "entity") {
        if (request.kind === "network" && request.type === "movie") return errorResponse("Networks list series only.", 400)
        return response(await tmdbEntity(request.kind, request.id, request.type, request.page ?? 1, request.language ?? "en-US"))
      }

      if (request.action === "related") {
        return response(await tmdbRelated(request.id, request.type, request.kind, request.page ?? 1, request.language ?? "en-US"))
      }

      return response(await details(request))
    } catch (error) {
      // Do not return upstream bodies, API credentials, or database details.
      console.error("metadata provider request failed", error instanceof Error ? error.message : "unknown error")
      // Seeding is protected by a separate server secret and is operational
      // tooling, not a client endpoint. Returning its concise failure reason
      // makes the importer retryable without exposing it to the app.
      if (request.action === "seed_catalog") {
        const operationalMessage = error instanceof Error
          ? error.message
          : JSON.stringify(error)
        return errorResponse(operationalMessage || "Discovery seed failed.", 502)
      }
      return errorResponse("Metadata is temporarily unavailable. Please try again.", 502)
    }
  }),
}
