#!/usr/bin/env python3
"""Network failures must retry/fail over without accepting corrupt ZIP ranges."""
import io
import unittest
import urllib.error
from unittest.mock import patch
from build_web_skin_probe import RangedArchive, URLS


class Response(io.BytesIO):
    def __init__(self, content=b"", status=200, headers=None):
        super().__init__(content)
        self.status = status
        self.headers = headers or {"Content-Length": "100"}


def unavailable():
    return urllib.error.HTTPError(URLS[0], 503, "Unavailable", {}, None)


class DownloadTests(unittest.TestCase):
    @patch("build_web_skin_probe.time.sleep")
    @patch("build_web_skin_probe.urllib.request.urlopen")
    def test_head_retries_and_uses_second_source(self, request, sleep):
        request.side_effect = [unavailable(), unavailable(), unavailable(), Response()]
        archive = RangedArchive()
        self.assertEqual(archive.size, 100)
        self.assertEqual(request.call_args_list[-1].args[0].full_url, URLS[1])
        self.assertEqual(sleep.call_count, 2)

    @patch("build_web_skin_probe.time.sleep")
    @patch("build_web_skin_probe.urllib.request.urlopen")
    def test_get_retries_exact_range_without_advancing_on_failure(self, request, sleep):
        request.side_effect = [Response(), unavailable(), Response(b"abc", 206, {"Content-Range": "bytes 10-12/100"})]
        archive = RangedArchive()
        archive.seek(10)
        self.assertEqual(archive.read(3), b"abc")
        self.assertEqual(archive.tell(), 13)
        self.assertEqual(request.call_args_list[-1].args[0].get_header("Range"), "bytes=10-12")
        self.assertEqual(sleep.call_count, 1)

    @patch("build_web_skin_probe.time.sleep")
    @patch("build_web_skin_probe.urllib.request.urlopen")
    def test_ignored_range_fails_over_before_reading_full_archive(self, request, _sleep):
        ignored = Response(b"not a range")
        ignored.read = unittest.mock.Mock(side_effect=AssertionError("Must not read full TPZ"))
        request.side_effect = [Response(), ignored, Response(b"abc", 206, {"Content-Range": "bytes 0-2/100"})]
        archive = RangedArchive()
        self.assertEqual(archive.read(3), b"abc")
        self.assertEqual(request.call_args_list[-1].args[0].full_url, URLS[1])

    @patch("build_web_skin_probe.time.sleep")
    @patch("build_web_skin_probe.urllib.request.urlopen")
    def test_truncated_range_retries(self, request, _sleep):
        request.side_effect = [Response(), Response(b"a", 206, {"Content-Range": "bytes 0-2/100"}), Response(b"abc", 206, {"Content-Range": "bytes 0-2/100"})]
        self.assertEqual(RangedArchive().read(3), b"abc")

    @patch("build_web_skin_probe.time.sleep")
    @patch("build_web_skin_probe.urllib.request.urlopen")
    def test_total_failure_remains_a_failure(self, request, _sleep):
        request.side_effect = unavailable()
        with self.assertRaisesRegex(RuntimeError, "Both official"):
            RangedArchive()
        self.assertEqual(request.call_count, 6)

    @patch("build_web_skin_probe.urllib.request.urlopen", return_value=Response())
    def test_eof_does_not_request_an_invalid_range(self, request):
        archive = RangedArchive()
        archive.seek(100)
        self.assertEqual(archive.read(10), b"")
        self.assertEqual(request.call_count, 1)


if __name__ == "__main__":
    unittest.main()
