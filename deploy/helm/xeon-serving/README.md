# Deploy the LLM on Intel® Xeon®

This Helm chart wraps the `llm-service` chart from
[AI Architecture Charts](https://github.com/rh-ai-quickstart/ai-architecture-charts).
It serves `Qwen/Qwen3-30B-A3B` using the Xeon vLLM runtime through a KServe
InferenceService, exposed in-cluster through a ClusterIP Service. vLLM is
configured with a 16384-token context length, bfloat16, tensor parallelism of 2,
and automatic tool calling using the Hermes tool-call parser.

## Prerequisites

- OpenShift AI
- A supported Xeon node (Sapphire Rapids or newer) with at least 64 allocatable
  vCPUs and 128 GiB of memory available, plus disk space for the model download.
- The cluster must be able to reach Hugging Face to download the model.
  `Qwen/Qwen3-30B-A3B` is not gated, so no Hugging Face token is required. A
  token can optionally be provided for gated or private models, or to avoid
  Hugging Face rate limits.

## Install

Optionally, copy `.env.example` to the ignored `.env` file in this directory
and set a Hugging Face token (not needed for the default, non-gated model):

```bash
HF_TOKEN=hf_your_token_here
```

Deploy from this directory:

```bash
bash ./deploy.sh
```

Or, from the repository root: `make deploy-xeon-model`.

If a token is set in `.env`, the script passes it to Helm, which creates or
updates the `huggingface-secret` Kubernetes Secret used by the vLLM pod;
otherwise the Secret is created with an empty token. The token is not printed,
but Helm stores release values in the cluster; protect Helm release data and
namespace access accordingly.

After installing, the script waits for the `qwen3-30b-a3b` InferenceService to
become ready before exiting. On first install this includes the model download
and vLLM initialization, which can take considerable time; the default
60-minute timeout can be overridden with the `WAIT_TIMEOUT` environment
variable (for example `WAIT_TIMEOUT=90m bash ./deploy.sh`). Check progress and
logs with:

```bash
oc -n mortgage-ai get pods,inferenceservices,servingruntimes
oc -n mortgage-ai describe inferenceservice qwen3-30b-a3b
oc -n mortgage-ai logs -l serving.kserve.io/inferenceservice=qwen3-30b-a3b --all-containers --tail=100
```

## OpenAI-compatible API

The chart does not create an OpenShift Route; the service is only reachable
inside the cluster.

The vLLM OpenAI-compatible base URL, reachable from other pods in the cluster,
is:

```text
http://qwen3-30b-a3b-vllm.mortgage-ai.svc.cluster.local/v1
```

For example, from a pod with `curl` installed:

```bash
curl http://qwen3-30b-a3b-vllm.mortgage-ai.svc.cluster.local/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen3-30B-A3B","messages":[{"role":"user","content":"Hello!"}],"max_tokens":100}'
```

For access from a workstation (`*.svc.cluster.local` names do not resolve
outside the cluster), use a port-forward:

```bash
oc -n mortgage-ai port-forward svc/qwen3-30b-a3b-vllm 8000:80
```

and use `http://localhost:8000/v1` as the base URL. With the port-forward
running, list the served models (the `id` value is what you pass as `model` in
requests) with:

```bash
curl http://localhost:8000/v1/models
```

Example output (formatted):

```json
{
  "object": "list",
  "data": [
    {
      "id": "Qwen/Qwen3-30B-A3B",
      "object": "model",
      "created": 1794853952,
      "owned_by": "vllm",
      "root": "Qwen/Qwen3-30B-A3B",
      "parent": null,
      "max_model_len": 16384,
      "permission": ["..."]
    }
  ]
}
```

Then send a chat completion to the forwarded endpoint:

```bash
curl http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen3-30B-A3B","messages":[{"role":"user","content":"Hello!"}],"max_tokens":100}'
```

The cluster-internal service uses unauthenticated HTTP; restrict access with
network policies or add authentication and TLS before exposing it beyond a
trusted network.

## Uninstall

```bash
bash ./deploy.sh --remove
```

Or, from the repository root: `make undeploy-xeon-model`.

This uninstalls the Helm release; the namespace and anything else in it are
kept. The equivalent Helm command is:

```bash
helm uninstall qwen3-30b-a3b-xeon -n mortgage-ai
```
