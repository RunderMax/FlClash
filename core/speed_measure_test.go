package core

import (
	"io"
	"net/http"
	"testing"
	"time"
)

type steadyBody struct {
	clock *time.Time
	chunk int
	step  time.Duration
	left  int
}

func (b *steadyBody) Read(p []byte) (int, error) {
	if b.left <= 0 {
		return 0, io.EOF
	}
	n := min(b.chunk, len(p), b.left)
	b.left -= n
	*b.clock = b.clock.Add(b.step)
	return n, nil
}

func TestMeasureDownloadRatesWhatCameAfterTheWarmUp(t *testing.T) {
	clock := time.Unix(0, 0)
	body := &steadyBody{clock: &clock, chunk: 64 * 1024, step: 100 * time.Millisecond, left: 1 << 30}
	total, rate := measureDownload(body, 8*time.Second, func() time.Time { return clock })
	if total != 80*64*1024 {
		t.Fatalf("total = %d", total)
	}
	if rate != 640*1024 {
		t.Fatalf("rate = %d, want %d", rate, 640*1024)
	}
}

func TestMeasureDownloadRatesAShortBodyFromTheStart(t *testing.T) {
	clock := time.Unix(0, 0)
	body := &steadyBody{clock: &clock, chunk: 1000, step: 500 * time.Millisecond, left: 4000}
	total, rate := measureDownload(body, 8*time.Second, func() time.Time { return clock })
	if total != 4000 || rate != 2000 {
		t.Fatalf("total = %d, rate = %d", total, rate)
	}
}

func TestMeasureDownloadReportsNothingForAnEmptyBody(t *testing.T) {
	clock := time.Unix(0, 0)
	body := &steadyBody{clock: &clock}
	if _, rate := measureDownload(body, time.Second, func() time.Time { return clock }); rate != 0 {
		t.Fatalf("rate = %d", rate)
	}
}

func TestSpeedTestDownloadsThroughTheNamedOutbound(t *testing.T) {
	withProbeProxies(t, "node-a")
	payload := make([]byte, 2<<20)
	server := probeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(payload)
	})

	result := handleSpeedTest(&SpeedParams{ProxyName: "node-a", Url: server.URL})
	if result.Error != "" || result.Bytes != int64(len(payload)) || result.BytesPerSecond <= 0 {
		t.Fatalf("result = %+v", result)
	}
}

func TestSpeedTestRefusesAMeteredNetwork(t *testing.T) {
	free := onFreeNetwork
	onFreeNetwork = func() bool { return false }
	defer func() { onFreeNetwork = free }()

	if result := handleSpeedTest(&SpeedParams{ProxyName: "DIRECT"}); result.Error != speedErrorMetered {
		t.Fatalf("result = %+v", result)
	}
}
