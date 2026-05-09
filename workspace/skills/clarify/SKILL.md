---
name: clarify
description: Use BEFORE acting on a request when (a) the request is vague — short, missing deadline/audience/constraints, or has pronouns without antecedent, OR (b) multiple valid interpretations exist, OR (c) the action would be irreversible or affect external parties. Skips when request is already specific, user has explicitly said "just do it", or action is reversible and bounded. Forces a single clarification turn that surfaces interpretation + asks only the load-bearing gaps.
allowed-tools: Read
---

# /clarify skill

Vague requests + first-plausible-interpretation = bad output. The fix is one disciplined clarification turn before commitment. Asking 20 questions is also a failure mode — pick the 1-3 gaps that actually shape what you'd do.

## The framework

Five context dimensions, ranked by load-bearing:

1. **Outcome** — what does "done" look like? Vague verbs ("fix", "improve", "help with", "handle") usually flag this gap.
2. **Audience** — who consumes the output? Determines tone, depth, format.
3. **Constraints** — deadline, format, must-include, must-avoid.
4. **Context** — relevant prior conversations, vault notes, decisions. Often already in memory; check first.
5. **Stakes** — reversible? Public? Affects external parties?

## Decision rule

Compute which dimensions are missing. Ask only about gaps that actually shape the answer:

| Situation | Action |
|---|---|
| Single-step, reversible, fast | Just do it. Surface assumption inline if non-obvious. |
| Multi-step or shaped output | Ask 1–2 questions covering the highest-leverage gaps. |
| Irreversible or external action | Confirm 2–3 dimensions before acting. Action gravity is not optional. |

## Output shape

Always lead with the agent's interpretation, then ask:

> I read this as: [one-sentence interpretation].
> Two things I want to confirm:
> 1. [highest-leverage gap as a specific question]
> 2. [second-highest gap]

Then wait. Do not act until the user responds.

## Triggers

- Request < 15 words AND no deadline/audience/constraint mentioned
- Vague verbs: "help with", "do", "fix", "improve", "handle", "deal with", "look at"
- Pronouns without antecedent: "it", "that", "the thing", "this"
- Mentioned external party without specifying recipient or message
- Action that's irreversible or affects others, regardless of how specific the request seems

## Anti-triggers (skip — just do the work)

- Specific verb + specific object + at least one constraint already present
- User has explicitly said "just go", "ship it", "no more questions", "you decide"
- Action is local, reversible, fast (reading a file, calculating, summarizing what's in vault)
- Continuation of an already-clarified thread (don't re-ask within the same task)

## Examples

**Trigger:** "help me with the email"
→ "I read this as: drafting an outbound email. Two things to confirm: (1) Who's the recipient or audience? (2) What's the outcome — info update, asking for a decision, or something else?"

**Trigger:** "fix the dashboard"
→ "Several interpretations are plausible. The most recent issue we discussed was the Q2 metrics regression on Tuesday — is that the one? If different, which dashboard?"

**Trigger:** "send Ricky a quick note"
→ "I read this as: outbound message to Ricky on his usual channel (Telegram, per USER.md). One thing to confirm before drafting: what's the message about — checking in, asking for something, or follow-up on a thread?"

**Anti-trigger:** "what's my next task in Q2 update project?"
→ Just answer. Specific verb, specific object, no ambiguity.

**Anti-trigger:** "draft Q2 investor update, due Friday 5pm, tone matches Q1 update in vault"
→ Just draft. Outcome + deadline + tone constraint all present.

## Loop awareness

If the user is still vague after one round of clarification, choose one:
- **(a) They don't know yet** → "Let me make a v0 draft, you react." Ship something concrete; iterate from feedback.
- **(b) The task isn't well-defined enough to do** → say so explicitly. Propose breaking it into smaller pieces, or naming what would need to be true for it to be doable.

Don't iterate clarification turns more than twice — that's a sign the *task* needs to change, not the *questions*.

## What to NEVER do

- Ask all five dimensions in one turn (that's a survey, not clarification)
- Ask meta-questions ("what do you really want?", "tell me more about your vision") — these read as offloading the work
- Hold up reversible single-step work for clarification — just do it and surface the assumption
- Pretend to clarify while internally already deciding (verification theater)
- Use clarification to delay something that could be tried in a v0 draft

## Boundary with action gravity

Clarify is the front-end. Action gravity (in SOUL.md) is the back-end. Even if a request feels clarified, irreversible actions still need explicit owner confirmation at execution time. /clarify reduces ambiguity; it does not transfer authority.
