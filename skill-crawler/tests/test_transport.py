import http.client
import io
import os
import ssl
import unittest

from skill_crawler.transport import KeepAliveTransport, tls_context

HELLO = b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\nX-Test: yes\r\n\r\nhello"
WORLD = b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nworld"


class _Incoming(io.BytesIO):
    """Bytes the peer sends. http.client closes its reader per response; the socket stays."""

    def close(self) -> None:
        pass


class ScriptedSocket:
    """Stands in for a connected socket: records what is sent, replays what the peer sends."""

    def __init__(self, incoming: bytes):
        self.sent = b""
        self.closed = False
        self._incoming = _Incoming(incoming)

    def sendall(self, data: bytes) -> None:
        self.sent += data

    def makefile(self, mode: str, *args):
        return self._incoming

    def close(self) -> None:
        self.closed = True


class _ScriptedConnection(http.client.HTTPConnection):
    def connect(self) -> None:
        # http.client re-dials a closed connection by itself; the transport must not rely on it.
        raise AssertionError(f"connection to {self.host} was reused after it was closed")


class ScriptedNetwork:
    """Hands out real http.client connections whose sockets replay a script each."""

    def __init__(self, *scripts: bytes):
        self._scripts = list(scripts)
        self.sockets = []
        self.dialed = []

    def connect(self, host: str, port: int | None) -> http.client.HTTPConnection:
        self.dialed.append((host, port))
        connection = _ScriptedConnection(host, port)
        connection.sock = ScriptedSocket(self._scripts.pop(0))
        self.sockets.append(connection.sock)
        return connection


def make(*scripts: bytes):
    network = ScriptedNetwork(*scripts)
    return KeepAliveTransport(connect=network.connect), network


def body_of(reply) -> bytes:
    try:
        return reply.read()
    finally:
        reply.close()


class Replies(unittest.TestCase):
    def test_returns_status_headers_and_body(self):
        transport, _ = make(HELLO)
        reply = transport("https://a.example/x", {})
        self.assertEqual((reply.status, reply.headers.get("X-Test"), body_of(reply)), (200, "yes", b"hello"))

    def test_error_status_is_a_reply_not_an_exception(self):
        transport, _ = make(b"HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found")
        reply = transport("https://a.example/x", {})
        self.assertEqual((reply.status, body_of(reply)), (404, b"Not Found"))

    def test_sends_a_get_for_path_and_query_with_the_given_headers(self):
        transport, network = make(HELLO)
        body_of(transport("https://a.example/search?q=topic%3Askills&page=2", {"User-Agent": "test-agent"}))
        sent = network.sockets[0].sent
        self.assertTrue(sent.startswith(b"GET /search?q=topic%3Askills&page=2 HTTP/1.1\r\n"), sent)
        self.assertIn(b"\r\nHost: a.example\r\n", sent)
        self.assertIn(b"\r\nUser-Agent: test-agent\r\n", sent)

    def test_url_without_a_path_requests_the_root(self):
        transport, network = make(HELLO)
        body_of(transport("https://a.example", {}))
        self.assertTrue(network.sockets[0].sent.startswith(b"GET / HTTP/1.1\r\n"))

    def test_does_not_ask_the_server_to_close_the_connection(self):
        transport, network = make(HELLO)
        body_of(transport("https://a.example/x", {}))
        self.assertNotIn(b"connection: close", network.sockets[0].sent.lower())

    def test_dials_the_host_and_port_of_the_url(self):
        transport, network = make(HELLO, WORLD)
        body_of(transport("https://a.example/x", {}))
        body_of(transport("https://b.example:8443/x", {}))
        self.assertEqual(network.dialed, [("a.example", None), ("b.example", 8443)])


class ConnectionReuse(unittest.TestCase):
    def test_second_request_to_a_host_reuses_its_connection(self):
        transport, network = make(HELLO + WORLD)
        first = body_of(transport("https://a.example/1", {}))
        second = body_of(transport("https://a.example/2", {}))
        self.assertEqual((first, second, len(network.sockets)), (b"hello", b"world", 1))

    def test_each_host_gets_its_own_connection(self):
        transport, network = make(HELLO, WORLD)
        first = body_of(transport("https://a.example/1", {}))
        second = body_of(transport("https://b.example/1", {}))
        self.assertEqual((first, second, len(network.sockets)), (b"hello", b"world", 2))

    def test_reply_closed_before_its_end_gives_up_the_connection(self):
        big = b"HTTP/1.1 200 OK\r\nContent-Length: 500000\r\n\r\n" + b"x" * 500000
        transport, network = make(big, WORLD)
        reply = transport("https://a.example/big", {})
        reply.read(10)
        reply.close()
        self.assertEqual(body_of(transport("https://a.example/next", {})), b"world")
        self.assertTrue(network.sockets[0].closed)

    def test_small_unread_body_is_drained_so_the_connection_stays_usable(self):
        transport, network = make(b"HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found" + WORLD)
        transport("https://a.example/missing", {}).close()
        self.assertEqual(body_of(transport("https://a.example/next", {})), b"world")
        self.assertEqual(len(network.sockets), 1)

    def test_connection_the_server_will_close_is_not_reused(self):
        closing = b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello"
        transport, network = make(closing, WORLD)
        body_of(transport("https://a.example/1", {}))
        self.assertEqual(body_of(transport("https://a.example/2", {})), b"world")
        self.assertNotIn(b"GET /2", network.sockets[0].sent)
        self.assertTrue(network.sockets[0].closed)

    def test_idle_connection_the_server_dropped_is_replaced(self):
        transport, network = make(HELLO, WORLD)  # first socket has nothing after "hello"
        body_of(transport("https://a.example/1", {}))
        self.assertEqual(body_of(transport("https://a.example/2", {})), b"world")
        self.assertEqual(len(network.sockets), 2)


class Failures(unittest.TestCase):
    def test_body_shorter_than_its_content_length_raises(self):
        transport, _ = make(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n" + b"x" * 40)
        reply = transport("https://a.example/x", {})
        with self.assertRaises(OSError):
            while reply.read(16):
                pass

    def test_short_body_raises_when_read_in_one_go(self):
        transport, _ = make(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n" + b"x" * 40)
        reply = transport("https://a.example/x", {})
        with self.assertRaises(OSError):
            reply.read()

    def test_chunked_body_cut_mid_chunk_raises(self):
        transport, _ = make(
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n1f40\r\nabc"
        )
        reply = transport("https://a.example/x", {})
        with self.assertRaises(OSError):
            while reply.read(16):
                pass

    def test_complete_body_read_in_pieces_ends_with_empty_bytes(self):
        transport, _ = make(HELLO)
        reply = transport("https://a.example/x", {})
        self.assertEqual([reply.read(3), reply.read(3), reply.read(3)], [b"hel", b"lo", b""])

    def test_connection_whose_reply_broke_is_not_sent_another_request(self):
        transport, network = make(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n" + b"x" * 40, WORLD)
        reply = transport("https://a.example/short", {})
        with self.assertRaises(OSError):
            reply.read()
        reply.close()
        self.assertEqual(body_of(transport("https://a.example/next", {})), b"world")
        self.assertNotIn(b"/next", network.sockets[0].sent)
        self.assertTrue(network.sockets[0].closed)

    def test_no_reply_on_a_new_connection_raises_without_redialing(self):
        transport, network = make(b"")
        with self.assertRaises(OSError):
            transport("https://a.example/x", {})
        self.assertEqual(len(network.sockets), 1)

    def test_reply_that_is_not_http_raises_oserror(self):
        transport, _ = make(b"SSH-2.0-OpenSSH_9.6\r\n\r\n")
        with self.assertRaises(OSError):
            transport("https://a.example/x", {})


class TlsContext(unittest.TestCase):
    def test_certificates_and_host_names_are_always_verified(self):
        context = tls_context()
        self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)
        self.assertTrue(context.check_hostname)

    def test_python_without_a_ca_store_gets_the_operating_system_bundle(self):
        paths = ssl.get_default_verify_paths()
        if paths.cafile or paths.capath:
            self.skipTest("this Python build has its own CA store")
        if not os.path.exists("/etc/ssl/cert.pem"):
            self.skipTest("no operating system bundle at the fallback path")
        self.assertGreater(tls_context().cert_store_stats()["x509_ca"], 0)


if __name__ == "__main__":
    unittest.main()
