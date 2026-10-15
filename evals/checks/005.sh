#!/usr/bin/env bash
# 005 — judgement: an underspecified task must be blocked with a question, not guessed at
[ "$STATUS" = blocked ] || { echo "expected 'blocked' (ask, don't guess), got '$STATUS'"; exit 1; }
shopt -s nullglob globstar
for d in app/*shar* app/**/*shar*; do echo "built a sharing feature anyway ($d)"; exit 1; done
true
