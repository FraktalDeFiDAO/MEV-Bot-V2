// finder/finder.go

// Package finder provides the core logic for finding files based on a configuration.
// It walks a directory tree, applying include and exclude glob patterns, and writes
// the contents of matching files to a specified writer.
package finder

import (
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// Config holds the configuration for the file finding operation.
// This structure makes the function signature clean and easy to extend.
type Config struct {
	// Root is the starting directory for the search.
	Root string
	// IncludePattern is a case-insensitive glob pattern for file names to include.
	IncludePattern string
	// ExcludePatterns is a slice of glob patterns for paths to exclude.
	// If a directory matches, the entire directory is skipped.
	ExcludePatterns []string
	// Output is the destination for the formatted content. It can be a file,
	// standard output, or any other type that implements io.Writer.
	Output io.Writer
}

// Run executes the file finding and processing operation based on the provided config.
// It returns an error if the root directory cannot be walked or if any file
// operations fail.
func Run(cfg Config) error {
	// filepath.WalkDir is a modern and efficient way to recursively walk a directory.
	walkErr := filepath.WalkDir(cfg.Root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			// Propagate errors encountered by WalkDir, e.g., permission denied.
			return err
		}

		// --- Exclusion Logic ---
		// Check if the current path matches any of the exclusion patterns.
		for _, pattern := range cfg.ExcludePatterns {
			// filepath.Match performs glob-style matching.
			matched, _ := filepath.Match(pattern, path)
			if matched {
				if d.IsDir() {
					// If a directory is excluded, skip walking its contents.
					// This is a crucial optimization for directories like .git or node_modules.
					return filepath.SkipDir
				}
				// If it's a file, just skip this entry.
				return nil
			}
		}

		// We are only interested in processing files, not directories.
		if d.IsDir() {
			return nil
		}

		// --- Inclusion Logic ---
		// To replicate '-iname', we perform a case-insensitive match.
		// We convert both the filename and the pattern to lower case.
		includePatternLower := strings.ToLower(cfg.IncludePattern)
		fileNameLower := strings.ToLower(d.Name())

		matched, _ := filepath.Match(includePatternLower, fileNameLower)
		if !matched {
			// Skip files that don't match the inclusion pattern.
			return nil
		}

		// If we reach here, the file is a match and should be processed.
		return processFile(path, cfg.Output)
	})

	return walkErr
}

// processFile formats and writes the content of a single file to the writer.
// This function replicates the 'echo ... && cat ... && echo ...' logic.
func processFile(path string, writer io.Writer) error {
	// Open the matched file for reading.
	file, err := os.Open(path)
	if err != nil {
		// Return a more informative error message.
		return fmt.Errorf("error opening file %s: %w", path, err)
	}
	defer file.Close()

	// Use filepath.ToSlash to ensure consistent forward slashes in the output,
	// regardless of the operating system.
	cleanPath := filepath.ToSlash(path)

	// Write header comment.
	header := fmt.Sprintf("//******************************\\\\\n// [ START => %s ]\n", cleanPath)
	if _, err := io.WriteString(writer, header); err != nil {
		return fmt.Errorf("error writing header for %s: %w", path, err)
	}

	// Efficiently copy the entire file content to the output writer.
	if _, err := io.Copy(writer, file); err != nil {
		return fmt.Errorf("error writing content for %s: %w", path, err)
	}

	// Write footer comment. Note the newline at the start to separate from file content.
	footer := fmt.Sprintf("\n// [ %s <= END ]\n//******************************\\\\\n\n", cleanPath)
	if _, err := io.WriteString(writer, footer); err != nil {
		return fmt.Errorf("error writing footer for %s: %w", path, err)
	}

	return nil
}
