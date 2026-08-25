"use strict";

const http = require("http");
const { healthPayload } = require("message-format");

const server = http.createServer((request, response) => {
  if (request.url === "/health") {
    const body = healthPayload("cache-lab");
    response.writeHead(200, {
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(body),
    });
    response.end(body);
    return;
  }

  const body = JSON.stringify({ error: "not found" });
  response.writeHead(404, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
  });
  response.end(body);
});

server.listen(8080, "0.0.0.0");
