package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/duhuimeijia/kb-engine/cli/internal/cmdutil"
	"github.com/duhuimeijia/kb-engine/cli/internal/config"
	"github.com/duhuimeijia/kb-engine/cli/internal/iostreams"
	sdk "github.com/duhuimeijia/kb-engine/client"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestStatusJQPreservesTenantID(t *testing.T) {
	out, _ := iostreams.SetForTest(t)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/api/v1/auth/me", r.URL.Path)
		_, _ = w.Write([]byte(`{"success":true,"data":{"user":{"id":"user-test","tenant_id":9007199254740993}}}`))
	}))
	defer server.Close()
	f := &cmdutil.Factory{Config: func() (*config.Config, error) {
		return &config.Config{CurrentProfile: "test", Profiles: map[string]config.Profile{
			"test": {Host: server.URL},
		}}, nil
	}}
	require.NoError(t, runStatus(context.Background(),
		&cmdutil.FormatOptions{Mode: cmdutil.FormatJSON, JQ: ".data.tenant_id"}, f, sdk.NewClient(server.URL)))
	assert.Equal(t, "9007199254740993\n", out.String())
}
