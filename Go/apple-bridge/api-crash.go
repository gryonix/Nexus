package main

// Where a fatal Go panic is written, and Go's share of memory.

import "C"
import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"runtime"
	"runtime/debug"
	"runtime/pprof"
	"sort"
	"strconv"
	"strings"
)

// Above this many goroutines the note names where they wait
const crowdedGoroutines = 500

//export GryonixGoMemory
func GryonixGoMemory() *C.char {
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	inUse := float64(stats.HeapInuse+stats.StackInuse) / (1 << 20)
	count := runtime.NumGoroutine()
	note := fmt.Sprintf("Go %.1f MB, %d goroutines", inUse, count)
	if count > crowdedGoroutines {
		note += "; " + goroutineHotSpots(3)
	}
	return C.CString(note)
}

// The functions most goroutines are parked under, busiest first
func goroutineHotSpots(limit int) string {
	var dump bytes.Buffer
	if err := pprof.Lookup("goroutine").WriteTo(&dump, 1); err != nil {
		return err.Error()
	}
	counts := map[string]int{}
	group, named := 0, false
	scanner := bufio.NewScanner(&dump)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) >= 2 && fields[1] == "@" {
			group, _ = strconv.Atoi(fields[0])
			named = false
			continue
		}
		if named || len(fields) < 3 || fields[0] != "#" || isPlumbing(fields[2]) {
			continue
		}
		counts[shortName(fields[2])] += group
		named = true
	}
	return busiest(counts, limit)
}

func busiest(counts map[string]int, limit int) string {
	names := make([]string, 0, len(counts))
	for name := range counts {
		names = append(names, name)
	}
	sort.Slice(names, func(i, j int) bool { return counts[names[i]] > counts[names[j]] })
	if len(names) > limit {
		names = names[:limit]
	}
	parts := make([]string, len(names))
	for i, name := range names {
		parts[i] = fmt.Sprintf("%d %s", counts[name], name)
	}
	return strings.Join(parts, ", ")
}

// Standard library frames say nothing about which connection waits
func isPlumbing(function string) bool {
	for _, prefix := range []string{"runtime.", "internal/", "sync.", "io.", "net.", "bufio.", "crypto/", "time.", "context."} {
		if strings.HasPrefix(function, prefix) {
			return true
		}
	}
	return false
}

// The package's last path element and the function, no offset
func shortName(function string) string {
	function, _, _ = strings.Cut(function, "+")
	if cut := strings.LastIndex(function, "/"); cut >= 0 {
		return function[cut+1:]
	}
	return function
}

//export GryonixCrashOutput
func GryonixCrashOutput(path *C.char) *C.char {
	file, err := os.OpenFile(C.GoString(path), os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return C.CString(err.Error())
	}
	defer file.Close()
	if err := debug.SetCrashOutput(file, debug.CrashOptions{}); err != nil {
		return C.CString(err.Error())
	}
	return C.CString("")
}
