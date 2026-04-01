---
name: delegation-contracts
description: "Guide Kai to create Subagent Contracts that specify exactly which skills/tools each subagent should load. Kai analyzes and decides, subagents execute."
---

## Purpose

Ensure every specialist receives clear, bounded instructions that:
1. Prevent scope creep and autonomous decisions
2. **Specify exactly which skills to load** (Kai decides based on task analysis)
3. **Specify exactly which tools to use** (Kai analyzes and assigns)

---

## Core Principle: Kai Decides, Subagents Execute

| Kai Does (Orchestrator) | Subagent Does (Executor) |
|-------------------------|--------------------------|
| Analyze task requirements | Execute as specified |
| Determine which skills needed | Load exactly those skills |
| Assign tools to subagent | Use only assigned tools |
| Map skills to subtasks | Apply skills as directed |
| Decide patterns to apply | Implement patterns as specified |

**Kai is the brain — analyzes, plans, assigns**
**Subagents are hands — execute exactly as specified**

---

## Contract Structure

Every specialist MUST receive:

```json
{
  "contract": {
    "task": {
      "description": "what to accomplish",
      "files": ["exact/file/paths (if applicable)"]
    },
    "mode": "implement | test | review | validate | design | research",
    "boundary": {
      "explicitly_out_of_scope": ["what not to touch"],
      "limitations": ["constraints"]
    },
    "skills_to_load": ["EXPLICIT list of skills Kai determined"],
    "skills_location": "where to find these skills",
    "standards_to_read": ["which context files to reference"],
    "input_context": {
      "research_findings": "summary from Researcher",
      "user_requirements": "specifics",
      "technical_constraints": "limitations"
    },
    "expected_output": {
      "format": "structured report",
      "deliverables": ["file/paths"],
      "success_criteria": ["checklist"]
    },
    "reporting": {
      "to": "Kai only",
      "format": "see Report Format below",
      "no_delegation": true
    }
  }
}
```

---

## Kai's Skill/TooL Selection Process

### Step 1: Analyze Task Requirements

```
Task: Implement user authentication
Requirements:
- Input validation needed
- API calls with potential failures
- Rate limiting consideration

Skills needed:
- bounded-execution (scope discipline) ← REQUIRED
- input-validation (validate inputs) ← REQUIRED
- retry-mechanism (API resilience) ← CONDITIONAL
```

### Step 2: Map Skills to Subagent

Based on discovered available skills, assign to subagent:

```
Implementer:
  skills_to_load:
    - bounded-execution
    - input-validation
    - retry-mechanism (if available, otherwise skip)
  
  NOTE: If any specified skill doesn't exist, Kai must:
  1. Note it in contract
  2. Adjust task approach if critical skill missing
```

### Step 3: Specify in Contract

```json
{
  "task": {
    "description": "Implement login API endpoint",
    "files": ["src/api/auth.js"]
  },
  "mode": "implement",
  "skills_to_load": [
    "bounded-execution",
    "input-validation",
    "retry-mechanism"
  ],
  "skills_location": "skills/implementer/patterns/",
  "standards_to_read": [
    "context/standards/code-quality.md"
  ],
  "boundary": {
    "explicitly_out_of_scope": ["Database schema", "Frontend"]
  }
}
```

---

## Skill Assignment by Subagent Type

### Implementer
```json
{
  "skills_to_load": [
    "bounded-execution",
    "input-validation"
  ],
  "additional_skills": [
    "retry-mechanism (if API calls)",
    "circuit-breaker (if external services)",
    "rate-limiting (if API constraints)"
  ]
}
```

### Auditor
```json
{
  "skills_to_load": [
    "code-review"
  ],
  "standards_to_read": [
    "context/standards/security.md",
    "context/standards/code-quality.md"
  ]
}
```

### TestAuthor
```json
{
  "skills_to_load": [
    "test-driven-development"
  ],
  "standards_to_read": [
    "context/standards/testing.md"
  ]
}
```

---

## Environment Discovery Integration

### Before Creating Contracts

Kai must have completed Team Discovery and Environment Discovery to know:
1. What subagents exist and their roles
2. What skills exist in this environment
3. What skills are missing
4. Where skills are located

### Contract Includes

```
Contract to Implementer:

Skills to Load (Kai determined based on task):
✅ bounded-execution (skills/implementer/)
✅ input-validation (skills/implementer/patterns/)
✅ retry-mechanism (skills/implementer/patterns/)

⚠️ NOTE: circuit-breaker was specified but NOT FOUND in environment

Standards to Read:
- context/standards/code-quality.md
```

---

## Validation Checklist

Before delegating, verify:

- [ ] Task description is clear and specific
- [ ] Scope is explicit (exact files/functions)
- [ ] Boundary is clear (what is NOT included)
- [ ] Skills_to_load is EXPLICITLY specified
- [ ] Each skill exists in discovered environment (or noted as missing)
- [ ] Skills location is indicated
- [ ] Standards_to_read is specified
- [ ] Output format is defined
- [ ] No delegation allowed flag is set
- [ ] Reporting target is Kai only

---

## Anti-Patterns to Avoid

**❌ Bad:** "Explore skills and determine which to use"
**✅ Good:** "Load these specific skills: bounded-execution, input-validation"

**❌ Bad:** "Read any relevant standards"
**✅ Good:** "Read these files: context/standards/code-quality.md"

**❌ Bad:** "Use appropriate patterns"
**✅ Good:** "Apply input-validation pattern for this function"

---

## Kai's Decision Matrix

| Task Type | Always Required | Conditionally Add |
|-----------|-----------------|-------------------|
| Implement | bounded-execution | input-validation (inputs), retry-mechanism (API), circuit-breaker (external services), rate-limiting (API) |
| Review | code-review | security.md (security focus) |
| Test | test-driven-development | (none) |
| Research | context-discovery | (varies) |
| Design | frontend-design | (varies) |

---

## Output Format

```
Contract prepared for delegation to {specialist}.

Task: {description}
Scope: {files}
Boundary: {out of scope}

Skills TO LOAD (as determined by Kai):
✅ skill-name-1 (location)
✅ skill-name-2 (location)
⚠️ skill-name-3: NOT FOUND - will proceed without

Standards TO READ:
- context/standards/file.md

Expected Output: {format}
Reporting: Kai only

Ready for delegation.
```
