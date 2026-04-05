package jwt

import (
	"fmt"
	"time"

	jwtlib "github.com/golang-jwt/jwt/v5"
)

// Issuer creates signed JWT tokens.
type Issuer struct {
	secret []byte
	ttl    time.Duration
}

func NewIssuer(secret string, ttl time.Duration) *Issuer {
	return &Issuer{
		secret: []byte(secret),
		ttl:    ttl,
	}
}

func (i *Issuer) Issue(userID, source string) (string, error) {
	now := time.Now()
	claims := jwtlib.MapClaims{
		"sub":    userID,
		"source": source,
		"iat":    now.Unix(),
		"exp":    now.Add(i.ttl).Unix(),
	}

	token := jwtlib.NewWithClaims(jwtlib.SigningMethodHS256, claims)
	signed, err := token.SignedString(i.secret)
	if err != nil {
		return "", fmt.Errorf("sign jwt: %w", err)
	}
	return signed, nil
}

// Parse validates and parses a JWT token.
func (i *Issuer) Parse(tokenStr string) (jwtlib.MapClaims, error) {
	token, err := jwtlib.Parse(tokenStr, func(t *jwtlib.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwtlib.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return i.secret, nil
	})
	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(jwtlib.MapClaims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid token")
	}

	return claims, nil
}
