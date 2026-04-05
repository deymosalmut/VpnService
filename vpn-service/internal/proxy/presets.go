package marzban

import (
	"time"

	"github.com/google/uuid"
)

// NewVLESSRealityUser builds a UserCreate configured for VLESS + XTLS-Reality.
// This is the recommended protocol for bypassing DPI.
func NewVLESSRealityUser(username string, expireAt time.Time, dataLimitGB int64, inboundTag string) UserCreate {
	vlessUUID := uuid.New().String()
	expire := expireAt.Unix()

	var dataLimit *int64
	if dataLimitGB > 0 {
		dl := dataLimitGB * 1024 * 1024 * 1024 // GB to bytes
		dataLimit = &dl
	}

	return UserCreate{
		Username: username,
		Proxies: map[string]ProxySettings{
			"vless": {
				ID:   vlessUUID,
				Flow: "xtls-rprx-vision",
			},
		},
		Inbounds: map[string][]string{
			"vless": {inboundTag},
		},
		Expire:                 &expire,
		DataLimit:              dataLimit,
		DataLimitResetStrategy: "no_reset",
		Status:                 "active",
	}
}

// NewMultiProtocolUser builds a UserCreate with both VLESS Reality and VMess.
// Useful for clients that don't support Reality.
func NewMultiProtocolUser(username string, expireAt time.Time, dataLimitGB int64, vlessInbound, vmessInbound string) UserCreate {
	sharedUUID := uuid.New().String()
	expire := expireAt.Unix()

	var dataLimit *int64
	if dataLimitGB > 0 {
		dl := dataLimitGB * 1024 * 1024 * 1024
		dataLimit = &dl
	}

	return UserCreate{
		Username: username,
		Proxies: map[string]ProxySettings{
			"vless": {
				ID:   sharedUUID,
				Flow: "xtls-rprx-vision",
			},
			"vmess": {
				ID: sharedUUID,
			},
		},
		Inbounds: map[string][]string{
			"vless": {vlessInbound},
			"vmess": {vmessInbound},
		},
		Expire:                 &expire,
		DataLimit:              dataLimit,
		DataLimitResetStrategy: "no_reset",
		Status:                 "active",
	}
}

// UsernameFromUserID generates a Marzban-compatible username from our internal user ID.
// Marzban usernames must be alphanumeric + underscore.
func UsernameFromUserID(userID string) string {
	// Replace non-alphanumeric chars with underscore
	result := make([]byte, 0, len(userID))
	for _, c := range []byte(userID) {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' {
			result = append(result, c)
		} else {
			result = append(result, '_')
		}
	}
	// Prefix to avoid collisions with manually created users
	return "vpn_" + string(result)
}
