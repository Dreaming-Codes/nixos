// Rewrites language_models.openai_compatible.<cpa provider>.available_models in
// Zed's settings.json from CLIProxyAPI's live model list. Zed has no model
// discovery for OpenAI-compatible providers.
//
// usage: bun zed.ts [settings.json]
import { readFile, rename, writeFile } from "node:fs/promises"
import { homedir } from "node:os"
import { fetchModels, providers, type Model } from "./catalog.ts"

const path = process.argv[2] ?? `${process.env.XDG_CONFIG_HOME ?? `${homedir()}/.config`}/zed/settings.json`

// xAI rows use the Responses API; CPA translates chat completions for the rest.
function toZed(m: Model) {
  const chatCompletions = m.ownedBy !== "xai"
  const reasons = m.efforts.length > 0
  return {
    name: m.id,
    display_name: m.provider === providers.personal ? `${m.name} (personal)` : m.name,
    max_tokens: m.context,
    max_output_tokens: m.output,
    capabilities: {
      tools: true,
      images: m.images,
      parallel_tool_calls: true,
      prompt_cache_key: false,
      chat_completions: chatCompletions,
      interleaved_reasoning: chatCompletions && reasons,
      max_tokens_parameter: false,
    },
    ...(reasons && { reasoning_effort: m.efforts.includes("high") ? "high" : m.efforts.at(-1) }),
  }
}

const text = await readFile(path, "utf8")
const settings = JSON.parse(text)
const compatible = settings.language_models?.openai_compatible ?? {}
const models = await fetchModels()

for (const provider of Object.values(providers)) {
  if (!compatible[provider]) continue
  compatible[provider].available_models = models.filter((m) => m.provider === provider).map(toZed)
}

const next = JSON.stringify(settings, null, 2) + "\n"
if (next !== text) {
  const tmp = `${path}.cpa-models.tmp`
  await writeFile(tmp, next, { mode: 0o600 })
  await rename(tmp, path)
}
