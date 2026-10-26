import base64
import json
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

import ai_images


PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a+l8AAAAASUVORK5CYII=")


class ImageClientTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.output = Path(self.directory.name) / "result.png"
        self.requests = []
        self.status = 200
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                owner.requests.append((self.path, dict(self.headers), body))
                self.send_response(owner.status)
                self.send_header("Content-Type", "application/json")
                if owner.status == 302:
                    self.send_header("Location", "https://other.example.test/")
                self.end_headers()
                response = ({"data": [{"b64_json": base64.b64encode(PNG).decode()}]}
                            if owner.status == 200 else {"error": "model not allowed"})
                self.wfile.write(json.dumps(response).encode())

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        gateway = patch.object(ai_images, "GATEWAY", f"http://127.0.0.1:{server.server_port}/v1")
        gateway.start()
        self.addCleanup(gateway.stop)

    def test_generation_uses_gateway_and_saves_returned_png(self):
        result = ai_images.request_image("Paint a beach", str(self.output))
        path, headers, body = self.requests[0]
        self.assertEqual(path, "/v1/images/generations")
        self.assertEqual(headers["Authorization"], "Bearer netbird")
        self.assertEqual(body["model"], "gpt-image-2.5-sunburst")
        self.assertEqual(body["prompt"], "Paint a beach")
        self.assertEqual(self.output.read_bytes(), PNG)
        self.assertEqual(result["path"], str(self.output))
        self.assertEqual(result["size"], "1x1")
        self.assertEqual(result["requested_size"], "3840x2160")

    def test_edit_uploads_ordered_local_references_as_json(self):
        first = self.output.with_name("target.png")
        second = self.output.with_name("style.png")
        first.write_bytes(PNG)
        second.write_bytes(PNG + b"distinct-reference")
        ai_images.request_image("Image 1 is the target; image 2 is the style",
                                str(self.output), [str(first), str(second)])
        path, headers, body = self.requests[0]
        self.assertEqual(path, "/v1/images/edits")
        self.assertEqual(headers["Content-Type"], "application/json")
        self.assertEqual(list(body)[0], "model")
        self.assertEqual([base64.b64decode(item["image_url"].split(",", 1)[1])
                          for item in body["images"]], [first.read_bytes(), second.read_bytes()])

    def test_policy_denial_preserves_status_and_creates_no_output(self):
        self.status = 403
        with self.assertRaisesRegex(RuntimeError, "HTTP 403.*model not allowed"):
            ai_images.request_image("test", str(self.output))
        self.assertFalse(self.output.exists())

    def test_redirect_is_not_followed(self):
        self.status = 302
        with self.assertRaisesRegex(ValueError, "redirected"):
            ai_images.request_image("test", str(self.output))
        self.assertFalse(self.output.exists())

    def test_existing_file_is_rejected_before_spending_quota(self):
        self.output.write_bytes(b"existing work")
        with self.assertRaisesRegex(ValueError, "already exists"):
            ai_images.request_image("test", str(self.output))
        self.assertEqual(self.requests, [])
        self.assertEqual(self.output.read_bytes(), b"existing work")

    def test_non_image_reference_is_rejected_before_upload(self):
        reference = self.output.with_name("private.txt")
        reference.write_text("not image data")
        with self.assertRaisesRegex(ValueError, "Expected a PNG"):
            ai_images.request_image("test", str(self.output), [str(reference)])
        self.assertEqual(self.requests, [])

    def test_oversized_request_is_rejected_before_upload(self):
        with patch.object(ai_images, "MAX_REQUEST_BYTES", 10):
            with self.assertRaisesRegex(ValueError, "exceeds 30 MiB"):
                ai_images.request_image("test", str(self.output))
        self.assertEqual(self.requests, [])


if __name__ == "__main__":
    unittest.main()
