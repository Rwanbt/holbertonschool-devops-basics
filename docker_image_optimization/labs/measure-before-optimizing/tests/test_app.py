import unittest

from app import payload_for


class PayloadTests(unittest.TestCase):
    def test_health(self) -> None:
        self.assertEqual(payload_for("/health"), (200, {"service": "image-lab", "status": "ok"}))

    def test_missing(self) -> None:
        self.assertEqual(payload_for("/missing"), (404, {"error": "not found"}))


if __name__ == "__main__":
    unittest.main()
