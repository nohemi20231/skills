import unittest

from skill_crawler.fetch import Fetcher, RobotsDisallowed
from tests.helpers import FakeWeb, redirect


class FakeTime:
    """A clock that only moves when told to, or when the code under test sleeps."""

    def __init__(self):
        self.now = 100.0
        self.sleeps = []

    def clock(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(round(seconds, 3))
        self.now += seconds


def make(pages: dict, **options):
    web = FakeWeb(pages)
    time = FakeTime()
    fetcher = Fetcher(web, clock=time.clock, sleep=time.sleep, **options)
    return fetcher, web, time


class Throttle(unittest.TestCase):
    def test_spaces_requests_to_one_host_by_the_delay(self):
        fetcher, _, time = make({"https://a.example/1": "one", "https://a.example/2": "two"}, delay=1.0)
        fetcher.get("https://a.example/1")  # robots.txt, then the page
        time.sleeps.clear()
        time.now += 0.4
        fetcher.get("https://a.example/2")
        self.assertEqual(time.sleeps, [0.6])

    def test_first_request_to_a_host_is_not_delayed_by_another_host(self):
        fetcher, _, time = make({}, delay=1.0)
        fetcher.get("https://a.example/1")
        time.sleeps.clear()
        fetcher.get("https://b.example/1")
        self.assertEqual(time.sleeps, [1.0])  # only b's own robots.txt -> page gap

    def test_host_specific_delay_replaces_the_default(self):
        fetcher, _, time = make({}, delay=1.0, host_delays={"api.example": 6.5})
        fetcher.get("https://api.example/1")
        time.sleeps.clear()
        fetcher.get("https://api.example/2")
        self.assertEqual(time.sleeps, [6.5])

    def test_no_wait_once_the_delay_has_already_passed(self):
        fetcher, _, time = make({}, delay=1.0)
        fetcher.get("https://a.example/1")
        time.sleeps.clear()
        time.now += 30
        fetcher.get("https://a.example/2")
        self.assertEqual(time.sleeps, [])


class Robots(unittest.TestCase):
    def test_disallowed_url_is_never_requested(self):
        fetcher, web, _ = make({
            "https://a.example/robots.txt": "User-agent: *\nDisallow: /private/\n",
            "https://a.example/private/list": "secret",
            "https://a.example/public/list": "open",
        })
        with self.assertRaises(RobotsDisallowed):
            fetcher.get("https://a.example/private/list")
        self.assertEqual(fetcher.get("https://a.example/public/list"), (200, b"open"))
        self.assertNotIn("https://a.example/private/list", web.urls())

    def test_rules_addressed_to_this_crawler_win_over_the_wildcard(self):
        fetcher, _, _ = make(
            {"https://a.example/robots.txt": "User-agent: skill-crawler\nDisallow: /\n\nUser-agent: *\nAllow: /\n"},
            user_agent="skill-crawler/0.1 (test)",
        )
        with self.assertRaises(RobotsDisallowed):
            fetcher.get("https://a.example/page")

    def test_robots_file_is_requested_once_per_host(self):
        fetcher, web, _ = make({"https://a.example/robots.txt": "User-agent: *\nAllow: /\n"})
        fetcher.get("https://a.example/1")
        fetcher.get("https://a.example/2")
        self.assertEqual(web.urls().count("https://a.example/robots.txt"), 1)

    def test_robots_status_decides_access_when_there_are_no_rules(self):
        cases = {404: True, 410: True, 401: False, 403: False, 503: False}
        for status, allowed in cases.items():
            with self.subTest(status=status):
                fetcher, web, _ = make({
                    "https://a.example/robots.txt": (status, ""),
                    "https://a.example/page": "ok",
                })
                if allowed:
                    self.assertEqual(fetcher.get("https://a.example/page"), (200, b"ok"))
                else:
                    with self.assertRaises(RobotsDisallowed):
                        fetcher.get("https://a.example/page")
                    self.assertNotIn("https://a.example/page", web.urls())


class Requests(unittest.TestCase):
    def test_every_request_carries_the_user_agent_and_nothing_else(self):
        fetcher, web, _ = make({}, user_agent="skill-crawler/0.1 (test)")
        fetcher.get("https://a.example/page")
        self.assertEqual(
            web.requests,
            [
                ("https://a.example/robots.txt", {"User-Agent": "skill-crawler/0.1 (test)"}),
                ("https://a.example/page", {"User-Agent": "skill-crawler/0.1 (test)"}),
            ],
        )

    def test_get_returns_the_status_of_a_failed_request(self):
        fetcher, _, _ = make({"https://a.example/gone": (410, "gone")})
        self.assertEqual(fetcher.get("https://a.example/gone"), (410, b"gone"))

    def test_get_reads_no_more_than_the_byte_limit(self):
        fetcher, _, _ = make({"https://a.example/big": "x" * 5000})
        self.assertEqual(fetcher.get("https://a.example/big", max_bytes=1000), (200, b"x" * 1000))

    def test_open_hands_back_a_stream_for_large_downloads(self):
        fetcher, _, _ = make({"https://a.example/archive": b"\x1f\x8bdata"})
        reply = fetcher.open("https://a.example/archive")
        self.assertEqual((reply.status, reply.read(2), reply.read()), (200, b"\x1f\x8b", b"data"))

    def test_only_https_urls_are_fetched(self):
        fetcher, web, _ = make({})
        for url in ("file:///etc/passwd", "ftp://a.example/x", "/etc/passwd", "http://a.example/x"):
            with self.subTest(url=url):
                with self.assertRaises(ValueError):
                    fetcher.get(url)
        self.assertEqual(web.requests, [])


class Redirects(unittest.TestCase):
    def test_follows_a_redirect_to_the_final_reply(self):
        fetcher, _, _ = make({
            "https://a.example/old": redirect("/new", status=301),
            "https://a.example/new": redirect("https://b.example/final", status=307),
            "https://b.example/final": "moved here",
        })
        self.assertEqual(fetcher.get("https://a.example/old"), (200, b"moved here"))

    def test_redirect_target_must_pass_its_own_robots_rules(self):
        fetcher, web, _ = make({
            "https://a.example/list": redirect("https://b.example/list"),
            "https://b.example/robots.txt": "User-agent: *\nDisallow: /\n",
            "https://b.example/list": "hidden",
        })
        with self.assertRaises(RobotsDisallowed):
            fetcher.get("https://a.example/list")
        self.assertNotIn("https://b.example/list", web.urls())

    def test_redirect_away_from_https_is_refused_as_a_network_error(self):
        fetcher, web, _ = make({"https://a.example/list": redirect("http://a.example/list")})
        with self.assertRaises(OSError):
            fetcher.get("https://a.example/list")
        self.assertNotIn("http://a.example/list", web.urls())

    def test_redirect_loop_ends_as_a_network_error(self):
        fetcher, web, _ = make({"https://a.example/loop": redirect("/loop")})
        with self.assertRaises(OSError):
            fetcher.get("https://a.example/loop")
        self.assertLessEqual(web.urls().count("https://a.example/loop"), 6)

    def test_redirect_status_without_a_location_is_returned_as_is(self):
        fetcher, _, _ = make({"https://a.example/odd": (302, "no location")})
        self.assertEqual(fetcher.get("https://a.example/odd"), (302, b"no location"))


if __name__ == "__main__":
    unittest.main()
