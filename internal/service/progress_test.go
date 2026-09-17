package service

import (
	"app/backend"
	"testing"
)

func TestReporterPreservesBytesThroughCommit(t *testing.T) {
	for _, path := range []string{"video.mov", "live-photo.heic"} {
		t.Run(path, func(t *testing.T) {
			var got Progress
			r := &reporter{callback: func(p Progress) { got = p }}
			for _, step := range []struct {
				status   backend.ThreadStatus
				state    string
				uploaded int64
			}{
				{backend.ThreadStatus{Status: "hashing", FilePath: path}, "preparing", 0},
				{backend.ThreadStatus{Status: "uploading", FilePath: path, BytesUploaded: 3, BytesTotal: 10}, "uploading", 3},
				{backend.ThreadStatus{Status: "uploading", FilePath: path, BytesUploaded: 9, BytesTotal: 10}, "uploading", 9},
				// The second Live Photo component already includes the still's bytes.
				{backend.ThreadStatus{Status: "uploading", FilePath: path, BytesUploaded: 10, BytesTotal: 10}, "uploading", 10},
				{backend.ThreadStatus{Status: "finalizing", FilePath: path}, "committing", 10},
				// Repeated phase notifications must neither reset nor add phantom bytes.
				{backend.ThreadStatus{Status: "finalizing"}, "committing", 10},
			} {
				r.ThreadStatus(step.status)
				if got.State != step.state || got.Uploaded != step.uploaded || got.Total != 0 {
					t.Fatalf("%+v => %+v, want %s/%d with unchanged resource total", step.status, got, step.state, step.uploaded)
				}
			}
		})
	}
}

func TestReporterPreservesRealRetryProgress(t *testing.T) {
	var got Progress
	r := &reporter{callback: func(p Progress) { got = p }}
	r.ThreadStatus(backend.ThreadStatus{Status: "uploading", FilePath: "photo.heic", BytesUploaded: 8, BytesTotal: 10})
	r.ThreadStatus(backend.ThreadStatus{Status: "uploading", FilePath: "photo.heic", BytesUploaded: 0, BytesTotal: 10, Attempt: 2})
	if got.Uploaded != 0 || got.State != "uploading" {
		t.Fatalf("retry counter replaced by stale progress: %+v", got)
	}
	r.ThreadStatus(backend.ThreadStatus{Status: "uploading", FilePath: "photo.heic", BytesUploaded: 4, BytesTotal: 10, Attempt: 2})
	if got.Uploaded != 4 {
		t.Fatal(got)
	}
}
