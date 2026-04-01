---
name: environment-awareness
description: "Guide Kai through discovering available skills and tools, then ANALYZING and ASSIGNING to subagents. Step 0 of Kai's workflow."
---

## Purpose

Help Kai:
1. **Discover** what skills and tools are available in the current environment
2. **Analyze** task requirements to determine which skills each subagent needs
3. **Assign** explicitly which skills each subagent should load

This makes Kai portable across environments where skills and tools may vary, while still being the decision-maker.

---

## When to Use

**ALWAYS at the start of any Kai session, before Step 1 (Parse & Bound):**

```
User Input
    ↓
┌─────────────────────────────────────┐
│  STEP 0: Environment Discovery     │
│  1. Discover available resources    │
│  2. Analyze task requirements       │
│  3. Assign skills to subagents       │
└─────────────────────────────────────┘
    ↓
Step 1: Parse & Bound (with awareness)
```

---

## Phase 1: Discovery

### Step 0.1: Explore Skills Directory

Skills may exist at multiple locations. Explore all possible locations:

```
Possible skill locations:
- skills/                    # Kai's own skills
- skills/kai/               # Kai workflow skills
- skills/implementer/       # Implementation skills
- skills/implementer/patterns/  # Implementation patterns
- skills/auditor/           # Audit skills
- skills/researcher/        # Research skills
- .agents/skills/           # Additional skills (external)
- .agents/skills/*/         # More skills at root level
```

**Method**: Use `glob` with pattern `**/SKILL.md` across multiple potential root directories.

### Step 0.2: Map Available Skills

Build a map of what exists:

```
Skills Found:
├── skills/kai/
│   ├── checkpoint-handling ✓
│   ├── delegation-contracts ✓
│   ├── error-containment ✓
│   └── environment-awareness ✓
├── skills/implementer/
│   ├── bounded-execution ✓
│   └── patterns/
│       ├── input-validation ✓
│       ├── retry-mechanism ✓
│       ├── rate-limiting ✓
│       ├── circuit-breaker ✓
│       ├── parallel-execution ✓
│       └── event-coordination ✓
├── skills/auditor/
│   └── code-review ✓
├── skills/researcher/
│   └── context-discovery ✓
└── .agents/skills/
    ├── test-driven-development ✓
    └── ... (may have more)
```

### Step 0.3: Check for Missing Skills

If user or plan mentions specific skills, verify they exist:

```
Verifying referenced skills:
- bounded-execution: FOUND ✓ (skills/implementer/)
- input-validation: FOUND ✓ (skills/implementer/patterns/)
- find-skills: NOT FOUND ✗
```

---

## Phase 2: Analysis & Assignment

### Step 0.4: Analyze Tasks and Assign Skills

Based on the discovered environment, Kai analyzes each task in the plan and assigns skills:

```
Task Analysis → Skill Assignment:

IMPLEMENTER tasks:
┌─────────────────────────────────────────────────────────┐
│ Task: Implement user authentication                      │
│ Requires: Input handling, API calls                      │
│ Kai Assigns:                                             │
│   - bounded-execution (scope discipline)                 │
│   - input-validation (validate inputs)                   │
│   - retry-mechanism (API resilience)                    │
└─────────────────────────────────────────────────────────┘

AUDITOR tasks:
┌─────────────────────────────────────────────────────────┐
│ Task: Security review of auth module                     │
│ Kai Assigns:                                             │
│   - code-review (review methodology)                     │
└─────────────────────────────────────────────────────────┘

TESTAUTHOR tasks:
┌─────────────────────────────────────────────────────────┐
│ Task: Write tests for authentication                     │
│ Kai Assigns:                                             │
│   - test-driven-development (testing approach)           │
└─────────────────────────────────────────────────────────┘
```

### Skill Assignment Reference

| Task Type | Always Assign | Conditionally Add |
|-----------|--------------|------------------|
| Implement | bounded-execution | input-validation (inputs), retry-mechanism (API), circuit-breaker (services), rate-limiting (API) |
| Review | code-review | security.md focus |
| Test | test-driven-development | (varies) |
| Research | context-discovery | (varies) |

---

## Environment Awareness Output

After discovery, present the environment map:

```
## Environment Awareness

### Available Skills (by category)

**Kai Workflow Skills:**
- checkpoint-handling ✓
- delegation-contracts ✓
- error-containment ✓

**Implementation Skills:**
- bounded-execution ✓
- input-validation ✓ (patterns/)
- retry-mechanism ✓ (patterns/)
- rate-limiting ✓ (patterns/)
- circuit-breaker ✓ (patterns/)
- parallel-execution ✓ (patterns/)
- event-coordination ✓ (patterns/)

**Review Skills:**
- code-review ✓

**Research Skills:**
- context-discovery ✓

**Test Skills:**
- test-driven-development ✓ (.agents/skills/)

### Skills Not Found (Referenced but Missing)
- find-skills: Not found

### Skill Locations
- Kai workflow: `skills/kai/`
- Implementation patterns: `skills/implementer/patterns/`
- Review: `skills/auditor/`
- Test: `.agents/skills/`
- Additional: `.agents/skills/`

---

### Skill Assignment for Current Plan

| Subagent | Skills to Load | Location |
|----------|---------------|----------|
| Implementer | bounded-execution, input-validation | skills/implementer/ |
| Auditor | code-review | skills/auditor/ |
| TestAuthor | test-driven-development | .agents/skills/ |
```

---

## Why This Matters

### Without Discovery & Assignment (Bad)

```
Kai: "Implementer, explore skills and decide what to use..."
Implementer: "I found bounded-execution but not sure what's needed..."
Result: Subagent uncertainty, inconsistent skill usage
```

### With Kai's Discovery & Assignment (Good)

```
Kai: [discovers skills first]
Kai: [analyzes task, assigns skills]
Kai to Implementer: "Load bounded-execution, input-validation.
Located at skills/implementer/ and skills/implementer/patterns/"
Implementer: [loads exactly as specified]
Result: Consistent, predictable execution
```

### Key Principle

**Kai discovers to be aware, then decides to be effective.**

---

## Integration with Kai Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  STEP 0: Environment Discovery (This skill)                 │
│                                                              │
│  PHASE 1: Discovery                                          │
│  1. Explore skills directory structure                       │
│  2. Map available skills                                    │
│  3. Note missing skills                                      │
│                                                              │
│  PHASE 2: Analysis & Assignment                              │
│  4. Analyze task requirements                                │
│  5. Match tasks to skills                                    │
│  6. Verify skills exist                                      │
│  7. Create skill assignments for each subagent               │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  STEP 1-6: Continue Kai workflow                            │
│                                                              │
│  Use skill assignments when creating subagent contracts:     │
│  "Load these skills: bounded-execution, input-validation"   │
└─────────────────────────────────────────────────────────────┘
```

---

## Discovery Commands

### To explore skills:

```bash
# Explore multiple potential skill locations
glob pattern: "skills/**/SKILL.md"
glob pattern: ".agents/skills/**/SKILL.md"

# Read skill descriptions to understand capabilities
read file: "skills/kai/checkpoint-handling/SKILL.md"
```

### To build the assignment:

1. Read plan subtasks
2. For each subtask, determine required skills
3. Check if skill exists in discovered map
4. Create explicit assignment

---

## Flexibility Note

**Discovery is MANDATORY but results are ENVIRONMENT-SPECIFIC.**

- In deployment A: skills at `skills/` and `.agents/skills/`
- In deployment B: skills only at `skills/`
- In deployment C: skills directory may not exist

Kai must adapt assignments to whatever environment exists.

---

## Output Format

After running this skill:

```
Environment Awareness: COMPLETE
Skills found: {n}
Skills missing: {n}

Skill Assignments:
- Implementer: bounded-execution, input-validation
- Auditor: code-review
- TestAuthor: test-driven-development
- Researcher: context-discovery

Ready to proceed with Step 1: Parse & Bound
```

---

**Base directory for this skill**: `file:///home/fadhilyori/.config/opencode/skills/kai/environment-awareness`
