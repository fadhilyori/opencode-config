# Agent System Guide

System-wide rules for all agents.

---

## Token Economy
- Optimize token efficiency — compact prompts, no redundancy
- One tool call > multiple manual reads

## Research Before Action
- 80% confidence threshold before acting
- Never assume external library behavior

## Lazy Context Loading
- Read project context first
- Load only relevant standards
- Don't preload everything

## Coordination
- Sessions: `.tmp/sessions/{id}/`
- Tasks: `.tmp/tasks/{feature}/`
- External: `.tmp/external/{package}/`
