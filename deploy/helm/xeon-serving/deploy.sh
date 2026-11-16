#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

RELEASE=qwen3-30b-a3b-xeon
NAMESPACE=mortgage-ai
WAIT_TIMEOUT=${WAIT_TIMEOUT:-60m}

usage() {
    echo "Usage: $0 [--remove]" >&2
    echo "  (no args)  Deploy or upgrade the chart." >&2
    echo "  --remove   Uninstall the release (the namespace is kept)." >&2
}

if [[ $# -gt 1 ]]; then
    usage
    exit 1
fi

if [[ $# -eq 1 ]]; then
    case "$1" in
        --remove)
            if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
                helm uninstall "$RELEASE" -n "$NAMESPACE"
            else
                echo "Release $RELEASE not found in namespace $NAMESPACE; skipping uninstall."
            fi
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
fi

# HF_TOKEN is optional: Qwen/Qwen3-30B-A3B is not gated. Set it in .env for
# gated or private models, or to avoid Hugging Face rate limits.
HF_TOKEN=""
if [[ -f .env ]] && grep -Eq '^[[:space:]]*(export[[:space:]]+)?HF_TOKEN=' .env; then
    source <(grep -E '^[[:space:]]*(export[[:space:]]+)?HF_TOKEN=' .env)
fi

umask 077
token_file=$(mktemp)
trap 'rm -f "$token_file"' EXIT
printf '%s' "${HF_TOKEN:-}" > "$token_file"
unset HF_TOKEN

if [[ ! -s "$token_file" ]]; then
    echo "No HF_TOKEN found in .env; deploying without a Hugging Face token."
fi

helm repo add rh-ai-quickstart https://rh-ai-quickstart.github.io/ai-architecture-charts --force-update
helm dependency build .
helm upgrade --install "$RELEASE" . \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set-file "llm-service.secret.hf_token=$token_file"

# On first install, the InferenceService only becomes ready once vLLM has
# downloaded and loaded the model, which can take a long time.
echo "Waiting up to $WAIT_TIMEOUT for the qwen3-30b-a3b InferenceService to become ready..."
if ! oc -n "$NAMESPACE" wait inferenceservice/qwen3-30b-a3b --for=condition=Ready --timeout="$WAIT_TIMEOUT"; then
    echo "InferenceService qwen3-30b-a3b is not ready after $WAIT_TIMEOUT. Inspect with:" >&2
    echo "  oc -n $NAMESPACE get pods,inferenceservices" >&2
    echo "  oc -n $NAMESPACE logs -l serving.kserve.io/inferenceservice=qwen3-30b-a3b --all-containers --tail=100" >&2
    exit 1
fi
echo "InferenceService qwen3-30b-a3b is ready."
