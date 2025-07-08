package utils

import (
	"log"
	"os"
)

func InitLogging() {
	// Example: Customize logging output
	log.SetFlags(log.LstdFlags | log.Lmicroseconds | log.Lshortfile) // Add file/line and microseconds
	log.SetOutput(os.Stdout)                                         // Default, but can be set to a file
	log.Println("Logging initialized")
}
