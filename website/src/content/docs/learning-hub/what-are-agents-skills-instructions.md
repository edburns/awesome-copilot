---
title: 'What are Agents, Skills, and Instructions'
description: 'Understand the primary customization primitives that extend GitHub Copilot for specific workflows.'
authors:
  - GitHub Copilot Learning Hub Team
lastUpdated: 2026-07-28
estimatedReadingTime: '7 minutes'
prev: false
---

Building great experiences with GitHub Copilot starts with understanding the core primitives that shape how Copilot behaves in different contexts. This article clarifies what each artifact does, how it is packaged inside this repository, and when to use it.

## Agents

Agents are configuration files (`*.agent.md`) that describe:

- The tasks they specialize in (for example, "Terraform Expert" or "LaunchDarkly Flag Manager").
- Which tools or MCP servers they can invoke.
- Optional instructions that guide the conversation style or guardrails.

When you assign an issue to Copilot or open the **Agents** panel in VS Code, these configurations let you swap in a specialized assistant. Each agent in this repo lives under `agents/` and includes metadata about the tools it depends on.

In products that support delegation, a primary agent can also launch temporary subagents for focused work such as planning, research, or review. See [Agents and Subagents](../agents-and-subagents/) for the coordination model.

### When to reach for an agent

- You have a recurring workflow that benefits from deep tooling integrations.
- You want Copilot to proactively execute commands or fetch context via MCP.
- You need persona-level guardrails that persist throughout a coding session.
- You want a coordinator that can delegate narrower work to subagents.

## Skills

Skills are self-contained folders that package reusable capabilities for GitHub Copilot. Each skill lives in its own directory and contains a `SKILL.md` file along with optional bundled assets such as reference documents, templates, and scripts.

A `SKILL.md` defines:

- A **name** (used as a `/command` in VS Code Chat and for agent discovery).
- A **description** that tells agents and users when the skill is relevant.
- Detailed instructions for how the skill should be executed.
- References to any bundled assets the skill needs.

Skills follow the open [Agent Skills specification](https://agentskills.io/home), making them portable across coding agent systems beyond GitHub Copilot.

### Why skills over prompts

Skills replace the earlier prompt file (`*.prompt.md`) pattern and offer several advantages:

- **Agent discovery**: Skills include extended frontmatter that lets agents find and invoke them automatically—prompts could only be triggered manually via a slash command.
- **Richer context**: Skills can bundle reference files, scripts, templates, and other assets alongside their instructions, giving the AI much more to work with.
- **Cross-platform portability**: The Agent Skills specification is supported across multiple coding agent systems, so your investment travels with you.
- **Slash command support**: Like prompts, skills can still be invoked via `/command` in VS Code Chat.

### When to reach for a skill

- You want to standardize how Copilot responds to a recurring task.
- You need bundled resources (templates, schemas, scripts) to complete the task.
- You want agents to discover and invoke the capability automatically.
- You prefer to drive the conversation, but with guardrails and rich context.

## Instructions

Instructions (`*.instructions.md`) provide background context that Copilot reads whenever it works on matching files. They often contain:

- Coding standards or style guides (naming conventions, testing strategy).
- Framework-specific hints (Angular best practices, .NET analyzers to suppress).
- Repository-specific rules ("never commit secrets", "feature flags must live in `flags/`").

Instructions sit under `instructions/` and can be scoped globally, per language, or per directory using glob patterns. They help Copilot align with your engineering playbook automatically.

### When to reach for instructions

- You need persistent guidance that applies across many sessions.
- You are codifying architecture decisions or compliance requirements.
- You want Copilot to understand patterns without manually pasting context.

## How the artifacts work together

Think of these artifacts as complementary layers:

1. **Instructions** lay the groundwork with long-lived guardrails.
2. **Skills** let you trigger rich, reusable workflows on demand—and let agents discover those workflows automatically.
3. **Agents** bring the most opinionated behavior, bundling tools and instructions into a single persona.

By combining all three, teams can achieve:

- Consistent onboarding for new developers.
- Repeatable operations tasks with reduced context switching.
- Tailored experiences for specialized domains (security, infrastructure, data science, etc.).

## Beyond the Core Three: The Full Customization Ecosystem

Agents, Skills, and Instructions are the foundation, but GitHub Copilot's customization ecosystem has grown to include additional primitives for more powerful automation and integration:

### Hooks

**Hooks** are shell scripts that run automatically at key lifecycle events during a Copilot session — when a session starts, when a prompt is submitted, or before and after a tool is used. Unlike Skills and Agents (which guide the AI), Hooks run outside the model and provide deterministic automation:

- Format code after every file edit
- Block prompts that match sensitive patterns
- Log agent actions for compliance auditing
- Inject dynamic context into model prompts

Hooks are defined in JSON files in `.github/hooks/` and are ideal for **deterministic guardrails** that must happen reliably regardless of the AI's reasoning. See [Automating with Hooks](../automating-with-hooks/) for full details.

### Plugins

**Plugins** are installable packages that bundle Agents, Skills, Hooks, and MCP server configurations into a single unit. Instead of manually copying files into each project, a plugin lets you:

- Install a curated set of capabilities with one command: `copilot plugin install my-plugin@awesome-copilot`
- Share a consistent toolkit across your whole team
- Bundle complex MCP server configurations that would otherwise require manual setup

Plugins are discoverable through **marketplaces** (including the `awesome-copilot` marketplace that's built in by default). See [Installing and Using Plugins](../installing-and-using-plugins/) for details.

### Canvas Extensions

**Canvas Extensions** are interactive surfaces that render rich outputs — plans, diffs, browser previews, or custom data visualizations — inside the Copilot app. Where chat threads give you text, canvases give you a collaborative workspace where you and agents can view, edit, and iterate on actual work artifacts. See [Working with Canvas Extensions](../working-with-canvas-extensions/) for details.

### Agentic Workflows

**Agentic Workflows** are AI-powered repository automations that run Copilot coding agents in GitHub Actions. Written as markdown files with natural language instructions, they let you automate scheduled tasks, event-driven triage, and compliance checks — without writing YAML. See [Agentic Workflows](../agentic-workflows/) for details.

## Next steps

- Explore the rest of the **Fundamentals** track for deeper dives on chat modes, collections, and MCP servers.
- Browse the [Awesome Agents](../../agents/), [Skills](../../skills/), and [Instructions](../../instructions/) directories for inspiration.
- Check the [Hooks](../../hooks/) and [Plugins](../../plugins/) directories for ready-to-use automation and installable toolkits.
- Try generating your own artifacts, then add them to the repo to keep the Learning Hub evolving.

---
