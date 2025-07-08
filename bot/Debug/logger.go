package Debug

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
)

// Logger provides a dedicated logger for detailed debugging, writing to a separate file.
type Logger struct {
	*log.Logger
	file *os.File
}

// NewLogger creates and returns a new Logger instance.
func NewLogger(logPath string) (*Logger, error) {
	// Ensure the directory for the log file exists.
	logDir := filepath.Dir(logPath)
	if err := os.MkdirAll(logDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create debug log directory: %w", err)
	}

	// Open the log file in append mode, creating it if it doesn't exist.
	file, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0666)
	if err != nil {
		return nil, fmt.Errorf("failed to open debug log file: %w", err)
	}

	// Create a new logger that writes to the file.
	l := log.New(file, "DEBUG: ", log.Ldate|log.Ltime|log.Lmicroseconds|log.Lshortfile)

	return &Logger{
		Logger: l,
		file:   file,
	}, nil
}

// Close closes the underlying log file.
func (l *Logger) Close() error {
	if l.file != nil {
		return l.file.Close()
	}
	return nil
}

// LogJson marshals the given data structure to a pretty-printed JSON string and logs it.
// This is useful for inspecting the contents of complex objects.
func (l *Logger) LogJson(prefix string, data interface{}) {
	jsonData, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		l.Printf("%s: Error marshalling to JSON: %v", prefix, err)
		return
	}
	l.Printf("%s:\n%s", prefix, string(jsonData))
}
