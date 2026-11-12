// Prints CLIProxyAPI openai-compatibility and claude entries for the Neuralink
// AI gateway, built from its live LiteLLM catalog and the hand-curated team
// overrides. Ids that share a LiteLLM upstream collapse to one entry.
//
// usage: bun nlk-gateway-cpa-models.ts <team-overrides.json> <cpa-registry.json>
// env: NLK_GATEWAY_URL, NLK_GATEWAY_TOKEN
//      or NLK_GATEWAY_MODELS / NLK_GATEWAY_MODEL_INFO (saved /v1/models and /v1/model/info)

type Json = Record<string, any>

type Row = {
  id: string
  upstream: string
  max_input_tokens: number | null
  max_output_tokens: number | null
  max_tokens: number | null
}

const [teamFile, registryFile] = process.argv.slice(2)
const gatewayUrl = process.env.NLK_GATEWAY_URL ?? "https://ai-gateway.svc.int.n7k.io"

async function load(path: string, file: string | undefined): Promise<Json> {
  if (file) return Bun.file(file).json()
  const res = await fetch(gatewayUrl + path, {
    headers: { authorization: `Bearer ${process.env.NLK_GATEWAY_TOKEN}`, accept: "application/json" },
    signal: AbortSignal.timeout(120_000),
  })
  if (!res.ok) throw new Error(`GET ${path}: HTTP ${res.status}`)
  const body = await res.json()
  if (!body.data?.length) throw new Error(`GET ${path}: no models`)
  return body
}

const [models, info, teamJson, registry] = await Promise.all([
  load("/v1/models", process.env.NLK_GATEWAY_MODELS),
  load("/v1/model/info", process.env.NLK_GATEWAY_MODEL_INFO),
  Bun.file(teamFile).json(),
  Bun.file(registryFile).json(),
])

// Team keys ending in -extended fold onto the base id (Grok 200k vs 500k is a
// CLI pin on one gateway model).
const team: Json = { ...teamJson.models }
for (const extKey of Object.keys(team).filter((k) => k.endsWith("-extended")).sort()) {
  const base = extKey.slice(0, -"-extended".length)
  const ext = team[extKey]
  const name = team[base]?.name ?? ext.name?.replaceAll(" Extended", "")
  team[base] = name == null ? ext : { ...ext, name }
}
for (const k of Object.keys(team)) if (k.endsWith("-extended")) delete team[k]

const modelsById = new Map<string, Json>(models.data.map((m: Json) => [m.id, m]))

const infoRows: Row[] = info.data.map((e: Json) => ({
  id: e.model_name,
  upstream: e.litellm_params?.model ?? e.model_name,
  max_input_tokens: e.model_info?.max_input_tokens ?? null,
  max_output_tokens: e.model_info?.max_output_tokens ?? null,
  max_tokens: e.model_info?.max_tokens ?? null,
}))
const infoIds = new Set(infoRows.map((r) => r.id))
const modelsOnlyRows: Row[] = models.data
  .filter((m: Json) => !infoIds.has(m.id))
  .map((m: Json) => ({
    id: m.id,
    upstream: m.id,
    max_input_tokens: m.max_input_tokens ?? null,
    max_output_tokens: m.max_output_tokens ?? null,
    max_tokens: null,
  }))

function rankId(id: string): number {
  let score = id.length
  if (id.includes("[1m]")) score -= 10000
  if (id.includes("fallback")) score -= 5000
  if (id.includes("preview")) score -= 20
  if (id.startsWith("us.")) score -= 100
  if (!id.includes(".") && !id.includes("-")) score -= 200
  if (id.startsWith("openai.")) score -= 10
  if (id.startsWith("global.")) score += 200
  if (id.includes("-")) score += 15
  return score
}

const byUpstream = Map.groupBy([...infoRows, ...modelsOnlyRows], (r) => r.upstream)

const resolved = [...byUpstream.values()]
  .map((rows) => {
    const best = rows.toSorted((a, b) => rankId(b.id) - rankId(a.id))[0]
    const field = (f: keyof Row) => rows.find((r) => r[f] != null)?.[f] ?? modelsById.get(best.id)?.[f] ?? null
    const teamKey = rows.map((r) => r.id).find((id) => id in team) ?? null
    const t: Json = teamKey == null ? {} : team[teamKey]
    const context =
      field("max_input_tokens") ??
      ("context_window" in t ? t.context_window : teamKey != null ? teamJson.provider_default_context_window : null)
    return { id: best.id, teamName: t.name ?? null, context }
  })
  .filter((r) => r.context != null)

function familyRank(id: string): number {
  if (id.startsWith("global.anthropic.")) return 0
  if (id.startsWith("global.")) return 1
  if (/^(claude|grok|gpt)/.test(id)) return 2
  if (id.startsWith("gemini")) return 3
  return 4
}
resolved.sort((a, b) => familyRank(a.id) - familyRank(b.id) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))

function displayName(r: (typeof resolved)[number]): string {
  if (r.teamName != null) return r.teamName
  let s = r.id
  for (const p of ["global.anthropic.", "us.anthropic.", "openai.", "global."]) if (s.startsWith(p)) s = s.slice(p.length)
  return s
}

// CLIProxyAPI strips `thinking` from requests to models without a thinking
// capability, and gateway ids are absent from its registry.
const claudeThinking = new Map<string, Json>(
  (registry.claude ?? [])
    .filter((m: Json) => m.thinking)
    .map((m: Json) => [
      m.id,
      Object.fromEntries(Object.entries(m.thinking).map(([k, v]) => [k.replaceAll("_", "-"), v])),
    ]),
)

// global.anthropic.claude-opus-4-6-v1 -> claude-opus-4-6
function registryId(id: string): string {
  let s = id.split("anthropic.").at(-1)!
  for (const suffix of ["-global-fallback", "-us-fallback", "-v1:0", "-v1"]) if (s.endsWith(suffix)) s = s.slice(0, -suffix.length)
  return s
}

const isAnthropic = (id: string) => id.includes("anthropic") || id.startsWith("claude") || id.includes("fable")

const entry = (r: (typeof resolved)[number]) => {
  const thinking = claudeThinking.get(registryId(r.id))
  return {
    name: r.id,
    alias: r.id,
    "display-name": displayName(r),
    "max-context-length": r.context,
    ...(thinking && { thinking }),
  }
}

const base = gatewayUrl.replace(/\/+$/, "")
console.log(
  JSON.stringify({
    "openai-compatibility": {
      name: "nlk-gateway",
      prefix: "work",
      "base-url": `${base}/v1`,
      models: resolved.filter((r) => !isAnthropic(r.id)).map(entry),
    },
    // Native Anthropic passthrough keeps thinking signatures intact.
    claude: {
      name: "nlk-gateway",
      prefix: "work",
      "base-url": base,
      models: resolved.filter((r) => isAnthropic(r.id)).map(entry),
    },
  }),
)
