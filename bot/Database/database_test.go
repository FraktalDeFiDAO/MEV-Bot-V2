package Database

import (
	"testing"
)

func TestDBWriterCommitBatch(t *testing.T) {
	writer, err := NewDBWriter(":memory:")
	if err != nil {
		t.Fatalf("failed to create DBWriter: %v", err)
	}

	writer.batch = append(writer.batch, &DBWriteRequest{
		Type:  SaveTokenRequest,
		Token: &TokenRecord{Address: "0x1", Symbol: "TST", Decimals: 18},
	})
	writer.commitBatch()

	row := writer.db.QueryRow("SELECT symbol FROM tokens WHERE address = ?", "0x1")
	var symbol string
	if err := row.Scan(&symbol); err != nil {
		t.Fatalf("token not inserted: %v", err)
	}
	if symbol != "TST" {
		t.Fatalf("unexpected symbol: %s", symbol)
	}
}
