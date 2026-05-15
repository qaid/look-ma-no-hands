/**
 * Agent Team — Dispatcher-only orchestrator with grid dashboard
 *
 * The primary Pi agent has NO codebase tools. It can ONLY delegate work
 * to specialist agents via the `dispatch_agent` tool. Each specialist
 * maintains its own Pi session for cross-invocation memory.
 *
 * Loads agent definitions from agents/*.md, .claude/agents/*.md, .pi/agents/*.md.
 * Teams are defined in .pi/agents/teams.yaml — on boot a select dialog lets
 * you pick which team to work with. Only team members are available for dispatch.
 *
 * Commands:
 *   /agents-team          — switch active team
 *   /agents-list          — list loaded agents
 *   /agents-grid N        — set column count (default 2)
 *
 * Usage: pi -e extensions/agent-team.ts
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { Text, type AutocompleteItem, truncateToWidth, visibleWidth } from "@mariozechner/pi-tui";
import { spawn } from "child_process";
import { readdirSync, readFileSync, existsSync, mkdirSync, unlinkSync } from "fs";
import { join, resolve } from "path";
import { applyExtensionDefaults } from "./themeMap.ts";

// ── Types ────────────────────────────────────────

interface AgentDef {
	name: string;
	description: string;
	tools: string;
	model?: string;
	systemPrompt: string;
	file: string;
}

interface AgentState {
	def: AgentDef;
	status: "idle" | "running" | "done" | "error";
	task: string;
	toolCount: number;
	elapsed: number;
	lastWork: string;
	contextPct: number;
	inputTokens: number;
	outputTokens: number;
	sessionFile: string | null;
	runCount: number;
	timer?: ReturnType<typeof setInterval>;
}

// ── Token Formatter ────────────────────────────

function formatTokens(n: number): string {
	if (n === 0) return "0";
	if (n >= 1000) return `${(n / 1000).toFixed(1)}k`;
	return `${n}`;
}

// ── Display Name Helper ──────────────────────────

function displayName(name: string): string {
	return name.split("-").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
}

// ── Extract model name from full model identifier ──

function extractModelName(modelId?: string): string {
	if (!modelId) return "?";
	// modelId format: "openrouter/anthropic/claude-haiku-4.5"
	// Extract the last part after the final "/"
	const parts = modelId.split("/");
	return parts[parts.length - 1] || "?";
}

// ── Display Name with Model ──────────────────────────

function displayNameWithModel(state: AgentState): string {
	const name = displayName(state.def.name);
	const model = extractModelName(state.def.model);
	return `${name} [${model}]`;
}

// ── Teams YAML Parser ────────────────────────────

interface TeamDef {
	agents: string[];
	not_covered: string[];
}

function parseTeamsYaml(raw: string): Record<string, TeamDef> {
	const teams: Record<string, TeamDef> = {};
	let current: string | null = null;
	// Track which sub-key we are currently populating ('agents' | 'not_covered' | null)
	let subKey: "agents" | "not_covered" | null = null;

	for (const line of raw.split("\n")) {
		// Skip comment lines
		if (line.trimStart().startsWith("#")) continue;

		// Top-level team key: "teamname:"
		const teamMatch = line.match(/^(\S[^:]*):\s*$/);
		if (teamMatch) {
			current = teamMatch[1].trim();
			teams[current] = { agents: [], not_covered: [] };
			subKey = null;
			continue;
		}

		if (!current) continue;

		// Sub-key inside a team: "  agents:" or "  not_covered:"
		const subKeyMatch = line.match(/^\s{2}(agents|not_covered):\s*(\[\])?\s*$/);
		if (subKeyMatch) {
			subKey = subKeyMatch[1] as "agents" | "not_covered";
			// "not_covered: []" inline empty list -- leave array empty and reset subKey
			if (subKeyMatch[2] === "[]") subKey = null;
			continue;
		}

		// List item under a sub-key: "    - item"
		const itemMatch = line.match(/^\s{4}-\s+(.+)$/);
		if (itemMatch && current && subKey) {
			teams[current][subKey].push(itemMatch[1].trim());
		}
	}
	return teams;
}

// ── Frontmatter Parser ───────────────────────────

function parseAgentFile(filePath: string): AgentDef | null {
	try {
		const raw = readFileSync(filePath, "utf-8");
		const match = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
		if (!match) return null;

		const frontmatter: Record<string, string> = {};
		let lastKey: string | null = null;
		for (const line of match[1].split("\n")) {
			const listItem = line.match(/^\s+-\s+(.+)$/);
			if (listItem && lastKey) {
				// Append to the current list key
				frontmatter[lastKey] = frontmatter[lastKey]
					? frontmatter[lastKey] + ", " + listItem[1].trim()
					: listItem[1].trim();
				continue;
			}
			const idx = line.indexOf(":");
			if (idx > 0) {
				lastKey = line.slice(0, idx).trim();
				frontmatter[lastKey] = line.slice(idx + 1).trim();
			}
		}

		if (!frontmatter.name) return null;

		return {
			name: frontmatter.name,
			description: frontmatter.description || "",
			tools: frontmatter.tools || "read,grep,find,ls",
			model: frontmatter.model || undefined,
			systemPrompt: match[2].trim(),
			file: filePath,
		};
	} catch {
		return null;
	}
}

function scanAgentDirs(cwd: string): AgentDef[] {
	const dirs = [
		join(cwd, "agents"),
		join(cwd, ".claude", "agents"),
		join(cwd, ".pi", "agents"),
	];

	const agents: AgentDef[] = [];
	const seen = new Set<string>();

	for (const dir of dirs) {
		if (!existsSync(dir)) continue;
		try {
			for (const file of readdirSync(dir)) {
				if (!file.endsWith(".md")) continue;
				const fullPath = resolve(dir, file);
				const def = parseAgentFile(fullPath);
				if (def && !seen.has(def.name.toLowerCase())) {
					seen.add(def.name.toLowerCase());
					agents.push(def);
				}
			}
		} catch {}
	}

	return agents;
}

// ── Extension ────────────────────────────────────

export default function (pi: ExtensionAPI) {
	const agentStates: Map<string, AgentState> = new Map();
	let allAgentDefs: AgentDef[] = [];
	let teams: Record<string, TeamDef> = {};
	let activeTeamName = "";
	let gridCols = 2;
	let widgetCtx: any;
	let sessionDir = "";
	let contextWindow = 0;

	function loadAgents(cwd: string) {
		// Create session storage dir
		sessionDir = join(cwd, ".pi", "agent-sessions");
		if (!existsSync(sessionDir)) {
			mkdirSync(sessionDir, { recursive: true });
		}

		// Load all agent definitions
		allAgentDefs = scanAgentDirs(cwd);

		// Load teams from .pi/agents/teams.yaml
		const teamsPath = join(cwd, ".pi", "agents", "teams.yaml");
		if (existsSync(teamsPath)) {
			try {
				teams = parseTeamsYaml(readFileSync(teamsPath, "utf-8"));
			} catch {
				teams = {};
			}
		} else {
			teams = {};
		}

		// If no teams defined, create a default "all" team
		if (Object.keys(teams).length === 0) {
			teams = { all: { agents: allAgentDefs.map(d => d.name), not_covered: [] } };
		}
	}

	function activateTeam(teamName: string) {
		activeTeamName = teamName;
		const members = (teams[teamName] || { agents: [], not_covered: [] }).agents;
		const defsByName = new Map(allAgentDefs.map(d => [d.name.toLowerCase(), d]));

		agentStates.clear();
		for (const member of members) {
			const def = defsByName.get(member.toLowerCase());
			if (!def) continue;
			const key = def.name.toLowerCase().replace(/\s+/g, "-");
			const sessionFile = join(sessionDir, `${key}.json`);
			agentStates.set(def.name.toLowerCase(), {
				def,
				status: "idle",
				task: "",
				toolCount: 0,
				elapsed: 0,
				lastWork: "",
				contextPct: 0,
				inputTokens: 0,
				outputTokens: 0,
				sessionFile: existsSync(sessionFile) ? sessionFile : null,
				runCount: 0,
			});
		}

		// Auto-size grid columns based on team size
		const size = agentStates.size;
		gridCols = size <= 3 ? size : size === 4 ? 2 : 3;
	}

	// ── Grid Rendering ───────────────────────────

	// Renders a full-width card for running/error agents (6 lines, bordered).
	function renderActiveCard(state: AgentState, width: number, theme: any): string[] {
		const w = width - 2;
		const truncate = (s: string, max: number) => s.length > max ? s.slice(0, max - 3) + "..." : s;

		const statusColor = state.status === "running" ? "accent" : "error";
		const statusIcon = state.status === "running" ? "●" : "✗";

		const nameDisplay = displayNameWithModel(state);
		const nameStr = theme.fg("accent", theme.bold(truncate(nameDisplay, w)));
		const nameVisible = Math.min(nameDisplay.length, w);

		const statusStr = `${statusIcon} ${state.status}`;
		const timeStr = ` ${Math.round(state.elapsed / 1000)}s`;
		const statusLine = theme.fg(statusColor, statusStr + timeStr);
		const statusVisible = statusStr.length + timeStr.length;

		const filled = Math.min(5, Math.ceil(state.contextPct / 20));
		const bar = "#".repeat(filled) + "-".repeat(5 - filled);
		const pctStr = contextWindow > 0 ? `${Math.ceil(state.contextPct)}%` : "?%";
		const ctxStr = `[${bar}] ${pctStr} · ${formatTokens(state.inputTokens)} in · ${formatTokens(state.outputTokens)} out`;
		const ctxLine = theme.fg("dim", ctxStr);
		const ctxVisible = ctxStr.length;

		const workRaw = state.task ? (state.lastWork || state.task) : state.def.description;
		const workLinesSrc = workRaw.split("\n").filter(l => l.trim());
		const workText1 = truncate(workLinesSrc[0] || "", Math.min(50, w - 1));
		const workText2 = truncate(workLinesSrc[1] || "", Math.min(50, w - 1));
		const workLine1 = theme.fg("muted", workText1);
		const workLine2 = theme.fg("muted", workText2);

		const top = "┌" + "─".repeat(w) + "┐";
		const bot = "└" + "─".repeat(w) + "┘";
		const border = (content: string, visLen: number) =>
			theme.fg("dim", "│") + content + " ".repeat(Math.max(0, w - visLen)) + theme.fg("dim", "│");

		return [
			theme.fg("dim", top),
			border(" " + nameStr, 1 + nameVisible),
			border(" " + statusLine, 1 + statusVisible),
			border(" " + ctxLine, 1 + ctxVisible),
			border(" " + workLine1, 1 + workText1.length),
			border(" " + workLine2, 1 + workText2.length),
			theme.fg("dim", bot),
		];
	}

	// Renders a single-line entry for idle/done agents.
	// idle: "Name: ○ idle"
	// done: "Name: ✓ done(14.2k)"  (combined input+output tokens)
	// Note: "error" agents are handled exclusively by renderActiveCard (they are
	// filtered into activeAgents in updateWidget) and will never reach this function.
	function renderCompactCard(state: AgentState, colWidth: number, theme: any): string[] {
		const truncate = (s: string, max: number) => s.length > max ? s.slice(0, max - 3) + "..." : s;
		const padTo = (styled: string, visLen: number) =>
			styled + " ".repeat(Math.max(0, colWidth - visLen));

		const nameDisplay = displayNameWithModel(state);

		if (state.status === "idle") {
			const suffix = ": ○ idle";
			const nameTrunc = truncate(nameDisplay, Math.max(1, colWidth - suffix.length));
			const raw = nameTrunc + suffix;
			const line =
				theme.fg("accent", theme.bold(nameTrunc)) +
				theme.fg("dim", suffix);
			return [padTo(line, raw.length)];
		}

		// done -- show combined token count
		const totalTokens = state.inputTokens + state.outputTokens;
		const tokenPart = totalTokens > 0 ? `(${formatTokens(totalTokens)})` : "";
		const suffix = ": ✓ done" + tokenPart;
		const nameTrunc = truncate(nameDisplay, Math.max(1, colWidth - suffix.length));
		const raw = nameTrunc + suffix;
		const line =
			theme.fg("accent", theme.bold(nameTrunc)) +
			theme.fg("success", suffix);
		return [padTo(line, raw.length)];
	}

	function updateWidget() {
		if (!widgetCtx) return;

		widgetCtx.ui.setWidget("agent-team", (_tui: any, theme: any) => {
			const text = new Text("", 0, 1);

			return {
				render(width: number): string[] {
					if (agentStates.size === 0) {
						text.setText(theme.fg("dim", "No agents found. Add .md files to agents/"));
						return text.render(width);
					}

					const allAgents = Array.from(agentStates.values());
					const activeAgents = allAgents.filter(a => a.status === "running" || a.status === "error");
					const inactiveAgents = allAgents.filter(a => a.status === "idle" || a.status === "done");
					const lines: string[] = [];

					// Active agents: each rendered full-width, stacked vertically
					for (const agent of activeAgents) {
						for (const line of renderActiveCard(agent, width, theme)) {
							lines.push(line);
						}
					}

					// Separator between sections when both are populated
					if (activeAgents.length > 0 && inactiveAgents.length > 0) {
						lines.push("");
					}

					// Inactive agents: grid using gridCols (set by activateTeam on boot, overridden by /agents-grid)
					if (inactiveAgents.length > 0) {
						const gap = 1;
						const cols = gridCols;
						const colWidth = Math.floor((width - gap * (cols - 1)) / cols);

						for (let i = 0; i < inactiveAgents.length; i += cols) {
							const rowAgents = inactiveAgents.slice(i, i + cols);
							const cards = rowAgents.map(a => renderCompactCard(a, colWidth, theme));

							// Pad last row to fill the grid (single-line cards)
							while (cards.length < cols) {
								cards.push([" ".repeat(colWidth)]);
							}

							// One line per grid row
							lines.push(cards.map(card => card[0] || " ".repeat(colWidth)).join(" ".repeat(gap)));
						}
					}

					text.setText(lines.join("\n"));
					return text.render(width);
				},
				invalidate() {
					text.invalidate();
				},
			};
		});
	}

	// ── Dispatch Agent (returns Promise) ─────────

	function dispatchAgent(
		agentName: string,
		task: string,
		ctx: any,
	): Promise<{ output: string; exitCode: number; elapsed: number }> {
		const key = agentName.toLowerCase();
		const state = agentStates.get(key);
		if (!state) {
			return Promise.resolve({
				output: `Agent "${agentName}" not found. Available: ${Array.from(agentStates.values()).map(s => displayName(s.def.name)).join(", ")}`,
				exitCode: 1,
				elapsed: 0,
			});
		}

		if (state.status === "running") {
			return Promise.resolve({
				output: `Agent "${displayName(state.def.name)}" is already running. Wait for it to finish.`,
				exitCode: 1,
				elapsed: 0,
			});
		}

		state.status = "running";
		state.task = task;
		state.toolCount = 0;
		state.elapsed = 0;
		state.lastWork = "";
		state.inputTokens = 0;
		state.outputTokens = 0;
		state.contextPct = 0;
		state.runCount++;
		updateWidget();

		const startTime = Date.now();
		state.timer = setInterval(() => {
			state.elapsed = Date.now() - startTime;
			updateWidget();
		}, 1000);

		const model = state.def.model
			? state.def.model
			: ctx.model
				? `${ctx.model.provider}/${ctx.model.id}`
				: "openrouter/google/gemini-3-flash-preview";

		// Session file for this agent
		const agentKey = state.def.name.toLowerCase().replace(/\s+/g, "-");
		const agentSessionFile = join(sessionDir, `${agentKey}.json`);

		// Build args — first run creates session, subsequent runs resume
		const args = [
			"--mode", "json",
			"-p",
			"--no-extensions",
			"--model", model,
			"--tools", state.def.tools,
			"--thinking", "off",
			"--append-system-prompt", state.def.systemPrompt,
			"--session", agentSessionFile,
		];

		// Continue existing session if we have one
		if (state.sessionFile) {
			args.push("-c");
		}

		args.push(task);

		const textChunks: string[] = [];

		return new Promise((resolve) => {
			const proc = spawn("pi", args, {
				stdio: ["ignore", "pipe", "pipe"],
				env: { ...process.env },
			});

			let buffer = "";

			proc.stdout!.setEncoding("utf-8");
			proc.stdout!.on("data", (chunk: string) => {
				buffer += chunk;
				const lines = buffer.split("\n");
				buffer = lines.pop() || "";
				for (const line of lines) {
					if (!line.trim()) continue;
					try {
						const event = JSON.parse(line);
						if (event.type === "message_update") {
							const delta = event.assistantMessageEvent;
							if (delta?.type === "text_delta") {
								textChunks.push(delta.delta || "");
								const full = textChunks.join("");
								const nonEmpty = full.split("\n").filter((l: string) => l.trim());
								state.lastWork = nonEmpty.slice(-2).join("\n");
								updateWidget();
							}
						} else if (event.type === "tool_execution_start") {
							state.toolCount++;
							updateWidget();
						} else if (event.type === "message_end") {
							const msg = event.message;
							if (msg?.usage) {
								const inputTok = msg.usage.input || msg.usage.input_tokens || 0;
								const outputTok = msg.usage.output || msg.usage.output_tokens || 0;
								if (contextWindow > 0) {
									state.contextPct = (inputTok / contextWindow) * 100;
								}
								state.inputTokens = inputTok;
								state.outputTokens += outputTok;
								updateWidget();
							}
						} else if (event.type === "agent_end") {
							const msgs = event.messages || [];
							const last = [...msgs].reverse().find((m: any) => m.role === "assistant");
							if (last?.usage) {
								const inputTok = last.usage.input || last.usage.input_tokens || 0;
								const outputTok = last.usage.output || last.usage.output_tokens || 0;
								if (contextWindow > 0) {
									state.contextPct = (inputTok / contextWindow) * 100;
								}
								state.inputTokens = inputTok;
								state.outputTokens += outputTok;
								updateWidget();
							}
						} else if (event.type === "tool_execution_end") {
							updateWidget();
						} else if (event.type === "agent_start") {
							state.lastWork = "starting...";
							updateWidget();
						}
					} catch {}
				}
			});

			proc.stderr!.setEncoding("utf-8");
			proc.stderr!.on("data", () => {});

			proc.on("close", (code) => {
				if (buffer.trim()) {
					try {
						const event = JSON.parse(buffer);
						if (event.type === "message_update") {
							const delta = event.assistantMessageEvent;
							if (delta?.type === "text_delta") textChunks.push(delta.delta || "");
						}
					} catch {}
				}

				clearInterval(state.timer);
				state.elapsed = Date.now() - startTime;
				state.status = code === 0 ? "done" : "error";

				// Mark session file as available for resume
				if (code === 0) {
					state.sessionFile = agentSessionFile;
				}

				const full = textChunks.join("");
				state.lastWork = full.split("\n").filter((l: string) => l.trim()).pop() || "";
				updateWidget();

				ctx.ui.notify(
					`${displayName(state.def.name)} ${state.status} in ${Math.round(state.elapsed / 1000)}s`,
					state.status === "done" ? "success" : "error"
				);

				resolve({
					output: full,
					exitCode: code ?? 1,
					elapsed: state.elapsed,
				});
			});

			proc.on("error", (err) => {
				clearInterval(state.timer);
				state.status = "error";
				state.lastWork = `Error: ${err.message}`;
				updateWidget();
				resolve({
					output: `Error spawning agent: ${err.message}`,
					exitCode: 1,
					elapsed: Date.now() - startTime,
				});
			});
		});
	}

	// ── dispatch_agent Tool (registered at top level) ──

	pi.registerTool({
		name: "dispatch_agent",
		label: "Dispatch Agent",
		description: "Dispatch a task to a specialist agent. The agent will execute the task and return the result. Use the system prompt to see available agent names.",
		parameters: Type.Object({
			agent: Type.String({ description: "Agent name (case-insensitive)" }),
			task: Type.String({ description: "Task description for the agent to execute" }),
		}),

		async execute(_toolCallId, params, _signal, onUpdate, ctx) {
			const { agent, task } = params as { agent: string; task: string };

			try {
				if (onUpdate) {
					onUpdate({
						content: [{ type: "text", text: `Dispatching to ${agent}...` }],
						details: { agent, task, status: "dispatching" },
					});
				}

				const result = await dispatchAgent(agent, task, ctx);

				const truncated = result.output.length > 8000
					? result.output.slice(0, 8000) + "\n\n... [truncated]"
					: result.output;

				const status = result.exitCode === 0 ? "done" : "error";
				const summary = `[${agent}] ${status} in ${Math.round(result.elapsed / 1000)}s`;

				return {
					content: [{ type: "text", text: `${summary}\n\n${truncated}` }],
					details: {
						agent,
						task,
						status,
						elapsed: result.elapsed,
						exitCode: result.exitCode,
						fullOutput: result.output,
					},
				};
			} catch (err: any) {
				return {
					content: [{ type: "text", text: `Error dispatching to ${agent}: ${err?.message || err}` }],
					details: { agent, task, status: "error", elapsed: 0, exitCode: 1, fullOutput: "" },
				};
			}
		},

		renderCall(args, theme) {
			const agentName = (args as any).agent || "?";
			const task = (args as any).task || "";
			const preview = task.length > 60 ? task.slice(0, 57) + "..." : task;
			return new Text(
				theme.fg("toolTitle", theme.bold("dispatch_agent ")) +
				theme.fg("accent", agentName) +
				theme.fg("dim", " — ") +
				theme.fg("muted", preview),
				0, 0,
			);
		},

		renderResult(result, options, theme) {
			const details = result.details as any;
			if (!details) {
				const text = result.content[0];
				return new Text(text?.type === "text" ? text.text : "", 0, 0);
			}

			// Streaming/partial result while agent is still running
			if (options.isPartial || details.status === "dispatching") {
				return new Text(
					theme.fg("accent", `● ${details.agent || "?"}`) +
					theme.fg("dim", " working..."),
					0, 0,
				);
			}

			const icon = details.status === "done" ? "✓" : "✗";
			const color = details.status === "done" ? "success" : "error";
			const elapsed = typeof details.elapsed === "number" ? Math.round(details.elapsed / 1000) : 0;
			const header = theme.fg(color, `${icon} ${details.agent}`) +
				theme.fg("dim", ` ${elapsed}s`);

			if (options.expanded && details.fullOutput) {
				const output = details.fullOutput.length > 4000
					? details.fullOutput.slice(0, 4000) + "\n... [truncated]"
					: details.fullOutput;
				return new Text(header + "\n" + theme.fg("muted", output), 0, 0);
			}

			return new Text(header, 0, 0);
		},
	});

	// ── Commands ─────────────────────────────────

	pi.registerCommand("agents-team", {
		description: "Select a team to work with",
		getArgumentCompletions: (prefix: string): AutocompleteItem[] | null => {
			const teamNames = Object.keys(teams);
			const items = teamNames.map(name => ({
				value: name,
				label: `${name} — ${(teams[name]?.agents || []).map((m: string) => displayName(m)).join(", ")}`,
			}));
			const filtered = items.filter(i => i.value.startsWith(prefix.toLowerCase()));
			return filtered.length > 0 ? filtered : items;
		},
		handler: async (args, ctx) => {
			widgetCtx = ctx;
			const teamNames = Object.keys(teams);
			if (teamNames.length === 0) {
				ctx.ui.notify("No teams defined in .pi/agents/teams.yaml", "warning");
				return;
			}

			// If a team name arg is provided, use it directly
			if (args && args.trim()) {
				const requestedTeam = args.trim().toLowerCase();
				const matchingTeam = teamNames.find(name => name.toLowerCase() === requestedTeam);

				if (!matchingTeam) {
					const validTeams = teamNames.join(", ");
					ctx.ui.notify(`Team "${args.trim()}" not found. Valid teams: ${validTeams}`, "error");
					return;
				}

				activateTeam(matchingTeam);
				updateWidget();
				ctx.ui.setStatus("agent-team", `Team: ${matchingTeam} (${agentStates.size})`);
				ctx.ui.notify(`Team: ${matchingTeam} — ${Array.from(agentStates.values()).map(s => displayName(s.def.name)).join(", ")}`, "success");
				return;
			}

			// No arg: show dialog
			const options = teamNames.map(name => {
				const members = (teams[name]?.agents || []).map((m: string) => displayName(m));
				return `${name} — ${members.join(", ")}`;
			});

			const choice = await ctx.ui.select("Select Team", options);
			if (choice === undefined) return;

			const idx = options.indexOf(choice);
			const name = teamNames[idx];
			activateTeam(name);
			updateWidget();
			ctx.ui.setStatus("agent-team", `Team: ${name} (${agentStates.size})`);
			ctx.ui.notify(`Team: ${name} — ${Array.from(agentStates.values()).map(s => displayName(s.def.name)).join(", ")}`, "info");
		},
	});

	pi.registerCommand("agents-list", {
		description: "List all loaded agents",
		handler: async (_args, _ctx) => {
			widgetCtx = _ctx;
			const names = Array.from(agentStates.values())
				.map(s => {
					const session = s.sessionFile ? "resumed" : "new";
					return `${displayName(s.def.name)} (${s.status}, ${session}, runs: ${s.runCount}): ${s.def.description}`;
				})
				.join("\n");
			_ctx.ui.notify(names || "No agents loaded", "info");
		},
	});

	pi.registerCommand("agents-grid", {
		description: "Set grid columns: /agents-grid <1-6>",
		getArgumentCompletions: (prefix: string): AutocompleteItem[] | null => {
			const items = ["1", "2", "3", "4", "5", "6"].map(n => ({
				value: n,
				label: `${n} columns`,
			}));
			const filtered = items.filter(i => i.value.startsWith(prefix));
			return filtered.length > 0 ? filtered : items;
		},
		handler: async (args, _ctx) => {
			widgetCtx = _ctx;
			const n = parseInt(args?.trim() || "", 10);
			if (n >= 1 && n <= 6) {
				gridCols = n;
				_ctx.ui.notify(`Grid set to ${gridCols} columns`, "info");
				updateWidget();
			} else {
				_ctx.ui.notify("Usage: /agents-grid <1-6>", "error");
			}
		},
	});

	// ── System Prompt Override ───────────────────

	pi.on("before_agent_start", async (_event, _ctx) => {
		// Build dynamic agent catalog from active team only
		const agentCatalog = Array.from(agentStates.values())
			.map(s => `### ${displayName(s.def.name)}\n**Dispatch as:** \`${s.def.name}\`\n${s.def.description}\n**Tools:** ${s.def.tools}`)
			.join("\n\n");

		const teamMembers = Array.from(agentStates.values()).map(s => displayName(s.def.name)).join(", ");
		const teamDef = teams[activeTeamName] || { agents: [], not_covered: [] };
		const notCoveredList = teamDef.not_covered.length > 0
			? teamDef.not_covered.join(", ")
			: "nothing -- full coverage";

		return {
			systemPrompt: `You are a dispatcher agent. You coordinate specialist agents to accomplish tasks.
You do NOT have direct access to the codebase. You MUST delegate all work through
agents using the dispatch_agent tool.

## Active Team: ${activeTeamName}
Members: ${teamMembers}
Not covered by this team: ${notCoveredList}
You can ONLY dispatch to agents listed below. Do not attempt to dispatch to agents outside this team.

## How to Work
- Analyze the user's request and break it into clear sub-tasks
- Choose the right agent(s) for each sub-task
- Dispatch tasks using the dispatch_agent tool
- Review results and dispatch follow-up agents if needed
- If a task fails, try a different agent or adjust the task description
- Summarize the outcome for the user

## Rules
- NEVER try to read, write, or execute code directly — you have no such tools
- ALWAYS use dispatch_agent to get work done
- You can chain agents: use scout to explore, then builder to implement
- You can dispatch the same agent multiple times with different tasks
- Keep tasks focused — one clear objective per dispatch

## Agents

${agentCatalog}

## Team Assessment (Required Before Every Task)

Before dispatching any work, you MUST emit a visible Team Fit Assessment block as the
FIRST thing in your response -- before any dispatch_agent call. Skipping or inlining
this block in reasoning is not permitted.

The block MUST look exactly like this:

---
**Team Fit Assessment**
- Task requires: [list capabilities needed]
- Active team covers: [yes/no for each capability]
- Gaps: [list missing capabilities, or "none"]
- Decision: [proceed | ask user to switch teams]
---

Then follow this logic:
1. Identify what agent capabilities the task requires (e.g. code changes need backend-engineer + code-reviewer; scraper work needs scraper-builder; strategic decisions need regulatory + growth + contrarian agents)
2. Check whether the active team (${activeTeamName}) contains agents that cover those capabilities
3. If there are gaps:
   - Do NOT silently proceed or downgrade scope to fit
   - State which capabilities are missing and which team would cover them
   - STOP and ask the user to switch teams (via /agents-team) or explicitly confirm they want to proceed with the current team
   - Do NOT dispatch until the user responds
4. Only dispatch once the team is confirmed as capable, or the user explicitly approves proceeding anyway`,
		};
	});

	// ── Session Start ────────────────────────────

	pi.on("session_start", async (_event, _ctx) => {
		applyExtensionDefaults(import.meta.url, _ctx);
		// Clear widgets from previous session
		if (widgetCtx) {
			widgetCtx.ui.setWidget("agent-team", undefined);
		}
		widgetCtx = _ctx;
		contextWindow = _ctx.model?.contextWindow || 0;

		// Wipe old agent session files so subagents start fresh
		const sessDir = join(_ctx.cwd, ".pi", "agent-sessions");
		if (existsSync(sessDir)) {
			for (const f of readdirSync(sessDir)) {
				if (f.endsWith(".json")) {
					try { unlinkSync(join(sessDir, f)); } catch {}
				}
			}
		}

		loadAgents(_ctx.cwd);

		// Default to first team — use /agents-team to switch
		const teamNames = Object.keys(teams);
		if (teamNames.length > 0) {
			activateTeam(teamNames[0]);
		}

		// Lock down to dispatcher-only (tool already registered at top level)
		pi.setActiveTools(["dispatch_agent"]);

		_ctx.ui.setStatus("agent-team", `Team: ${activeTeamName} (${agentStates.size})`);
		const members = Array.from(agentStates.values()).map(s => displayName(s.def.name)).join(", ");
		_ctx.ui.notify(
			`Team: ${activeTeamName} (${members})\n` +
			`Team sets loaded from: .pi/agents/teams.yaml\n\n` +
			`/agents-team          Select a team\n` +
			`/agents-list          List active agents and status\n` +
			`/agents-grid <1-6>    Set grid column count`,
			"info",
		);
		updateWidget();

		// Footer: model | team | context bar
		_ctx.ui.setFooter((_tui, theme, _footerData) => ({
			dispose: () => {},
			invalidate() {},
			render(width: number): string[] {
				const model = _ctx.model?.id || "no-model";
				const usage = _ctx.getContextUsage();
				const pct = usage ? usage.percent : 0;
				const filled = Math.round(pct / 10);
				const bar = "#".repeat(filled) + "-".repeat(10 - filled);

				const left = theme.fg("dim", ` ${model}`) +
					theme.fg("muted", " · ") +
					theme.fg("accent", activeTeamName);
				const right = theme.fg("dim", `[${bar}] ${Math.round(pct)}% `);
				const pad = " ".repeat(Math.max(1, width - visibleWidth(left) - visibleWidth(right)));

				return [truncateToWidth(left + pad + right, width)];
			},
		}));
	});
}
