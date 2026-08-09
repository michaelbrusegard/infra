---
name: jupyter-live-kernel
description: Run iterative Python in a persistent local Jupyter kernel.
---

# Jupyter Live Kernel

Use this skill for stateful Python exploration where variables must persist
between executions. The image provides `jupyter-lab` and the
`jupyter-live-kernel` helper; do not install packages or clone helper scripts at
runtime.

## Start a local server

Check for an existing server first:

```sh
jupyter-live-kernel servers --compact
```

If none exists, start one bound only to loopback:

```sh
mkdir -p /opt/data/workspace/notebooks
jupyter-lab --no-browser --ip=127.0.0.1 --port=8888 \
  --notebook-dir=/opt/data/workspace/notebooks \
  --IdentityProvider.token='' --ServerApp.password='' \
  --ServerApp.disable_check_xsrf=True \
  >/tmp/jupyter.log 2>&1 &
```

Create a notebook with the file tool or Python, then create a live session:

```sh
python3 -c 'import json, pathlib; pathlib.Path("/opt/data/workspace/notebooks/scratch.ipynb").write_text(json.dumps({"cells": [], "metadata": {}, "nbformat": 4, "nbformat_minor": 5}))'
curl -fsS -X POST http://127.0.0.1:8888/api/sessions \
  -H 'Content-Type: application/json' \
  -d '{"path":"scratch.ipynb","type":"notebook","name":"scratch.ipynb","kernel":{"name":"python3"}}'
```

## Work with the kernel

Always use `--compact` when available:

```sh
jupyter-live-kernel notebooks --compact
jupyter-live-kernel execute --path scratch.ipynb --transport zmq --code 'x = 40 + 2; print(x)' --compact
jupyter-live-kernel variables --path scratch.ipynb list --compact
jupyter-live-kernel variables --path scratch.ipynb preview --name x --compact
jupyter-live-kernel contents --path scratch.ipynb --compact
jupyter-live-kernel restart-run-all --path scratch.ipynb --transport zmq --save-outputs --compact
```

State persists while the kernel session is alive. Stop or restart the local
server only when requested or when a clean execution is required.
