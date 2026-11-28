package core

import (
	"context"
	"io"
	"time"

	"github.com/metacubex/http"
	"github.com/metacubex/mihomo/component/ca"
)

const (
	defaultSpeedURL   = "https://speed.cloudflare.com/__down?bytes=25000000"
	speedTestDuration = 8 * time.Second
	speedTestDial     = 10 * time.Second
	// The first bytes ride TCP slow start and say little of the rate.
	speedTestWarmUp = 256 * 1024
	// A phone on mobile data would pay for every test.
	speedErrorMetered = "metered"
)

type SpeedParams struct {
	ProxyName string `json:"proxy-name"`
	Url       string `json:"url"`
}

type SpeedResult struct {
	BytesPerSecond int64  `json:"bytes-per-second"`
	Bytes          int64  `json:"bytes"`
	Error          string `json:"error,omitempty"`
}

var speedSlot = make(slots, 1)

// handleSpeedTest downloads through one node, one node at a time: two at
// once would share the line and both read low.
func handleSpeedTest(params *SpeedParams) *SpeedResult {
	if !onFreeNetwork() {
		return &SpeedResult{Error: speedErrorMetered}
	}
	proxy := lookupProxy(params.ProxyName)
	if proxy == nil {
		return &SpeedResult{Error: probeErrorFailed}
	}
	url := params.Url
	if url == "" {
		url = defaultSpeedURL
	}
	ctx, cancel := context.WithTimeout(context.Background(), speedTestDial+speedTestDuration)
	defer cancel()
	if !speedSlot.acquireWithin(ctx, 5*time.Minute) {
		return &SpeedResult{Error: probeErrorTimeout}
	}
	defer speedSlot.release()

	tlsConfig, err := ca.GetTLSConfig(ca.Option{})
	if err != nil {
		return &SpeedResult{Error: probeErrorFailed}
	}
	dialer := &probeDialer{proxy: proxy}
	transport := &http.Transport{
		DialContext:         dialer.dial,
		TLSClientConfig:     tlsConfig,
		TLSHandshakeTimeout: speedTestDial,
	}
	defer transport.CloseIdleConnections()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return &SpeedResult{Error: probeErrorFailed}
	}
	request.Header.Set("User-Agent", browserUserAgent)
	response, err := (&http.Client{Transport: transport}).Do(request)
	if err != nil {
		return &SpeedResult{Error: probeErrorKind(err)}
	}
	defer func() { _ = response.Body.Close() }()
	if response.StatusCode != http.StatusOK {
		return &SpeedResult{Error: probeErrorFailed}
	}
	total, rate := measureDownload(response.Body, speedTestDuration, time.Now)
	if rate <= 0 {
		return &SpeedResult{Bytes: total, Error: probeErrorFailed}
	}
	return &SpeedResult{Bytes: total, BytesPerSecond: rate}
}

// measureDownload reads for [limit] and rates what came after the warm-up.
func measureDownload(body io.Reader, limit time.Duration, now func() time.Time) (total, rate int64) {
	buffer := make([]byte, 64*1024)
	start := now()
	var warmAt time.Time
	var warmBytes int64
	for {
		n, err := body.Read(buffer)
		total += int64(n)
		at := now()
		if warmAt.IsZero() && total >= speedTestWarmUp {
			warmAt, warmBytes = at, total
		}
		if err != nil || at.Sub(start) >= limit {
			from, counted := start, total
			if !warmAt.IsZero() && at.Sub(warmAt) >= time.Second {
				from, counted = warmAt, total-warmBytes
			}
			elapsed := at.Sub(from)
			if elapsed <= 0 {
				return total, 0
			}
			return total, int64(float64(counted) / elapsed.Seconds())
		}
	}
}
