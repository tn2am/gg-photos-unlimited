package service

import (
	"os"
	"path/filepath"
	"testing"
)

func TestOpenRejectsIncompleteStateWithoutOverwriting(t *testing.T) {
	for _, persisted := range []string{"null", "{}", `{"version":1}`, `{"options":{"quality":"original","concurrent":1},"jobs":[]}`, `{"version":1,"options":null,"jobs":[]}`, `{"version":1,"options":{"quality":"original"},"jobs":[]}`} {
		t.Run(persisted, func(t *testing.T) {
			root := t.TempDir()
			path := filepath.Join(root, "state.json")
			if err := os.WriteFile(path, []byte(persisted), 0600); err != nil {
				t.Fatal(err)
			}
			engine, err := Open(root, nil)
			if engine != nil {
				engine.Close()
			}
			if err == nil {
				t.Error("accepted incomplete persisted state")
			}
			got, err := os.ReadFile(path)
			if err != nil || string(got) != persisted {
				t.Fatalf("invalid state was overwritten: %q, %v", got, err)
			}
		})
	}
}
