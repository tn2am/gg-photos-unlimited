package service

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func TestCompletionRevisionAndPrivateSummary(t *testing.T) {
	e := newEngine(t, func(_ context.Context, _ []string, _ string, _ string, _ func(Progress)) (string, error) {
		return "private-media-key", nil
	})
	importTest(t, e, "original")
	e.online = true
	e.wifi = true
	e.Tick()
	waitIdle(t, e)
	if e.state.CompletionRevision != 1 {
		t.Fatal("commit did not notify observer")
	}
	raw := e.HandleJSON([]byte(`{"op":"upload_summary"}`), "settings")
	var response struct {
		OK   bool
		Data struct {
			CompletionRevision uint64
			DefaultQuality     string
			Conditions         map[string]bool
			Profiles           map[string]struct {
				Model         string
				StoragePolicy int
				UploadQuality int
				States        map[string]int
			}
		}
	}
	if err := json.Unmarshal(raw, &response); err != nil || !response.OK {
		t.Fatalf("invalid summary: %s", raw)
	}
	mode := response.Data.Profiles["original"]
	if !response.Data.Conditions["online"] || !response.Data.Conditions["wifi"] || response.Data.Conditions["charging"] || response.Data.Conditions["paused"] {
		t.Fatal("summary did not expose authoritative upload conditions")
	}
	if response.Data.CompletionRevision != 1 || mode.Model != "Pixel XL" || mode.StoragePolicy != 3 || mode.UploadQuality != 1 || mode.States["completed"] != 1 {
		t.Fatal("incorrect summary policy")
	}
	for _, secret := range []string{"private-media-key", "photo.jpg", "a@example.com", "fingerprint", "account"} {
		if strings.Contains(string(raw), secret) {
			t.Fatal("private data in diagnostic summary")
		}
	}
	e.HandleJSON([]byte(`{"op":"clear_completed"}`), "settings")
	reopened, err := Open(e.root, nil)
	if err != nil {
		t.Fatal(err)
	}
	if reopened.state.CompletionRevision != 1 {
		t.Fatal("history cleanup or restart lost completion revision")
	}
	failed := newEngine(t, func(_ context.Context, _ []string, _ string, _ string, _ func(Progress)) (string, error) {
		return "", errors.New("failure")
	})
	importTest(t, failed, "original")
	failed.online = true
	failed.wifi = true
	failed.Tick()
	waitIdle(t, failed)
	if failed.state.CompletionRevision != 0 {
		t.Fatal("failed upload announced completion")
	}
	if strings.Contains(string(e.HandleJSON([]byte(`{"op":"upload_summary"}`), "untrusted")), `"ok":true`) {
		t.Fatal("untrusted summary request allowed")
	}
}

func TestSummaryConditionsReadOnly(t *testing.T) {
	e := newEngine(t, nil)
	e.online, e.wifi, e.charging = true, false, true
	e.state.Options.Paused = true
	for _, role := range []string{"googlephotos", "photos", "settings"} {
		var reply struct {
			OK   bool
			Data struct{ Conditions map[string]bool }
		}
		raw := e.HandleJSON([]byte(`{"op":"upload_summary","online":false,"wifi":true,"charging":false}`), role)
		if err := json.Unmarshal(raw, &reply); err != nil || !reply.OK {
			t.Fatal("authorized host could not read conditions")
		}
		c := reply.Data.Conditions
		if !c["online"] || c["wifi"] || !c["charging"] || !c["paused"] {
			t.Fatal("caller overwrote daemon conditions")
		}
		if strings.Contains(string(e.HandleJSON([]byte(`{"op":"conditions","online":false}`), role)), `"ok":true`) {
			t.Fatal("host changed daemon conditions")
		}
	}
}

func TestMediaFailureSummary(t *testing.T) {
	e := newEngine(t, nil)
	for i := 0; i < 60; i++ {
		e.state.Jobs = append(e.state.Jobs, &Job{Quality: "original", State: "completed", Resources: []Resource{{Name: "private-name.HEIC"}}})
	}
	for _, job := range []*Job{
		{Quality: "original", State: "failed", Error: "commit_outcome_unknown", Resources: []Resource{{Name: "private-name.heif"}}},
		{Quality: "original", State: "failed", Error: "remote_live_photo_component_exists", Resources: []Resource{{Name: "private-name.HEIC"}, {Name: "private-name.MOV"}}},
		{Quality: "original", State: "pending", Error: "upload_failed_retrying", Resources: []Resource{{Name: "private-name.jpeg"}}},
		{Quality: "original", State: "failed", Error: "private-error-token", Resources: []Resource{{Name: "private-name.private-extension"}}},
	} {
		e.state.Jobs = append(e.state.Jobs, job)
	}
	var response struct {
		OK   bool
		Data struct {
			MediaTypes map[string]struct{ States, FailureCodes map[string]int }
		}
	}
	raw := e.HandleJSON([]byte(`{"op":"upload_summary"}`), "googlephotos")
	if err := json.Unmarshal(raw, &response); err != nil || !response.OK {
		t.Fatal("missing media summary")
	}
	m := response.Data.MediaTypes
	if m["heic"].States["completed"] != 60 || m["heic"].States["failed"] != 1 || m["heic"].FailureCodes["commit_outcome_unknown"] != 1 {
		t.Fatal("HEIC completion and failure counts conflated")
	}
	if m["heic_live_photo"].FailureCodes["remote_live_photo_component_exists"] != 1 || m["jpeg"].FailureCodes["upload_failed_retrying"] != 1 || m["other"].FailureCodes["other"] != 1 {
		t.Fatal("incorrect media/error classification")
	}
	for _, secret := range []string{"private-name", "private-error-token", "private-extension"} {
		if strings.Contains(string(raw), secret) {
			t.Fatal("private data escaped into media diagnostics")
		}
	}
}

func TestSummaryIncludesEmptyProfilesAndMixedQualities(t *testing.T) {
	e := newEngine(t, nil)
	for _, job := range []*Job{
		{Quality: "original", State: "completed", Resources: []Resource{{Name: "a.heic"}}},
		{Quality: "saver", State: "pending", Resources: []Resource{{Name: "b.jpg"}}},
		{Quality: "saver", State: "failed", Resources: []Resource{{Name: "c.png"}}},
	} {
		e.state.Jobs = append(e.state.Jobs, job)
	}
	var reply struct {
		OK   bool
		Data struct {
			Profiles map[string]struct {
				Model                        string
				StoragePolicy, UploadQuality int
				States                       map[string]int
			}
			MediaTypes map[string]struct{ States, FailureCodes map[string]int }
		}
	}
	raw := e.HandleJSON([]byte(`{"op":"upload_summary"}`), "googlephotos")
	if err := json.Unmarshal(raw, &reply); err != nil || !reply.OK {
		t.Fatalf("invalid summary: %s", raw)
	}
	profiles := reply.Data.Profiles
	if len(profiles) != 3 || profiles["original"].Model != "Pixel XL" || profiles["original"].StoragePolicy != 3 ||
		profiles["saver"].Model != "Pixel 2" || profiles["saver"].StoragePolicy != 1 ||
		profiles["quota"].Model != "Pixel 8" || profiles["quota"].StoragePolicy != 3 {
		t.Fatal("quality profile metadata changed")
	}
	for _, profile := range profiles {
		if profile.UploadQuality != 1 || profile.States == nil {
			t.Fatal("profile counters must be JSON objects, including empty profiles")
		}
	}
	if profiles["original"].States["completed"] != 1 || profiles["saver"].States["pending"] != 1 ||
		profiles["saver"].States["failed"] != 1 || len(profiles["quota"].States) != 0 ||
		reply.Data.MediaTypes["png"].FailureCodes["unspecified"] != 1 {
		t.Fatal("media and quality counts diverged")
	}
}
