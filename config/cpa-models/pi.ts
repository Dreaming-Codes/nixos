// Pi extension: registers the cpa-* providers with CLIProxyAPI's live model list.
import { cpaUrl, fetchModels, keyFile, providers, type Model, type ProviderId } from "./catalog.ts"

const thinkingLevels = ["minimal", "low", "medium", "high", "xhigh", "max"]

// Pi treats unmapped xhigh and max as unsupported and sends its own default
// for the other unmapped levels, so those are marked null.
function thinkingLevelMap(efforts: string[]) {
  const map: Record<string, string | null> = {}
  for (const level of thinkingLevels) {
    if (efforts.includes(level)) map[level] = level
    else if (level !== "xhigh" && level !== "max") map[level] = null
  }
  return map
}

// Claude rows keep thinking signatures over CPA's native Messages route.
const toPi = (m: Model) => ({
  id: m.id,
  name: m.name,
  ...(m.ownedBy === "anthropic" && { api: "anthropic-messages", baseUrl: cpaUrl }),
  reasoning: m.efforts.length > 0,
  thinkingLevelMap: thinkingLevelMap(m.efforts),
  input: m.images ? ["text", "image"] : ["text"],
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  contextWindow: m.context,
  maxTokens: m.output,
})

export default async function (pi: any) {
  let models: Model[] | undefined
  try {
    models = await fetchModels()
  } catch (error) {
    console.error("cpa-models: CLIProxyAPI unreachable, models load on refresh:", error)
  }
  const forProvider = (list: Model[], provider: ProviderId) => list.filter((m) => m.provider === provider).map(toPi)

  for (const [prefix, provider] of Object.entries(providers)) {
    const initial = models ? forProvider(models, provider) : []
    // Hosts without work logins have no work/ models.
    if (models && initial.length === 0) continue
    pi.registerProvider(provider, {
      name: `CLIProxyAPI ${prefix}`,
      baseUrl: `${cpaUrl}/v1`,
      apiKey: `!cat ${keyFile}`,
      api: "openai-completions",
      compat: { supportsDeveloperRole: false, supportsStore: false, supportsReasoningEffort: true, thinkingFormat: "openai" },
      models: initial,
      async refreshModels({ signal }: { signal: AbortSignal }) {
        return forProvider(await fetchModels(signal), provider)
      },
    })
  }
}
