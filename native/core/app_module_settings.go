package core

import (
	"encoding/json"
	"maps"
	"os"
	"path/filepath"
)

// 模組設定值存儲：前端 LocalStore 係真相來源（入備份），經
// moduleSettings action 將成份 map 同步入核心；核心同時持久化
// 到 module-settings.json 做重啟後備。JS 模組經 host.settings()
// 讀取（manifest 申報的預設值墊底，使用者設定覆蓋）。

func (d *Downloader) setModuleSettings(values map[string]map[string]any) {
	d.moduleSettingsMu.Lock()
	defer d.moduleSettingsMu.Unlock()
	d.moduleSettings = values
}

func (d *Downloader) moduleSettingsFor(source string) map[string]any {
	d.moduleSettingsMu.RLock()
	defer d.moduleSettingsMu.RUnlock()
	return maps.Clone(d.moduleSettings[source])
}

func (engine *nativeEngine) loadModuleSettings() {
	file := filepath.Join(engine.directory, "module-settings.json")
	data, err := os.ReadFile(file)
	if err != nil {
		return
	}
	var values map[string]map[string]any
	if json.Unmarshal(data, &values) == nil && values != nil {
		engine.downloader.setModuleSettings(values)
	}
}

func (engine *nativeEngine) syncModuleSettings(values map[string]map[string]any) error {
	if values == nil {
		values = map[string]map[string]any{}
	}
	engine.downloader.setModuleSettings(values)
	data, err := json.Marshal(values)
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(engine.directory, "module-settings.json"), data, 0o600)
}
