import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { setTimeout as sleep } from "node:timers/promises";
import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const MAX_REPORT_CHARS = 4000;
const STREAM_BATCH_MS = 1500;
const POLL_TIMEOUT_MS = 120_000;

type Trigger =
	| { kind: "stream"; match: RegExp }
	| { kind: "poll"; match?: RegExp; intervalMs: number };

interface Watch {
	id: string;
	label: string;
	command: string;
	trigger: Trigger;
	once: boolean;
	fired: number;
	stop: () => void;
}

function text(value: string) {
	return { content: [{ type: "text" as const, text: value }] };
}

function tail(value: string): string {
	return value.length > MAX_REPORT_CHARS ? `...${value.slice(-MAX_REPORT_CHARS)}` : value;
}

function describe(w: Watch): string {
	const t = w.trigger;
	const rule =
		t.kind === "stream"
			? `stream /${t.match.source}/`
			: `poll every ${t.intervalMs / 1000}s ${t.match ? `until /${t.match.source}/` : "on change"}`;
	return `${w.id} [${w.label}] ${rule}${w.once ? " once" : ""}, fired ${w.fired}x: ${w.command}`;
}

export default function watch(pi: ExtensionAPI) {
	const watches = new Map<string, Watch>();
	let nextId = 1;
	let ui: ExtensionContext["ui"] | undefined;

	function refreshStatus() {
		ui?.setStatus("watch", watches.size ? `watching ${watches.size}` : undefined);
	}

	function remove(w: Watch) {
		if (!watches.delete(w.id)) return;
		w.stop();
		refreshStatus();
	}

	function fire(w: Watch, report: string, end = w.once) {
		if (!watches.has(w.id)) return;
		w.fired++;
		const done = end ? "This watch is now stopped." : `Still watching. Stop it with watch_stop id=${w.id}.`;
		pi.sendMessage(
			{
				customType: "watch",
				content: `Watch ${w.id} [${w.label}] fired.\n\n${tail(report.trim())}\n\n${done}`,
				display: true,
			},
			{ triggerTurn: true, deliverAs: "steer" },
		);
		if (end) remove(w);
	}

	function startStream(w: Watch, match: RegExp, cwd: string): () => void {
		const proc = spawn("bash", ["-c", w.command], { cwd, detached: true, stdio: ["ignore", "pipe", "pipe"] });
		let pending: string[] = [];
		let timer: NodeJS.Timeout | undefined;
		const flush = () => {
			timer = undefined;
			const lines = pending;
			pending = [];
			if (lines.length) fire(w, lines.join("\n"));
		};
		const onLine = (line: string) => {
			if (!match.test(line)) return;
			pending.push(line);
			timer ??= setTimeout(flush, STREAM_BATCH_MS);
		};
		createInterface({ input: proc.stdout }).on("line", onLine);
		createInterface({ input: proc.stderr }).on("line", onLine);
		proc.on("error", (err) => fire(w, `Command failed to start: ${err.message}`, true));
		proc.on("exit", (code, signal) => {
			flush();
			fire(w, `Command exited (${signal ?? `code ${code}`}).`, true);
		});
		return () => {
			clearTimeout(timer);
			if (proc.exitCode === null && proc.pid) {
				try {
					process.kill(-proc.pid, "SIGTERM");
				} catch {}
			}
		};
	}

	function startPoll(w: Watch, trigger: Extract<Trigger, { kind: "poll" }>, cwd: string): () => void {
		const abort = new AbortController();
		let previous: string | boolean | undefined;
		const run = async () => {
			while (!abort.signal.aborted) {
				const result = await pi.exec("bash", ["-c", w.command], {
					cwd,
					signal: abort.signal,
					timeout: Math.min(trigger.intervalMs * 2, POLL_TIMEOUT_MS),
				});
				if (abort.signal.aborted) return;
				const output = `${result.stdout}${result.stderr}`;
				const state = trigger.match ? trigger.match.test(output) : output;
				const fires = trigger.match ? state === true && previous !== true : previous !== undefined && state !== previous;
				previous = state;
				if (fires) fire(w, `exit code ${result.code}\n${output}`);
				await sleep(trigger.intervalMs, undefined, { signal: abort.signal }).catch(() => {});
			}
		};
		void run();
		return () => abort.abort();
	}

	function stopAll() {
		for (const w of [...watches.values()]) remove(w);
	}

	pi.on("session_start", async (_event, ctx) => {
		ui = ctx.hasUI ? ctx.ui : undefined;
	});
	pi.on("session_shutdown", async () => {
		stopAll();
		ui = undefined;
	});

	pi.registerTool({
		name: "watch_start",
		label: "Watch",
		description:
			"Watch something in the background and get woken with a message when it happens. " +
			"kind=stream runs a long-lived shell command (e.g. `tail -F app.log`, `journalctl -fu foo`) and fires on output lines matching `match`. " +
			"kind=poll runs a shell command every `intervalSeconds` (e.g. `gh run view 123 --json status`, `curl -s url`) and fires when output starts matching `match`, or on any output change when `match` is omitted. " +
			"Watches end when the session ends.",
		promptSnippet: "Watch a command, log, URL or CI run in the background and wake on a condition",
		promptGuidelines: [
			"Use watch_start instead of sleeping or polling in bash when waiting on something slow (CI, deploys, logs, files).",
			"After starting a watch, end your turn; the watch wakes you with a message when it fires.",
		],
		parameters: Type.Object({
			kind: StringEnum(["stream", "poll"] as const),
			command: Type.String({ description: "Shell command run with bash -c in the session cwd." }),
			match: Type.Optional(Type.String({ description: "JavaScript regex. Required for stream." })),
			intervalSeconds: Type.Optional(Type.Number({ minimum: 1, description: "Poll interval. Default 30." })),
			once: Type.Optional(Type.Boolean({ description: "Stop after the first fire. Default true." })),
			label: Type.Optional(Type.String({ description: "Short name shown in reports." })),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			let match: RegExp | undefined;
			try {
				match = params.match ? new RegExp(params.match) : undefined;
			} catch (err) {
				return text(`Invalid regex: ${(err as Error).message}`);
			}
			if (params.kind === "stream" && !match) return text("kind=stream needs `match`.");

			const trigger: Trigger =
				params.kind === "stream"
					? { kind: "stream", match: match as RegExp }
					: { kind: "poll", match, intervalMs: (params.intervalSeconds ?? 30) * 1000 };
			const id = `w${nextId++}`;
			const w: Watch = {
				id,
				label: params.label ?? params.command.slice(0, 40),
				command: params.command,
				trigger,
				once: params.once ?? true,
				fired: 0,
				stop: () => {},
			};
			watches.set(id, w);
			w.stop = trigger.kind === "stream" ? startStream(w, trigger.match, ctx.cwd) : startPoll(w, trigger, ctx.cwd);
			refreshStatus();
			return text(`Started ${describe(w)}`);
		},
	});

	pi.registerTool({
		name: "watch_list",
		label: "Watches",
		description: "List active background watches.",
		parameters: Type.Object({}),
		async execute() {
			return text(watches.size ? [...watches.values()].map(describe).join("\n") : "No active watches.");
		},
	});

	pi.registerTool({
		name: "watch_stop",
		label: "Stop Watch",
		description: "Stop a background watch by id, or all watches with id=all.",
		parameters: Type.Object({ id: Type.String() }),
		async execute(_toolCallId, params) {
			if (params.id === "all") {
				const count = watches.size;
				stopAll();
				return text(`Stopped ${count} watch(es).`);
			}
			const w = watches.get(params.id);
			if (!w) return text(`No watch ${params.id}.`);
			remove(w);
			return text(`Stopped ${w.id}.`);
		},
	});

	pi.registerCommand("watches", {
		description: "List watches, or `/watches stop <id|all>`",
		handler: async (args, ctx) => {
			const [action, id] = args.trim().split(/\s+/);
			if (action === "stop" && id) {
				if (id === "all") stopAll();
				else {
					const w = watches.get(id);
					if (w) remove(w);
				}
			}
			const list = watches.size ? [...watches.values()].map(describe).join("\n") : "No active watches.";
			ctx.ui.notify(list, "info");
		},
	});
}
