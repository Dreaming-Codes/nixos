import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { ask as askWithForms, type Answers, type Question } from "pi-choices";
import { Type } from "typebox";

const OTHER = "Other...";
const DONE = "Done";

type DialogOptions = { signal?: AbortSignal };

async function askOther(ctx: ExtensionContext, title: string, opts: DialogOptions): Promise<string | undefined> {
	const value = await ctx.ui.input(`${title} (other)`, "Enter your answer...", opts);
	return value?.trim() || undefined;
}

// Dialog hosts (RPC clients like T3 Code) only offer single select, so multi-select toggles one option per prompt.
async function askCheckbox(
	ctx: ExtensionContext,
	title: string,
	options: string[],
	allowOther: boolean,
	opts: DialogOptions,
): Promise<string[] | undefined> {
	const all = [...options];
	const custom = new Set<string>();
	const selected = new Set<string>();
	for (;;) {
		const labels = all.map((option) => `${selected.has(option) ? "[x]" : "[ ]"} ${option}`);
		const done = `${DONE} (${selected.size} selected)`;
		const choices = [...labels, ...(allowOther ? [OTHER] : []), done];
		const choice = await ctx.ui.select(title, choices, opts);
		if (choice === undefined) return undefined;
		if (choice === done) return all.filter((option) => selected.has(option));
		if (choice === OTHER) {
			const other = await askOther(ctx, title, opts);
			if (other === undefined) continue;
			if (!all.includes(other)) {
				all.push(other);
				custom.add(other);
			}
			selected.add(other);
			continue;
		}
		const option = all[labels.indexOf(choice)];
		if (custom.has(option)) {
			const edited = await ctx.ui.editor(`${title} (edit, clear to remove)`, option, opts);
			if (edited === undefined) continue;
			const value = edited.trim();
			custom.delete(option);
			selected.delete(option);
			const index = all.indexOf(option);
			if (!value || all.includes(value)) all.splice(index, 1);
			else {
				all[index] = value;
				custom.add(value);
			}
			if (value) selected.add(value);
			continue;
		}
		if (selected.has(option)) selected.delete(option);
		else selected.add(option);
	}
}

async function askWithDialogs(ctx: ExtensionContext, questions: Question[], signal?: AbortSignal): Promise<Answers | undefined> {
	const opts: DialogOptions = { signal };
	const answers: Answers = {};
	for (const [index, q] of questions.entries()) {
		const title = questions.length > 1 ? `(${index + 1}/${questions.length}) ${q.question}` : q.question;
		if (q.type === "input") {
			const value = await ctx.ui.input(title, q.placeholder ?? "", opts);
			if (value === undefined) return undefined;
			answers[q.id] = value.trim();
		} else if (q.type === "radio") {
			const choice = await ctx.ui.select(title, q.allowOther ? [...q.options, OTHER] : q.options, opts);
			if (choice === undefined) return undefined;
			const value = choice === OTHER ? await askOther(ctx, title, opts) : choice;
			if (value === undefined) return undefined;
			answers[q.id] = value;
		} else {
			const values = await askCheckbox(ctx, title, q.options, q.allowOther ?? false, opts);
			if (values === undefined) return undefined;
			answers[q.id] = values;
		}
	}
	return answers;
}

function text(value: string) {
	return { content: [{ type: "text" as const, text: value }] };
}

export default function askUser(pi: ExtensionAPI) {
	pi.registerTool({
		name: "ask_user",
		label: "Ask User",
		description:
			"Ask the user one or more structured questions and wait for the answers. " +
			"Returns a JSON object keyed by question id (string for radio/input, string[] for checkbox).",
		promptSnippet: "Ask the user structured questions (single choice, multiple choice, free text)",
		promptGuidelines: [
			"Use ask_user when a decision the user has not specified blocks progress, batching related questions into one call.",
		],
		parameters: Type.Object({
			questions: Type.Array(
				Type.Object({
					type: Type.Union([Type.Literal("radio"), Type.Literal("checkbox"), Type.Literal("input")], {
						description: "radio = single choice, checkbox = multiple choice, input = free text.",
					}),
					id: Type.String({ description: "Key for this answer in the result." }),
					question: Type.String({ description: "Question text shown to the user." }),
					options: Type.Optional(Type.Array(Type.String(), { description: "Required for radio and checkbox." })),
					allowOther: Type.Optional(Type.Boolean({ description: "Add a free-text 'Other...' option (radio/checkbox)." })),
					placeholder: Type.Optional(Type.String({ description: "Input placeholder (input only)." })),
				}),
				{ minItems: 1, description: "Questions asked in order." },
			),
		}),
		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			if (!ctx.hasUI) return text("ask_user needs an interactive session; ask the user in plain text instead.");

			const questions = params.questions as Question[];
			const invalid = questions.find((q) => q.type !== "input" && !q.options?.length);
			if (invalid) return text(`Question "${invalid.id}" is ${invalid.type} and needs a non-empty options list.`);

			const answers =
				ctx.mode === "tui" ? await askWithForms(ctx, questions) : await askWithDialogs(ctx, questions, signal);
			if (answers === undefined) return text("User cancelled the questions.");
			return text(JSON.stringify(answers, null, 2));
		},
	});
}
