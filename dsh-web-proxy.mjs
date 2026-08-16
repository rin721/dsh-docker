import http from "node:http";
import net from "node:net";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));

const upstreamHost = process.env.DSH_INTERNAL_HOST || "127.0.0.1";
const upstreamPort = Number(process.env.DSH_INTERNAL_PORT || "3079");
const listenHost = process.env.DSH_PROXY_HOST || "0.0.0.0";
const listenPort = Number(process.env.DSH_PROXY_PORT || "3080");
const compatEnabled = !["0", "false", "no", "off"].includes(
  String(process.env.DSH_HTTP_COMPAT_SHIM ?? "true").toLowerCase(),
);

const internalAuthority = `localhost:${upstreamPort}`;
const internalOrigin = `http://${internalAuthority}`;
const compatPath = "/__dsh_http_compat.js";
const compatScript = readFileSync(join(here, "dsh-http-compat.js"), "utf8");
const compatTag = `<script src="${compatPath}"></script>`;

function singleHeader(headers, name) {
  const value = headers[name];
  return typeof value === "string" ? value : undefined;
}

function parseAuthority(authority) {
  try {
    const parsed = new URL(`http://${authority}`);
    // Host must be a bare authority. Reject userinfo/path/query/hash shapes that
    // URL parsing would otherwise silently accept.
    if (
      parsed.username !== "" ||
      parsed.password !== "" ||
      parsed.pathname !== "/" ||
      parsed.search !== "" ||
      parsed.hash !== "" ||
      parsed.hostname === ""
    ) {
      return undefined;
    }
    return parsed;
  } catch {
    return undefined;
  }
}

function validateExternalRequest(headers) {
  const host = singleHeader(headers, "host");
  if (host === undefined || parseAuthority(host) === undefined) {
    return { ok: false, reason: "invalid-host" };
  }

  if (singleHeader(headers, "sec-fetch-site") === "cross-site") {
    return { ok: false, reason: "cross-site" };
  }

  const origin = singleHeader(headers, "origin");
  if (origin !== undefined) {
    try {
      // Mirror DSH's browser trust contract: when Origin is present, its
      // authority must exactly match Host. Scheme itself is not compared.
      const hostUrl = new URL(`http://${host}`);
      if (new URL(origin).host !== hostUrl.host) {
        return { ok: false, reason: "origin-host-mismatch" };
      }
    } catch {
      return { ok: false, reason: "invalid-origin" };
    }
  }

  return { ok: true, host };
}

function internalizeHeaders(headers) {
  const result = { ...headers };

  // DSH stays loopback-only. We terminate the external authority at this
  // trusted proxy boundary after validation, so DSH always sees localhost.
  result.host = internalAuthority;

  // If the browser supplied Origin, normalize it together with Host. Leaving
  // the external Origin while changing Host would make DSH reject /api with 403.
  if (singleHeader(headers, "origin") !== undefined) {
    result.origin = internalOrigin;
  }

  // HTML rewriting is reliable only with an identity-encoded response.
  result["accept-encoding"] = "identity";

  return result;
}

function rejectHttp(response, reason) {
  response.writeHead(403, {
    "content-type": "text/plain; charset=utf-8",
    "cache-control": "no-store",
    "x-dsh-proxy-reject": reason,
  });
  response.end("forbidden\n");
}

function rejectUpgrade(socket, reason) {
  if (socket.writable) {
    const body = "forbidden\n";
    socket.end(
      "HTTP/1.1 403 Forbidden\r\n" +
        "Connection: close\r\n" +
        "Content-Type: text/plain; charset=utf-8\r\n" +
        `Content-Length: ${Buffer.byteLength(body)}\r\n` +
        `X-DSH-Proxy-Reject: ${reason}\r\n` +
        "\r\n" +
        body,
    );
  }
}

function sanitizeResponseHeaders(headers, rewritten) {
  const result = { ...headers };

  if (rewritten) {
    delete result["content-length"];
    delete result["content-encoding"];
    delete result.etag;
    delete result["last-modified"];
  }

  return result;
}

function injectCompatScript(html) {
  if (!compatEnabled || html.includes(compatPath)) {
    return html;
  }

  if (/<\/head>/i.test(html)) {
    return html.replace(/<\/head>/i, `${compatTag}</head>`);
  }

  if (/<body(?:\s[^>]*)?>/i.test(html)) {
    return html.replace(/<body(?:\s[^>]*)?>/i, (match) => `${match}${compatTag}`);
  }

  return `${compatTag}${html}`;
}

const server = http.createServer((clientRequest, clientResponse) => {
  const trust = validateExternalRequest(clientRequest.headers);
  if (!trust.ok) {
    rejectHttp(clientResponse, trust.reason);
    return;
  }

  if (clientRequest.url === compatPath) {
    if (!compatEnabled) {
      clientResponse.writeHead(404, {
        "content-type": "text/plain; charset=utf-8",
        "cache-control": "no-store",
      });
      clientResponse.end("compat shim disabled\n");
      return;
    }

    clientResponse.writeHead(200, {
      "content-type": "application/javascript; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    });
    clientResponse.end(compatScript);
    return;
  }

  const upstreamRequest = http.request(
    {
      host: upstreamHost,
      port: upstreamPort,
      method: clientRequest.method,
      path: clientRequest.url || "/",
      headers: internalizeHeaders(clientRequest.headers),
    },
    (upstreamResponse) => {
      const contentType = String(upstreamResponse.headers["content-type"] || "");
      const shouldRewrite =
        compatEnabled &&
        /^text\/html(?:;|$)/i.test(contentType) &&
        clientRequest.method !== "HEAD";

      if (!shouldRewrite) {
        clientResponse.writeHead(
          upstreamResponse.statusCode || 502,
          sanitizeResponseHeaders(upstreamResponse.headers, false),
        );
        upstreamResponse.pipe(clientResponse);
        return;
      }

      const chunks = [];
      let total = 0;
      const maxHtmlBytes = 8 * 1024 * 1024;

      upstreamResponse.on("data", (chunk) => {
        total += chunk.length;
        if (total > maxHtmlBytes) {
          upstreamResponse.destroy(
            new Error("DSH HTML response exceeded compatibility proxy limit"),
          );
          return;
        }
        chunks.push(chunk);
      });

      upstreamResponse.on("end", () => {
        const html = Buffer.concat(chunks).toString("utf8");
        const rewritten = Buffer.from(injectCompatScript(html), "utf8");
        const headers = sanitizeResponseHeaders(upstreamResponse.headers, true);

        headers["content-length"] = String(rewritten.length);
        headers["x-dsh-http-compat"] = compatEnabled ? "active" : "disabled";

        clientResponse.writeHead(upstreamResponse.statusCode || 200, headers);
        clientResponse.end(rewritten);
      });

      upstreamResponse.on("error", (error) => {
        if (!clientResponse.headersSent) {
          clientResponse.writeHead(502, {
            "content-type": "text/plain; charset=utf-8",
          });
        }
        clientResponse.end(`upstream response error: ${error.message}\n`);
      });
    },
  );

  upstreamRequest.on("error", (error) => {
    if (!clientResponse.headersSent) {
      clientResponse.writeHead(502, {
        "content-type": "text/plain; charset=utf-8",
      });
    }
    clientResponse.end(`upstream request error: ${error.message}\n`);
  });

  clientRequest.pipe(upstreamRequest);
});

server.on("upgrade", (request, clientSocket, head) => {
  const trust = validateExternalRequest(request.headers);
  if (!trust.ok) {
    rejectUpgrade(clientSocket, trust.reason);
    return;
  }

  const upstreamSocket = net.connect(upstreamPort, upstreamHost);

  upstreamSocket.on("connect", () => {
    const headers = internalizeHeaders(request.headers);

    let handshake = `${request.method} ${request.url || "/"} HTTP/${request.httpVersion}\r\n`;
    for (const [name, value] of Object.entries(headers)) {
      if (Array.isArray(value)) {
        for (const item of value) {
          handshake += `${name}: ${item}\r\n`;
        }
      } else if (value !== undefined) {
        handshake += `${name}: ${value}\r\n`;
      }
    }
    handshake += "\r\n";

    upstreamSocket.write(handshake);
    if (head?.length) {
      upstreamSocket.write(head);
    }

    clientSocket.pipe(upstreamSocket).pipe(clientSocket);
  });

  const closeBoth = () => {
    clientSocket.destroy();
    upstreamSocket.destroy();
  };

  upstreamSocket.on("error", closeBoth);
  clientSocket.on("error", closeBoth);
});

server.on("clientError", (_error, socket) => {
  if (socket.writable) {
    socket.end("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n");
  }
});

server.listen(listenPort, listenHost, () => {
  console.log(
    `DSH compatibility proxy listening on ${listenHost}:${listenPort} -> ` +
      `${upstreamHost}:${upstreamPort}; authority=dynamic; HTTP compat shim=${compatEnabled}`,
  );
});
