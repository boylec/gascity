package tmux

import (
	"strings"
	"testing"
)

// callIndexContaining returns the index of the first recorded call whose joined
// args contain every token, or -1.
func callIndexContaining(calls [][]string, tokens ...string) int {
	for i, call := range calls {
		joined := strings.Join(call, "\x00")
		ok := true
		for _, tok := range tokens {
			if !strings.Contains(joined, tok) {
				ok = false
				break
			}
		}
		if ok {
			return i
		}
	}
	return -1
}

func countCalls(calls [][]string, tokens ...string) int {
	n := 0
	for i := range calls {
		if callIndexContaining(calls[i:i+1], tokens...) == 0 {
			n++
		}
	}
	return n
}

// TestSubmitWithVerifyResendsOnDroppedEnter is the regression test for
// hq-hyb6h: the first Enter is delivered without a tmux error but Claude's
// input widget drops it, so the pasted text is still parked in the input box.
// submitWithVerify must notice the box did not clear and re-send Enter.
func TestSubmitWithVerifyResendsOnDroppedEnter(t *testing.T) {
	const msg = "check MQ for assigned work, then patrol"

	// Attached session (#{session_attached}="1") so WakePaneIfDetached makes no
	// resize calls — the per-attempt sequence is exactly:
	//   send-keys Enter ; display-message session_attached ; capture-pane
	stuckPane := "some scrollback\n│ > " + msg + "\n╰─────────╯"
	clearPane := "● Working on it now\n│ > \n╰─────────╯"
	fe := &fakeExecutor{
		outs: []string{
			"",        // 0: send-keys Enter (attempt 1)
			"1",       // 1: display-message session_attached
			stuckPane, // 2: capture-pane -> text still in box (drop!)
			"",        // 3: send-keys Enter (attempt 2)
			"1",       // 4: display-message session_attached
			clearPane, // 5: capture-pane -> box cleared
		},
	}
	tm := NewTmuxWithConfig(DefaultConfig())
	tm.exec = fe

	if err := tm.submitWithVerify("sess", "sess", msg); err != nil {
		t.Fatalf("submitWithVerify() = %v, want nil", err)
	}

	if got := countCalls(fe.calls, "send-keys", "Enter"); got != 2 {
		t.Fatalf("Enter send-keys count = %d, want 2 (one dropped, one re-sent): %#v", got, fe.calls)
	}
	if callIndexContaining(fe.calls, "capture-pane") < 0 {
		t.Fatalf("expected a verify capture-pane; calls=%#v", fe.calls)
	}
}

// TestSubmitWithVerifyStopsAfterClear confirms the happy path does NOT re-send
// Enter once the input box has cleared.
func TestSubmitWithVerifyStopsAfterClear(t *testing.T) {
	const msg = "run gc prime and begin patrol"
	fe := &fakeExecutor{
		outs: []string{
			"",                  // 0: send-keys Enter
			"1",                 // 1: display-message session_attached
			"● Patrolling now…", // 2: capture-pane -> box cleared, no nudge text
		},
	}
	tm := NewTmuxWithConfig(DefaultConfig())
	tm.exec = fe

	if err := tm.submitWithVerify("sess", "sess", msg); err != nil {
		t.Fatalf("submitWithVerify() = %v, want nil", err)
	}
	if got := countCalls(fe.calls, "send-keys", "Enter"); got != 1 {
		t.Fatalf("Enter send-keys count = %d, want 1 (no spurious re-send): %#v", got, fe.calls)
	}
}

// TestSubmitWithVerifyFailsWhenNeverSubmits confirms a bounded failure when the
// input box never clears (rather than reporting a false success).
func TestSubmitWithVerifyFailsWhenNeverSubmits(t *testing.T) {
	const msg = "drain-ack and exit cleanly"
	stuck := "│ > " + msg
	// Every capture shows the text still parked. Provide enough scripted
	// responses for all submitVerifyAttempts; trailing calls fall through to
	// the zero-value out ("") which is harmless for send-keys/display-message.
	fe := &fakeExecutor{
		outs: []string{
			"", "1", stuck, // attempt 1
			"", "1", stuck, // attempt 2
			"", "1", stuck, // attempt 3
		},
	}
	tm := NewTmuxWithConfig(DefaultConfig())
	tm.exec = fe

	err := tm.submitWithVerify("sess", "sess", msg)
	if err == nil {
		t.Fatalf("submitWithVerify() = nil, want error when input never clears")
	}
	if got := countCalls(fe.calls, "send-keys", "Enter"); got != submitVerifyAttempts {
		t.Fatalf("Enter send-keys count = %d, want %d: %#v", got, submitVerifyAttempts, fe.calls)
	}
}

func TestNudgeStillPendingMatchesOnlyInputLine(t *testing.T) {
	const msg = "check for assigned work"
	tm := NewTmuxWithConfig(DefaultConfig())

	// Text on the input prompt line -> pending.
	fe := &fakeExecutor{outs: []string{"│ > " + msg}}
	tm.exec = fe
	if !tm.nudgeStillPending("sess", msg) {
		t.Fatalf("nudgeStillPending = false, want true when text is on the input line")
	}

	// Same text but as submitted transcript output (● prefix) -> not pending.
	fe = &fakeExecutor{outs: []string{"● " + msg + "\n  doing it"}}
	tm.exec = fe
	if tm.nudgeStillPending("sess", msg) {
		t.Fatalf("nudgeStillPending = true, want false when text is submitted output")
	}

	// Empty/short message must never trigger a re-submit.
	fe = &fakeExecutor{outs: []string{"│ > "}}
	tm.exec = fe
	if tm.nudgeStillPending("sess", "  ") {
		t.Fatalf("nudgeStillPending = true for whitespace message, want false")
	}
}
