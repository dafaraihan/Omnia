import "@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "@supabase/supabase-js"

const encoder = new TextEncoder()
const decoder = new TextDecoder("utf-8", { fatal: true })
const chunkSize = 524288
class Failure extends Error {
  constructor(readonly status: number) { super("vault_request_failed") }
}
function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Failure(400)
  return value as Record<string, unknown>
}
function exact(value: Record<string, unknown>, fields: string[]) {
  if (Object.keys(value).some(k => !fields.includes(k)) || fields.some(k => !(k in value))) throw new Failure(400)
}
function integer(value: unknown, max = Number.MAX_SAFE_INTEGER - 1): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0 || value > max) throw new Failure(400)
  return value
}
function id(value: unknown): string {
  if (typeof value !== "string" || !/^(provider\.(mdblist|anilist|plugin-tmdb|tmdb|tvdb|fanart)|tracker\.(trakt|simkl|mdblist|pmdb|anilist)|pin\.[0-9a-fA-F-]{36}|server\.[A-Za-z0-9_-]{1,120}|livetv\.(configuration|secrets)|playlist\.[A-Za-z0-9_-]{1,120})$/.test(value)) throw new Failure(400)
  return value
}
function uuid(value: unknown): string {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) throw new Failure(400)
  return value
}
function decode(value: unknown, limit: number): Uint8Array<ArrayBuffer> {
  if (typeof value !== "string" || value.length > Math.ceil(limit / 3) * 4 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) throw new Failure(400)
  const bytes = Uint8Array.from(atob(value), c => c.charCodeAt(0))
  if (bytes.length > limit) throw new Failure(413)
  return bytes
}
function encode(bytes: Uint8Array): string {
  let text = ""
  for (let offset = 0; offset < bytes.length; offset += 8192) text += String.fromCharCode(...bytes.subarray(offset, offset + 8192))
  return btoa(text)
}
async function body(request: Request) {
  if (!(request.headers.get("content-type")?.toLowerCase().split(";")[0].trim() === "application/json") || !request.body) throw new Failure(400)
  const reader = request.body.getReader()
  const pieces: Uint8Array[] = []
  let length = 0
  let timedOut = false
  const deadline = setTimeout(() => { timedOut = true; void reader.cancel() }, 15000)
  try {
    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      length += value.length
      if (length > 1048576) { await reader.cancel(); throw new Failure(413) }
      pieces.push(value)
    }
  } finally { clearTimeout(deadline); reader.releaseLock() }
  if (timedOut) throw new Failure(408)
  const result = new Uint8Array(length)
  let offset = 0
  for (const piece of pieces) { result.set(piece, offset); offset += piece.length }
  try { return object(JSON.parse(decoder.decode(result))) } catch { throw new Failure(400) }
}
// Keyring retains old versions for reads; active version is used for new writes.
// Values: CREDENTIAL_VAULT_KEYS={"1":"<base64 32 bytes>"}, CREDENTIAL_VAULT_ACTIVE_KEY=1.
async function cryptor(owner: string) {
  const raw = object(JSON.parse(Deno.env.get("CREDENTIAL_VAULT_KEYS") ?? "{}"))
  const active = Deno.env.get("CREDENTIAL_VAULT_ACTIVE_KEY") ?? ""
  const keys = new Map<string, CryptoKey>()
  for (const [version, value] of Object.entries(raw)) {
    if (!/^[1-9][0-9]{0,5}$/.test(version)) throw new Failure(503)
    const bytes = decode(value, 32)
    if (bytes.length !== 32) throw new Failure(503)
    keys.set(version, await crypto.subtle.importKey("raw", bytes, "AES-GCM", false, ["encrypt", "decrypt"]))
  }
  if (!keys.has(active)) throw new Failure(503)
  function aad(entryID: string, revision: number, extra: unknown[] = []) {
    return encoder.encode(JSON.stringify([owner, entryID, 1, revision, ...extra]))
  }
  return {
    async seal(bytes: Uint8Array<ArrayBuffer>, entryID: string, revision: number, extra: unknown[] = []) {
      const nonce = crypto.getRandomValues(new Uint8Array(12))
      const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce, additionalData: aad(entryID, revision, extra) }, keys.get(active)!, bytes)
      return { version: 1, key: active, nonce: encode(nonce), ciphertext: encode(new Uint8Array(ciphertext)) }
    },
    async open(value: unknown, entryID: string, revision: number, extra: unknown[] = []) {
      const envelope = object(value)
      const key = keys.get(String(envelope.key))
      if (!key || envelope.version !== 1) throw new Failure(503)
      return new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv: decode(envelope.nonce, 12), additionalData: aad(entryID, revision, extra) }, key, decode(envelope.ciphertext, chunkSize + 16)))
    },
  }
}
Deno.serve(async request => {
  const response = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", "Pragma": "no-cache", "X-Content-Type-Options": "nosniff" } })
  try {
    if (request.method !== "POST") throw new Failure(405)
    const token = request.headers.get("authorization")?.match(/^Bearer ([^\s]{1,16384})$/i)?.[1]
    if (!token) throw new Failure(401)
    const url = Deno.env.get("SUPABASE_URL")!
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const client = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: (input, init) => fetch(input, { ...init, redirect: "error", signal: AbortSignal.any([request.signal, AbortSignal.timeout(15000)]) }) } })
    const { data, error } = await client.auth.getUser(token)
    if (error || !data.user || data.user.is_anonymous) throw new Failure(401)
    const owner = data.user.id
    const input = await body(request)
    const action = input.action
    const cryptoBox = await cryptor(owner)
    async function rpc(action: string, value: unknown = {}) {
      const result = await client.rpc("credential_vault_operation", { p_owner: owner, p_action: action, p_data: value })
      if (result.error) throw new Failure(result.error.message === "quota" ? 429 : 400)
      return result.data
    }
    async function entry(row: unknown, payload = true) {
      if (!row) throw new Failure(404)
      const e = object(row)
      const result: Record<string, unknown> = { id: e.id, revision: Number(e.revision), deleted: e.deleted }
      if (!e.deleted && payload) result.payload = encode(await cryptoBox.open(e.envelope, String(e.id), Number(e.revision)))
      return result
    }
    if (action === "list") {
      exact(input, ["action"])
      const rows = await rpc("list") as unknown[]
      return response({ entries: await Promise.all(rows.map(row => entry(row, false))) })
    }
    if (action === "read") {
      exact(input, ["action", "id"])
      return response({ entry: await entry(await rpc("read", { id: id(input.id) })) })
    }
    if (action === "write") {
      exact(input, input.deleted === true ? ["action", "id", "expectedRevision", "deleted"] : ["action", "id", "expectedRevision", "deleted", "payload"])
      const entryID = id(input.id), revision = integer(input.expectedRevision)
      if (typeof input.deleted !== "boolean" || (!input.deleted && entryID.startsWith("playlist."))) throw new Failure(400)
      let envelope = null
      if (!input.deleted) {
        const bytes = decode(input.payload, 262144)
        try {
          const value: unknown = JSON.parse(decoder.decode(bytes))
          if (entryID.startsWith("provider.") || entryID.startsWith("tracker.")) {
            if (typeof value !== "string" || value.length === 0 || encoder.encode(value).length > 65536) throw new Failure(400)
          } else if (entryID.startsWith("pin.")) {
            if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9a-f]{64}$/i.test(value)) throw new Failure(400)
          } else {
            // Native adapters validate each connection/configuration field before apply.
            object(value)
          }
        } catch { throw new Failure(400) }
        envelope = await cryptoBox.seal(bytes, entryID, revision + 1)
      }
      const result = object(await rpc("write", { id: entryID, expectedRevision: revision, deleted: input.deleted, envelope }))
      return response({ entry: await entry(result.entry) }, result.conflict ? 409 : 200)
    }
    if (action === "attachmentBegin") {
      exact(input, ["action", "id", "expectedRevision", "byteCount", "sha256"])
      const entryID = id(input.id), byteCount = integer(input.byteCount, 67108864)
      if (!entryID.startsWith("playlist.") || byteCount < 1 || typeof input.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(input.sha256)) throw new Failure(400)
      const uploadID = crypto.randomUUID(), generation = crypto.randomUUID(), chunkCount = Math.ceil(byteCount / chunkSize)
      await rpc("begin", { id: entryID, uploadID, generation, byteCount, sha256: input.sha256, expectedRevision: integer(input.expectedRevision), chunkCount })
      return response({ uploadID, generation, chunkSize, chunkCount })
    }
    if (action === "attachmentPut" || action === "attachmentCommit") {
      exact(input, action === "attachmentPut" ? ["action", "uploadID", "index", "payload"] : ["action", "uploadID"])
      const uploadID = uuid(input.uploadID), upload = object(await rpc("upload", { uploadID }))
      if (!upload.upload_id || upload.retired_at || upload.committed_revision) throw new Failure(404)
      const entryID = String(upload.entry_id), revision = Number(upload.expected_revision) + 1
      if (action === "attachmentPut") {
        const index = integer(input.index, Number(upload.chunk_count) - 1)
        const bytes = decode(input.payload, chunkSize)
        const expected = Math.min(chunkSize, Number(upload.byte_count) - index * chunkSize)
        if (bytes.length !== expected) throw new Failure(400)
        await rpc("put", { uploadID, index, envelope: await cryptoBox.seal(bytes, entryID, revision, [uploadID, upload.generation, index]) })
        return response({ ok: true })
      }
      const manifest = { version: 1, uploadID, generation: upload.generation, byteCount: upload.byte_count, sha256: upload.sha256, chunkSize, chunkCount: upload.chunk_count }
      const result = object(await rpc("commit", { uploadID, id: entryID, expectedRevision: Number(upload.expected_revision), deleted: false, envelope: await cryptoBox.seal(encoder.encode(JSON.stringify(manifest)), entryID, revision) }))
      return response({ entry: await entry(result.entry) }, result.conflict ? 409 : 200)
    }
    if (action === "attachmentGet") {
      exact(input, ["action", "id", "revision", "index"])
      const entryID = id(input.id), revision = integer(input.revision)
      const current = object(await rpc("read", { id: entryID }))
      if (current.deleted || Number(current.revision) !== revision || !entryID.startsWith("playlist.")) throw new Failure(409)
      const manifest = object(JSON.parse(decoder.decode(await cryptoBox.open(current.envelope, entryID, revision))))
      const index = integer(input.index, Number(manifest.chunkCount) - 1)
      const envelope = await rpc("chunk", { uploadID: manifest.uploadID, index })
      return response({ payload: encode(await cryptoBox.open(envelope, entryID, revision, [manifest.uploadID, manifest.generation, index])) })
    }
    throw new Failure(400)
  } catch (error) {
    // Never include input, provider URLs, crypto failures, or SDK errors in output/logs.
    return response({ error: "vault_request_failed" }, error instanceof Failure ? error.status : 503)
  }
})
