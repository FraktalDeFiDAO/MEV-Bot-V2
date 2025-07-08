// main.go

// This is the main entrypoint for the command-line application.
// It handles parsing command-line flags to configure and run the file finder.
package main

import (
	"flag"
	"io"
	"log"
	"os"
	"strings"

	// Import the core finder package.
	// You may need to adjust this path based on your Go module name.
	"fraktal/mev-bot-v2/finder"
)

// stringSliceFlag is a custom flag type to allow a flag to be specified multiple times.
// This is the idiomatic way in Go to handle repeated command-line arguments like '--exclude'.
type stringSliceFlag []string

func (s *stringSliceFlag) String() string {
	return strings.Join(*s, ", ")
}

func (s *stringSliceFlag) Set(value string) error {
	*s = append(*s, value)
	return nil
}

func main() {
	// --- Configuration via Command-Line Flags ---
	var excludePatterns stringSliceFlag

	// Define command-line flags with sensible defaults.
	searchDir := flag.String("dir", ".", "The root directory to start the search from.")
	includePattern := flag.String("iname", "*.sol", "Case-insensitive glob pattern for files to include.")
	outputFile := flag.String("out", "", "Path to the output file. Defaults to standard output (stdout).")
	// Register our custom flag type for the 'exclude' argument.
	flag.Var(&excludePatterns, "exclude", "Path pattern to exclude (e.g., '*/test/*'). Can be specified multiple times.")

	flag.Parse() // Parse the command-line arguments.

	// If no custom '-exclude' flags are provided by the user, use the defaults
	// from the original shell command.
	if len(excludePatterns) == 0 {
		excludePatterns = []string{
			"*contracts/lib*",
			"*/.git/*",
			"*/node_modules/*",
			"*.env",
			"*/vendor/*",
		}
	}

	// --- Setup and Execution ---
	var writer io.Writer = os.Stdout
	var outFile *os.File
	var err error

	// If an output file is specified, create it and set it as the writer.
	if *outputFile != "" {
		outFile, err = os.Create(*outputFile)
		if err != nil {
			log.Fatalf("Error creating output file %s: %v", *outputFile, err)
		}
		// Ensure the file is closed properly when main() exits.
		defer outFile.Close()
		writer = outFile
		log.Printf("Output will be written to %s", *outputFile)
	}

	// Create the configuration struct for the finder.
	cfg := finder.Config{
		Root:            *searchDir,
		IncludePattern:  *includePattern,
		ExcludePatterns: excludePatterns,
		Output:          writer,
	}

	// Run the finder and handle any fatal errors.
	if err := finder.Run(cfg); err != nil {
		log.Fatalf("An error occurred: %v", err)
	}

	log.Println("Operation completed successfully.")
}
