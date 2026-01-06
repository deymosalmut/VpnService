#!/usr/bin/env bash
set -euo pipefail

: "${OPENAI_API_KEY:?OPENAI_API_KEY is not set}"
echo "OPENAI_API_KEY is set (length: ${#OPENAI_API_KEY})"
