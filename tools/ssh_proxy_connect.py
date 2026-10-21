#!/usr/bin/env python3
"""SSH ProxyCommand: tunnel through the sandbox egress HTTP proxy (CONNECT).

Reads the proxy from the standard *_proxy environment variables (including
its credentials) and connects to the target host:port given as argv[1:3].
Credentials are only ever read from the environment of the calling process;
they are never printed, logged, or written to disk by this script.
Used for git-over-SSH to ssh.github.com:443 (GitHub SSH over the HTTPS port).
"""
import os
import select
import socket
import sys
import urllib.parse


def main() -> int:
    target_host, target_port = sys.argv[1], int(sys.argv[2])
    proxy_url = (
        os.environ.get("https_proxy")
        or os.environ.get("HTTPS_PROXY")
        or os.environ.get("http_proxy")
        or os.environ.get("HTTP_PROXY")
    )
    if not proxy_url:
        print("no *_proxy env var set", file=sys.stderr)
        return 1
    u = urllib.parse.urlparse(proxy_url)
    if u.hostname is None or u.port is None:
        print("malformed proxy url", file=sys.stderr)
        return 1

    sock = socket.create_connection((u.hostname, u.port), timeout=30)
    headers = [f"CONNECT {target_host}:{target_port} HTTP/1.1",
               f"Host: {target_host}:{target_port}"]
    if u.username:
        import base64

        creds = f"{urllib.parse.unquote(u.username)}:{urllib.parse.unquote(u.password or '')}"
        headers.append(
            "Proxy-Authorization: Basic "
            + base64.b64encode(creds.encode()).decode()
        )
    sock.sendall(("\r\n".join(headers) + "\r\n\r\n").encode())

    # Read the proxy response headers.
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            print("proxy closed during CONNECT", file=sys.stderr)
            return 1
        buf += chunk
    status_line = buf.split(b"\r\n", 1)[0].decode("latin-1")
    if " 200 " not in status_line:
        print(f"CONNECT failed: {status_line}", file=sys.stderr)
        return 1
    leftover = buf.split(b"\r\n\r\n", 1)[1]

    stdin = sys.stdin.buffer
    stdout = sys.stdout.buffer
    if leftover:
        stdout.write(leftover)
        stdout.flush()
    sock.setblocking(False)
    import os as _os

    stdin_fd = stdin.fileno()
    _os.set_blocking(stdin_fd, False)
    buffers = {stdin_fd: b"", sock.fileno(): b""}
    open_fds = {stdin_fd, sock.fileno()}
    while open_fds:
        rlist, _, _ = select.select(list(open_fds), [], [], 60)
        if not rlist:
            break
        for fd in rlist:
            try:
                data = _os.read(fd, 65536) if fd == stdin_fd else sock.recv(65536)
            except (BlockingIOError, InterruptedError):
                continue
            except OSError:
                data = b""
            if not data:
                open_fds.discard(fd)
                if fd != stdin_fd:
                    return 0
                try:
                    sock.shutdown(socket.SHUT_WR)
                except OSError:
                    pass
                continue
            if fd == stdin_fd:
                sock.sendall(data)
            else:
                stdout.write(data)
                stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
