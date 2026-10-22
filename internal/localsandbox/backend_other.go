//go:build !darwin && !windows

package localsandbox

import (
	"context"
	"fmt"

	"github.com/duhuimeijia/kb-engine/internal/localsandbox/core"
	"github.com/duhuimeijia/kb-engine/internal/logger"
)

// NewBackend has no implementation outside macOS and Windows.
func NewBackend() (core.Backend, error) {
	err := fmt.Errorf("%w: only macOS is supported today", core.ErrUnsupportedPlatform)
	logger.Errorf(context.Background(), "[LocalSandbox] %v", err)
	return nil, err
}
