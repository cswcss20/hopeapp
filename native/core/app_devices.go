package core

import (
	"context"
	"errors"
	"strings"
)

func (engine *nativeEngine) sourceDevices(ctx context.Context, source string, register bool) (map[string]any, error) {
	if !nativeSourceAvailable(source) {
		return map[string]any{"ready": true}, nil
	}
	p, ok := engine.downloader.provider(source)
	if !ok {
		return map[string]any{"ready": true}, nil
	}
	devices, ok := providerAs[DeviceProvider](p)
	if !ok {
		return map[string]any{"ready": true}, nil
	}
	ready, err := devices.Devices(ctx, register)
	if err != nil {
		return nil, err
	}
	if register {
		engine.mu.Lock()
		engine.commitProviderStateLocked(source)
		err := engine.writeCatalogDiskLocked()
		engine.mu.Unlock()
		if err != nil {
			return nil, err
		}
	}
	return map[string]any{"ready": ready}, nil
}

func (engine *nativeEngine) sourceAccount(ctx context.Context, source, command string, payload []byte) (any, error) {
	p, ok := engine.downloader.provider(source)
	if !ok {
		return nil, errNativeBuildSource
	}
	account, ok := providerAs[AccountProvider](p)
	if !ok {
		return nil, errNativeBuildSource
	}
	return account.Account(ctx, command, payload)
}

// detailAction 執行模組申報的詳情頁自訂動作：來源由 drama id
// 推斷（跟 libraryWrite 一致），動作標識經 input.Command 傳入。
func (engine *nativeEngine) detailAction(ctx context.Context, input nativeInput) (any, error) {
	source, _, valid := SplitProviderDramaID(input.Drama.ID)
	if !valid {
		return nil, errors.New("剧集信息无效")
	}
	p, ok := engine.downloader.provider(source)
	if !ok {
		return nil, errNativeBuildSource
	}
	actioner, ok := p.(DetailActioner)
	if !ok {
		return nil, errNativeBuildSource
	}
	result, err := actioner.DetailAction(ctx, strings.TrimSpace(input.Command), input.Drama)
	if err != nil {
		return nil, err
	}
	return result, nil
}
