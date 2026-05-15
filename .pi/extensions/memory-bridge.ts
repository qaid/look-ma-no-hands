/**
 * memory-bridge -- Shared memory layer for Look Ma No Hands
 *
 * Reads project knowledge from memory/ and expertise/ directories,
 * injecting both into the system prompt so all agents start with full context.
 *
 * Memory sources (in injection order):
 *   1. memory/last-session.md     -- session handoff state
 *   2. memory/MEMORY.md           -- session log index
 *   3. .claude/learnings.md       -- accumulated project learnings (if exists)
 *   4. expertise/*.md             -- agent expertise files
 *
 * Usage: pi -e extensions/memory-bridge.ts
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, basename } from "node:path";

interface LoadedFile {
  name: string;
  content: string;
}

function loadMarkdownDir(dir: string): LoadedFile[] {
  if (!existsSync(dir)) return [];
  try {
    return readdirSync(dir)
      .filter((f) => f.endsWith(".md"))
      .map((f) => ({
        name: basename(f, ".md"),
        content: readFileSync(join(dir, f), "utf-8"),
      }));
  } catch {
    return [];
  }
}

function loadFile(path: string): string {
  try {
    return readFileSync(path, "utf-8");
  } catch {
    return "";
  }
}

export default function (pi: ExtensionAPI) {
  let lastSession = "";
  let memoryIndex = "";
  let learnings = "";
  let expertiseFiles: LoadedFile[] = [];

  pi.on("session_start", async (_event, ctx) => {
    const root = ctx.cwd;

    // 1. Load session handoff
    lastSession = loadFile(join(root, "memory", "last-session.md"));

    // 2. Load memory index
    memoryIndex = loadFile(join(root, "memory", "MEMORY.md"));

    // 3. Load .claude/learnings.md (optional project learnings)
    learnings = loadFile(join(root, ".claude", "learnings.md"));

    // 4. Load expertise files
    expertiseFiles = loadMarkdownDir(join(root, "expertise"));

    const counts: string[] = [];
    if (lastSession) counts.push("last-session handoff");
    if (memoryIndex) counts.push("memory index");
    if (learnings) counts.push("project learnings");
    if (expertiseFiles.length) counts.push(`${expertiseFiles.length} expertise file(s)`);

    ctx.ui.notify(
      `Memory Bridge: loaded ${counts.join(", ") || "nothing"}`,
      "info"
    );
  });

  pi.on("before_agent_start", async (event) => {
    const sections: string[] = [];

    // Session state first (most immediately relevant)
    if (lastSession) {
      sections.push(
        `# Session Handoff (from memory/last-session.md)\n\n${lastSession}`
      );
    }

    // Memory index
    if (memoryIndex) {
      sections.push(
        `# Memory Index (from memory/MEMORY.md)\n\n${memoryIndex}`
      );
    }

    // Project learnings
    if (learnings) {
      sections.push(
        `# Project Learnings (from .claude/learnings.md)\n\n${learnings}`
      );
    }

    // Agent expertise files
    if (expertiseFiles.length) {
      sections.push(`# Agent Expertise Files (from expertise/)\n`);
      for (const file of expertiseFiles) {
        sections.push(`## ${file.name}\n\n${file.content}`);
      }
    }

    if (sections.length) {
      return {
        systemPrompt: event.systemPrompt + "\n\n" + sections.join("\n\n"),
      };
    }
  });
}
