package service

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
)

// CryptoTokenGenerator generates cryptographically secure tokens.
type CryptoTokenGenerator struct {
	byteLen int // number of random bytes (token string will be 2x this length in hex)
}

func NewCryptoTokenGenerator(byteLen int) *CryptoTokenGenerator {
	if byteLen < 16 {
		byteLen = 16 // minimum 128-bit tokens
	}
	return &CryptoTokenGenerator{byteLen: byteLen}
}

func (g *CryptoTokenGenerator) Generate() (string, error) {
	b := make([]byte, g.byteLen)
	_, err := rand.Read(b)
	if err != nil {
		return "", fmt.Errorf("crypto/rand: %w", err)
	}
	return hex.EncodeToString(b), nil
}
