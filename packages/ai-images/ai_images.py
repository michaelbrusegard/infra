"""Image generation through the NetBird AI gateway, as a CLI or MCP server."""

import argparse
import base64
import binascii
import json
import sys
from pathlib import Path
from typing import Literal
from urllib.error import HTTPError
from urllib.request import HTTPRedirectHandler, Request, build_opener


GATEWAY = "https://ai.asgard.michaelbrusegard.com/v1"
DEFAULT_MODEL = "gpt-image-2.5-sunburst"
MODELS = (DEFAULT_MODEL, "gpt-image-2.5-flare", "gpt-image-2")
# NetBird recovers routing metadata from requests up to 32 MiB. Leave room
# for the prompt and base64 expansion instead of failing after a long upload.
MAX_REQUEST_BYTES = 30 * 1024 * 1024
MAX_RESPONSE_BYTES = 64 * 1024 * 1024
Quality = Literal["low", "medium", "high", "xhigh", "max", "auto"]
Model = Literal["gpt-image-2.5-sunburst", "gpt-image-2.5-flare", "gpt-image-2"]


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("The AI gateway redirected the request; check its routing")


def image_type(data):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "image/webp"
    raise ValueError("Expected a PNG, JPEG, or WebP image")


def image_url(filename):
    path = Path(filename).expanduser()
    if not path.is_absolute():
        raise ValueError("Reference image paths must be absolute")
    with path.open("rb") as source:
        data = source.read(MAX_REQUEST_BYTES + 1)
    if len(data) > MAX_REQUEST_BYTES:
        raise ValueError(f"Reference image is too large: {path.name}")
    return f"data:{image_type(data)};base64," + base64.b64encode(data).decode("ascii")


def request_image(prompt, output_path, reference_images=None, *, model=DEFAULT_MODEL,
                  size="3840x2160", quality="high", opener=None):
    """Generate once, or edit using ordered local references, saving a new PNG."""
    if not prompt.strip():
        raise ValueError("A prompt is required")
    if model not in MODELS:
        raise ValueError(f"Unsupported image model: {model}")
    if quality not in ("low", "medium", "high", "xhigh", "max", "auto"):
        raise ValueError("Unsupported quality")
    if model == "gpt-image-2" and quality in ("xhigh", "max"):
        raise ValueError("Image 2 supports low, medium, high, or auto quality")
    if size != "auto":
        try:
            width, height = map(int, size.split("x"))
        except ValueError:
            raise ValueError("Size must be WIDTHxHEIGHT or auto") from None
        if (min(width, height) <= 0 or max(width, height) > 3840
                or width % 16 or height % 16
                or not 655360 <= width * height <= 8294400
                or max(width, height) > 3 * min(width, height)):
            raise ValueError("Unsupported dimensions for the image model")
    target = Path(output_path).expanduser()
    if not target.is_absolute() or target.suffix.lower() != ".png":
        raise ValueError("Output must be an absolute path ending in .png")
    if target.exists():
        raise ValueError("Output already exists; choose a new filename")
    references = reference_images or []
    if len(references) > 8:
        raise ValueError("Use at most eight reference images")
    # Put model first so the gateway can recover routing fields before images.
    payload = {"model": model, "prompt": prompt, "size": size,
               "quality": quality, "output_format": "png", "n": 1}
    endpoint = "/images/generations"
    if references:
        endpoint = "/images/edits"
        payload["images"] = [{"image_url": image_url(p)} for p in references]
    body = json.dumps(payload).encode()
    if len(body) > MAX_REQUEST_BYTES:
        raise ValueError("Request exceeds 30 MiB; resize the reference images")
    request = Request(GATEWAY + endpoint, data=body, headers={
        "Content-Type": "application/json",
        # NetBird authenticates the device; this is not an OpenAI API key.
        "Authorization": "Bearer netbird",
    })
    try:
        with (opener or build_opener(NoRedirect())).open(request, timeout=600) as response:
            raw = response.read(MAX_RESPONSE_BYTES + 1)
    except HTTPError as error:
        with error:
            message = error.read(4096).decode("utf-8", errors="replace")
        raise RuntimeError(f"AI gateway returned HTTP {error.code}: {message}") from None
    if len(raw) > MAX_RESPONSE_BYTES:
        raise ValueError("Image response exceeds 64 MiB")
    result = json.loads(raw)
    try:
        data = base64.b64decode(result["data"][0]["b64_json"], validate=True)
    except (KeyError, IndexError, TypeError, binascii.Error):
        raise ValueError("The gateway did not return a base64 image") from None
    if image_type(data) != "image/png":
        raise ValueError("The gateway returned a different format than the requested PNG")
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("xb") as output:
        output.write(data)
    return {"path": str(target), "model": model, "size": size, "quality": quality,
            "reference_images": len(references), "bytes": len(data)}


def serve():
    from mcp.server.fastmcp import FastMCP

    server = FastMCP("Asgard images")

    @server.tool()
    def generate_image(prompt: str, output_path: str, model: Model = DEFAULT_MODEL,
                       size: str = "3840x2160", quality: Quality = "high") -> dict:
        """Generate one PNG through the shared AI gateway. No personal API key is needed.

        Saves to a new absolute output_path. Uses the gateway's existing provider
        account and NetBird model policy. Use edit_image for local image references.
        """
        return request_image(prompt, output_path, model=model, size=size, quality=quality)

    @server.tool()
    def edit_image(prompt: str, reference_images: list[str], output_path: str,
                   model: Model = DEFAULT_MODEL, size: str = "3840x2160",
                   quality: Quality = "high") -> dict:
        """Edit images or transfer style using ordered absolute local image paths.

        Identify each image's role in the prompt, e.g. image 1 is the edit target
        and image 2 is the style reference. Preserve stated invariants. Saves a
        new PNG without replacing originals. Inspect the saved file afterward.
        """
        if not reference_images:
            raise ValueError("At least one reference image is required")
        return request_image(prompt, output_path, reference_images,
                             model=model, size=size, quality=quality)

    server.run(transport="stdio")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("serve", help="Run the MCP server over stdio")
    generate = commands.add_parser("generate", help="Generate or edit a PNG")
    generate.add_argument("--prompt", required=True)
    generate.add_argument("--output", required=True)
    generate.add_argument("--reference", action="append", default=[])
    generate.add_argument("--model", choices=MODELS, default=DEFAULT_MODEL)
    generate.add_argument("--size", default="3840x2160")
    generate.add_argument("--quality", default="high")
    args = parser.parse_args()
    if args.command == "serve":
        serve()
    else:
        print(json.dumps(request_image(args.prompt, args.output, args.reference,
                                      model=args.model, size=args.size, quality=args.quality)))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
