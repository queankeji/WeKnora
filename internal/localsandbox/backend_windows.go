//go:build windows

package localsandbox

import (
	"github.com/duhuimeijia/kb-engine/internal/localsandbox/core"
	"github.com/duhuimeijia/kb-engine/internal/localsandbox/winhost"
)

func NewBackend() (core.Backend, error) { return winhost.New() }
