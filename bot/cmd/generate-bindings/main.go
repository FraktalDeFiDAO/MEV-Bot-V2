package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// ABIArtifact represents the structure of the JSON output from `forge build`
// We only care about the ABI and Bytecode for abigen.
type ABIArtifact struct {
	ABI      json.RawMessage `json:"abi"`
	Bytecode struct {
		Object string `json:"object"` // Creation bytecode as a hex string (0x prefixed)
	} `json:"bytecode"`
	// DeployedBytecode struct { // Runtime bytecode, not typically used for abigen's --bin for new bindings
	// 	Object string `json:"object"`
	// } `json:"deployedBytecode"`
}

func main() {
	foundryProjectPath := flag.String("foundry-project", "./foundry_project", "Path to the Foundry project directory")
	outputDir := flag.String("output-dir", "./contracts", "Output directory for Go bindings")
	// Example: "MyContract1,MyContract2" or "MyContract1.sol:MyContract1,MyOtherContract.sol:MyOtherContract"
	contractsStr := flag.String("contracts", "", "Comma-separated list of contract names (e.g., ContractName) or source_file:ContractName pairs (e.g., MyContract.sol:MyContract)")
	baseGoPackage := flag.String("base-package", "fraktal/mev-bot-v2/contracts", "Base Go package for generated files (e.g., your_module/contracts)")

	flag.Parse()

	if *contractsStr == "" {
		log.Fatal("Error: -contracts flag is required. Please provide a comma-separated list of contract names or source_file:ContractName pairs.")
	}

	contractsToProcess := parseContractsInput(*contractsStr)
	if len(contractsToProcess) == 0 {
		log.Fatal("Error: No valid contracts specified.")
	}

	log.Println("Starting contract compilation and Go binding generation...")
	log.Printf("Foundry project path: %s", *foundryProjectPath)
	log.Printf("Go bindings output directory: %s", *outputDir)
	log.Printf("Base Go package: %s", *baseGoPackage)

	// 1. Run `forge build`
	log.Println("Running `forge build`...")
	cmdForge := exec.Command("forge", "build", "--force") // --force to recompile
	cmdForge.Dir = *foundryProjectPath
	var forgeErr bytes.Buffer
	cmdForge.Stderr = &forgeErr

	if err := cmdForge.Run(); err != nil {
		log.Fatalf("Error running `forge build`:\n%s\n%v", forgeErr.String(), err)
	}

	log.Println("`forge build` completed successfully.")

	// 2. For each contract, find artifact, extract ABI/BIN, run abigen
	forgeOutDir := filepath.Join(*foundryProjectPath, "out")

	for _, contractInfo := range contractsToProcess {
		log.Printf("Processing contract: %s (Source: %s)", contractInfo.ContractName, contractInfo.SourceFile)

		// Construct artifact path: out/<SourceFile>/<ContractName>.json
		// Example: out/MyContract.sol/MyContract.json
		// Example: out/interfaces/IERC20.sol/IERC20.json
		artifactPath := filepath.Join(forgeOutDir, contractInfo.SourceFile, contractInfo.ContractName+".json")

		if _, err := os.Stat(artifactPath); os.IsNotExist(err) {
			log.Printf("Warning: Artifact not found for %s at %s. Skipping.", contractInfo.ContractName, artifactPath)
			// Try a flatter structure if SourceFile was just ContractName.sol
			// e.g. out/ContractName.json if forge output is flatter for simple names
			// However, standard forge output is `out/Contract.sol/Contract.json`
			continue
		}

		// Read artifact JSON
		artifactData, err := os.ReadFile(artifactPath)
		if err != nil {
			log.Printf("Error reading artifact file %s: %v. Skipping.", artifactPath, err)
			continue
		}

		var artifact ABIArtifact
		if err := json.Unmarshal(artifactData, &artifact); err != nil {
			log.Printf("Error unmarshalling artifact JSON for %s: %v. Skipping.", contractInfo.ContractName, err)
			continue
		}

		if len(artifact.ABI) == 0 {
			log.Printf("Warning: ABI not found in artifact for %s. Skipping.", contractInfo.ContractName)
			continue
		}

		// Prepare for abigen
		// abigen needs ABI as a file. Create a temporary ABI file.
		// Alternatively, if abigen can take ABI via stdin or a flag, that's cleaner.
		// For robustness, let's write to a temp file.
		tempABIDir, err := os.MkdirTemp("", "abigen_abi_")
		if err != nil {
			log.Printf("Error creating temp dir for ABI: %v", err)
			continue
		}
		defer os.RemoveAll(tempABIDir) // Clean up temp dir

		tempABIFile := filepath.Join(tempABIDir, contractInfo.ContractName+".abi")
		if err := os.WriteFile(tempABIFile, artifact.ABI, 0644); err != nil {
			log.Printf("Error writing temporary ABI file for %s: %v. Skipping.", contractInfo.ContractName, err)
			continue
		}

		// Prepare output for abigen
		contractGoPackageName := strings.ToLower(contractInfo.ContractName)
		// goPkg := fmt.Sprintf("%s/%s", strings.TrimRight(*baseGoPackage, "/"), contractGoPackageName)
		goType := contractInfo.ContractName // Use original contract name for Go type

		// Ensure output subdirectory exists
		contractOutputDir := filepath.Join(*outputDir, contractGoPackageName)
		if err := os.MkdirAll(contractOutputDir, 0755); err != nil {
			log.Printf("Error creating output directory %s: %v. Skipping.", contractOutputDir, err)
			continue
		}
		goOutFile := filepath.Join(contractOutputDir, contractGoPackageName+".go")

		abigenArgs := []string{
			"--abi", tempABIFile,
			"--pkg", contractGoPackageName, // Package name for the file
			"--type", goType, // Struct name for the contract
			"--out", goOutFile,
		}

		// Add BIN if available (creation bytecode)
		// abigen --bin can take a hex string or a file path.
		// The `object` field from forge is already a hex string (0x prefixed).
		// abigen expects the hex string *without* the "0x" prefix for direct input.
		if artifact.Bytecode.Object != "" {
			bytecodeHex := strings.TrimPrefix(artifact.Bytecode.Object, "0x")
			if bytecodeHex != "" {
				abigenArgs = append(abigenArgs, "--bin", bytecodeHex)
				log.Printf("Using bytecode for %s", contractInfo.ContractName)
			}
		} else {
			log.Printf("No creation bytecode found in artifact for %s. abigen will run without --bin.", contractInfo.ContractName)
		}

		log.Printf("Running abigen for %s: Output: %s, Package: %s, Type: %s",
			contractInfo.ContractName, goOutFile, contractGoPackageName, goType)

		cmdAbigen := exec.Command("abigen", abigenArgs...)
		var abigenErr bytes.Buffer
		cmdAbigen.Stderr = &abigenErr
		var abigenOut bytes.Buffer
		cmdAbigen.Stdout = &abigenOut

		if err := cmdAbigen.Run(); err != nil {
			log.Printf("Error running `abigen` for %s:\nArgs: %v\nStdout: %s\nStderr: %s\nError: %v",
				contractInfo.ContractName, abigenArgs, abigenOut.String(), abigenErr.String(), err)
			continue
		}
		log.Printf("Successfully generated Go bindings for %s at %s", contractInfo.ContractName, goOutFile)
		if abigenOut.String() != "" {
			log.Printf("abigen stdout for %s:\n%s", contractInfo.ContractName, abigenOut.String())
		}
	}

	log.Println("Go binding generation process finished.")
}

type ContractToProcess struct {
	SourceFile   string // e.g., "MyContract.sol" or "interfaces/IERC20.sol"
	ContractName string // e.g., "MyContract" or "IERC20"
}

// parseContractsInput parses the -contracts flag.
// Input can be "Contract1,Contract2" or "Source1.sol:Contract1,Source2.sol:Contract2"
func parseContractsInput(contractsStr string) []ContractToProcess {
	var contracts []ContractToProcess
	parts := strings.Split(contractsStr, ",")
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		split := strings.SplitN(part, ":", 2)
		if len(split) == 2 {
			sourceFile := strings.TrimSpace(split[0])
			contractName := strings.TrimSpace(split[1])
			if sourceFile != "" && contractName != "" {
				contracts = append(contracts, ContractToProcess{SourceFile: sourceFile, ContractName: contractName})
			} else {
				log.Printf("Warning: Invalid contract format '%s', expected 'SourceFile.sol:ContractName'. Skipping.", part)
			}
		} else {
			// Assume it's just ContractName, and SourceFile is ContractName.sol
			contractName := strings.TrimSpace(split[0])
			if contractName != "" {
				contracts = append(contracts, ContractToProcess{SourceFile: contractName + ".sol", ContractName: contractName})
			} else {
				log.Printf("Warning: Invalid contract format '%s', expected 'ContractName' or 'SourceFile.sol:ContractName'. Skipping.", part)
			}
		}
	}
	return contracts
}
