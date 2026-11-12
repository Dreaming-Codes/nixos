// Model catalog served by CLIProxyAPI (CPA), shared by the OpenCode plugin,
// the Pi extension and the Zed settings generator.
import { readFile } from "node:fs/promises"
import { homedir } from "node:os"

export const cpaUrl = process.env.CPA_URL ?? "http://127.0.0.1:8317"
export const keyFile = process.env.CPA_KEY_FILE ?? `${homedir()}/.cli-proxy-api/client.key`

// CPA model prefix -> client provider id.
export const providers = { personal: "cpa-personal", work: "cpa-work" } as const
export type ProviderId = (typeof providers)[keyof typeof providers]

export type Model = {
  id: string
  provider: ProviderId
  name: string
  context: number
  output: number
  images: boolean
  efforts: string[]
  // "anthropic" rows speak the Messages API through CPA.
  ownedBy: string
}

// CPA lists non-claude ids to Anthropic clients as this prefix plus the id reversed.
const cloakPrefix = "claude-fable-5-dd-"
const uncloak = (id: string) => (id.startsWith(cloakPrefix) ? [...id.slice(cloakPrefix.length)].reverse().join("") : id)

const fallbackOutput = 32_000

async function get(path: string, key: string, headers: Record<string, string>, signal?: AbortSignal) {
  const res = await fetch(cpaUrl + path, {
    headers: { authorization: `Bearer ${key}`, ...headers },
    signal: signal ?? AbortSignal.timeout(10_000),
  })
  if (!res.ok) throw new Error(`CPA GET ${path}: HTTP ${res.status}`)
  return res.json() as Promise<any>
}

export async function fetchModels(signal?: AbortSignal): Promise<Model[]> {
  const key = (await readFile(keyFile, "utf8")).trim()
  // The Codex list carries modalities, effort levels and visibility. The
  // Anthropic list carries output limits and owners.
  const [codex, anthropic] = await Promise.all([
    get("/v1/models?client_version=cpa", key, {}, signal),
    get("/v1/models", key, { "anthropic-version": "2023-06-01" }, signal),
  ])
  const limits = new Map<string, any>(anthropic.data.map((m: any) => [uncloak(m.id), m]))
  const models: Model[] = []
  for (const m of codex.models) {
    const provider = providers[m.slug.split("/")[0] as keyof typeof providers]
    if (!provider || m.visibility === "hide") continue
    const limit = limits.get(m.slug)
    models.push({
      id: m.slug,
      provider,
      name: m.display_name || m.slug,
      context: m.context_window,
      output: limit?.max_tokens || fallbackOutput,
      images: (m.input_modalities ?? []).includes("image"),
      efforts: (m.supported_reasoning_levels ?? []).map((l: any) => l.effort),
      ownedBy: limit?.owned_by ?? "",
    })
  }
  return models.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
}
