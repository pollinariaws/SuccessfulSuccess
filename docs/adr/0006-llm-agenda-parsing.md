# 6. LLM parsing of pasted agendas

Date: 2026-10-29. Status: accepted.

## Context

Agendas arrive as emails, chat messages and notes, not as form fields. The feature
"Paste an agenda" turns such text into a pre-filled meeting form; the person checks it
and presses Save.

Constraints:

- The backend Lambda runs in a VPC without a NAT gateway, so it cannot reach Bedrock.
- Every call costs money, so the endpoint must be authenticated and limited.
- The pasted text comes from outside: it may contain instructions aimed at the model.
- The account is on a reduced Bedrock quota: Claude 5.x models are not available, and
  Haiku 4.5 is reachable only through the `global.` inference profile.

## Decision

- Model: Claude Haiku 4.5 (`global.anthropic.claude-haiku-4-5-20251001-v1:0`) through
  the Bedrock Converse API. About $0.003 per parse in tests; Sonnet 4.6 gave similar
  quality at about three times the price.
- The parser is a separate Lambda function **outside the VPC**: it needs Bedrock, not
  the database, so it costs nothing while idle and needs no NAT gateway or VPC endpoint.
- The model **never writes anything**. It returns a suggestion validated against a
  schema (Pydantic). Saving goes through the existing API with its own validation.
- The suggestion is stored next to the final meeting (`ai_suggestion`, JSONB, with model
  and prompt version). The difference between suggestion and saved values is the quality
  signal.
- Time zone offsets are added by code, not by the model. Text that contains no agenda
  returns an error instead of an empty form.

## Alternatives considered

- Bedrock from the API through a VPC interface endpoint: about $7.30 a month per zone
  and always on; the parser does not need the database, so the endpoint buys nothing.
- The Claude API directly instead of Bedrock: needs an API key to store and rotate;
  Bedrock uses the function's IAM role and the AWS bill.
- A regular-expression parser: free and instant, but it handles only one layout and
  fails on the first email written differently.
- The Anthropic Messages API on Bedrock (`bedrock-mantle`): not usable here, because
  the account has no access to the models it serves.

## Consequences

- One parse costs about $0.003 and takes 1-3 seconds.
- Logged per parse: user id, model, prompt version, input and output tokens, latency,
  cost. The pasted text is not logged.
- The `global.` profile can be served from any AWS region, so pasted text may leave the
  EU. For a real product with EU customers this needs a legal decision.
- The Lambda role may call `bedrock:InvokeModel` on `*`; a narrower policy is a follow-up.
- If Bedrock is down or throttled, the user sees a message and types the agenda by hand.
  Nothing else in the app depends on it.
- Relative dates ("Friday") are still ambiguous. The screen marks every suggested field,
  so the person decides.