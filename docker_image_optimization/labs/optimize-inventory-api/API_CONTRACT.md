# Inventory API Contract

The optimized image must preserve these responses:

- `GET /health` returns HTTP 200 and `{"service":"inventory-api","status":"ok"}`.
- `GET /items` returns HTTP 200 and `{"items":[{"id":1,"name":"layers"},{"id":2,"name":"cache"}]}`.

JSON whitespace and object-key order are not significant. No endpoint writes persistent data.
