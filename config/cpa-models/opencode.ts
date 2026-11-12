// OpenCode plugin: fills the cpa-* providers declared in opencode.json with
// CLIProxyAPI's live model list.
import { fetchModels, providers, type Model } from "./catalog.ts"

const refreshMs = 10 * 60_000

const toInfo = (m: Model) => ({
  id: m.id,
  modelID: m.id,
  providerID: m.provider,
  name: m.name,
  capabilities: { tools: true, input: m.images ? ["text", "image"] : ["text"], output: ["text"] },
  variants: m.efforts.map((effort) => ({ id: effort, settings: { reasoningEffort: effort } })),
  ...(m.efforts.length > 0 && { body: { include_reasoning: true } }),
  time: { released: 0 },
  cost: [],
  status: "active",
  enabled: true,
  limit: { context: m.context, output: m.output },
})

export default {
  id: "cpa-models",
  async setup(ctx: any) {
    let models: Model[] = []
    let snapshot = ""
    const refresh = async () => {
      try {
        const next = await fetchModels()
        const json = JSON.stringify(next)
        if (json === snapshot) return false
        models = next
        snapshot = json
        return true
      } catch (error) {
        console.error("cpa-models: keeping the previous model list:", error)
        return false
      }
    }

    await refresh()
    await ctx.provider.transform((editor: any) => {
      // Hosts without work logins have no work/ models and no cpa-work provider.
      for (const provider of Object.values(providers)) {
        const infos = models.filter((m) => m.provider === provider).map(toInfo)
        if (infos.length > 0) editor.models.set(provider, infos)
      }
    })
    setInterval(async () => {
      if (await refresh()) await ctx.provider.reload()
    }, refreshMs).unref?.()
  },
}
