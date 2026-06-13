package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
)

// LintEntry is one diagnosed line from a .ccr/shadow file.
type LintEntry struct {
	Line     int    // 1-based source line number
	Raw      string // raw pattern as written, trimmed of whitespace
	Status   string // "ok" | "warn" | "err"
	Class    string // "literal-unanchored" | "literal-anchored" | "glob-anchored" | "glob-unanchored" | "" if not applicable
	Key      string // lookup key for fast-path buckets; raw pattern for globs
	Message  string // human-readable note when status != ok
}

// runLint is the entrypoint for `ccr-fuse lint`.
func runLint(args []string) {
	fs := flag.NewFlagSet("lint", flag.ExitOnError)
	matchPath := fs.String("match", "", "report whether this workspace-relative path would be shadowed")
	fs.Usage = func() {
		fmt.Fprintln(os.Stderr, "Usage: ccr-fuse lint [--match <path>] [<.ccr/shadow file>]")
		fmt.Fprintln(os.Stderr, "  Default file: .ccr/shadow in the current directory.")
		fs.PrintDefaults()
	}
	_ = fs.Parse(args)

	path := ".ccr/shadow"
	if fs.NArg() > 0 {
		path = fs.Arg(0)
	}

	f, err := os.Open(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ccr-fuse lint: %v\n", err)
		os.Exit(2)
	}
	defer f.Close()

	entries, err := lintReader(f)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ccr-fuse lint: read %s: %v\n", path, err)
		os.Exit(2)
	}

	var active, warns, errs int
	maxRaw := 0
	for _, e := range entries {
		if l := len(e.Raw); l > maxRaw {
			maxRaw = l
		}
		switch e.Status {
		case "ok":
			active++
		case "warn":
			warns++
		case "err":
			errs++
		}
	}
	if maxRaw < 8 {
		maxRaw = 8
	}

	for _, e := range entries {
		fmt.Printf("%s:%d: %-*s  %-4s  %s\n",
			path, e.Line, maxRaw, e.Raw, strings.ToUpper(e.Status), describe(e))
	}
	fmt.Printf("\nSummary: %d active, %d warning, %d error\n", active, warns, errs)

	if *matchPath != "" {
		fmt.Printf("\nMatch report for path %q:\n", *matchPath)
		matches := matchAgainst(*matchPath, entries)
		if len(matches) == 0 {
			fmt.Println("  not matched by any active rule")
		} else {
			for _, m := range matches {
				fmt.Printf("  matched by line %d: %s (%s)\n", m.Line, m.Raw, m.Class)
			}
		}
	}

	if errs > 0 {
		os.Exit(1)
	}
}

func describe(e LintEntry) string {
	if e.Message != "" {
		return e.Message
	}
	return e.Class
}

// lintReader walks the .ccr/shadow content and classifies each non-empty line.
// Errors and warnings do not abort — they show up as entries with their own
// Status. Returns I/O errors from the scanner.
func lintReader(r io.Reader) ([]LintEntry, error) {
	var out []LintEntry
	seen := map[string]int{}
	sc := bufio.NewScanner(r)
	for lineNo := 0; sc.Scan(); {
		lineNo++
		raw := strings.TrimRight(sc.Text(), "\r")
		trim := strings.TrimSpace(raw)
		if trim == "" || strings.HasPrefix(trim, "#") {
			continue
		}
		if strings.HasPrefix(trim, "!") {
			out = append(out, LintEntry{
				Line: lineNo, Raw: trim, Status: "warn",
				Message: "negation not supported; skipped",
			})
			continue
		}
		if err := validatePattern(trim); err != nil {
			out = append(out, LintEntry{
				Line: lineNo, Raw: trim, Status: "err",
				Message: err.Error() + "; skipped",
			})
			continue
		}
		if dup, ok := seen[trim]; ok {
			out = append(out, LintEntry{
				Line: lineNo, Raw: trim, Status: "warn",
				Message: fmt.Sprintf("duplicate of line %d", dup),
			})
			continue
		}
		seen[trim] = lineNo
		kind, key := classify(trim)
		out = append(out, LintEntry{
			Line:   lineNo,
			Raw:    trim,
			Status: "ok",
			Class:  className(kind, trim),
			Key:    key,
		})
	}
	return out, sc.Err()
}

func className(kind patKind, raw string) string {
	switch kind {
	case patUnanchored:
		return "literal-unanchored"
	case patAnchored:
		return "literal-anchored"
	case patGlob:
		if strings.HasPrefix(raw, "/") || strings.Contains(strings.TrimSuffix(raw, "/"), "/") {
			if strings.HasPrefix(raw, "**/") {
				return "glob-unanchored"
			}
			return "glob-anchored"
		}
		return "glob-unanchored"
	}
	return "unknown"
}

// matchAgainst runs each active lint entry against a candidate path and returns
// the entries that match. Reuses the same matching engine the FUSE driver uses.
func matchAgainst(path string, entries []LintEntry) []LintEntry {
	var matched []LintEntry
	for _, e := range entries {
		if e.Status != "ok" {
			continue
		}
		// Build a single-rule Rules instance and test it.
		r, _ := parseRulesReader(strings.NewReader(e.Raw + "\n"))
		if r.Match(path) {
			matched = append(matched, e)
		}
	}
	return matched
}
