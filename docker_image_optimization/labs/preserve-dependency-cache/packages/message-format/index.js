"use strict";

function healthPayload(service) {
  return JSON.stringify({ service, status: "ok" });
}

module.exports = { healthPayload };
