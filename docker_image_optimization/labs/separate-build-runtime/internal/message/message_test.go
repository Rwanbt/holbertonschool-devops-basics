package message

import "testing"

func TestJSON(t *testing.T) {
	const expected = `{"service":"greeter","status":"ok"}`
	if got := JSON(); got != expected {
		t.Fatalf("JSON() = %q, want %q", got, expected)
	}
}
