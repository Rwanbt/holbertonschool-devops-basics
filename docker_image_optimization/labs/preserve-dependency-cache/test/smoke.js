"use strict";

const assert = require("assert");
const { healthPayload } = require("message-format");

assert.strictEqual(healthPayload("cache-lab"), '{"service":"cache-lab","status":"ok"}');
console.log("cache-lab tests passed");
