package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"strings"
)

// nativeUpdateServer keeps the legacy self-hosted update endpoint
// ({server}/v1/latest) as an optional fallback. It stays empty in
// Hopeapp builds: GitHub Releases is the update source.
var nativeUpdateServer = ""

var nativeProjectURL = "https://github.com/cswcss20/hopeapp"

const nativeUpdateRepo = "cswcss20/hopeapp"

var nativeAppVersionPattern = regexp.MustCompile(`^\d+\.\d+\.\d+\+(\d+)$`)

type nativeUpdateAsset struct {
	Name   string `json:"name"`
	URL    string `json:"url"`
	Size   int64  `json:"size"`
	Digest string `json:"digest,omitempty"`
}

type nativeUpdate struct {
	Available bool                `json:"available"`
	Version   string              `json:"version,omitempty"`
	URL       string              `json:"url,omitempty"`
	Assets    []nativeUpdateAsset `json:"assets,omitempty"`
}

func nativeUpdateServers() []string {
	servers := []string{}
	for _, server := range strings.Split(nativeUpdateServer, ",") {
		if server = strings.TrimRight(strings.TrimSpace(server), "/"); server != "" {
			servers = append(servers, server)
		}
	}
	return servers
}

func nativeReleasePrefix() string {
	project := strings.TrimRight(strings.TrimSpace(nativeProjectURL), "/")
	if project == "" {
		return ""
	}
	return project + "/releases/"
}

func nativeAssetPrefix() string {
	return nativeReleasePrefix() + "download/"
}

func nativeAppBuildNumber(version string) (int, bool) {
	match := nativeAppVersionPattern.FindStringSubmatch(version)
	if match == nil {
		return 0, false
	}
	number, err := strconv.Atoi(match[1])
	return number, err == nil
}

func (engine *nativeEngine) checkUpdate(ctx context.Context, version string) (nativeUpdate, error) {
	current, valid := nativeAppBuildNumber(version)
	if !valid {
		return nativeUpdate{}, errors.New("应用版本号无效")
	}
	latest, err := engine.fetchGitHubLatest(ctx)
	if err != nil {
		// Fall back to a configured legacy update server, if any.
		for _, server := range nativeUpdateServers() {
			if legacy, legacyErr := engine.fetchLatest(ctx, server); legacyErr == nil {
				latest, err = legacy, nil
				break
			} else if ctx.Err() != nil {
				break
			}
		}
	}
	if err != nil {
		return nativeUpdate{}, fmt.Errorf("更新服务器请求失败：%w", err)
	}
	number, valid := nativeAppBuildNumber(latest.Version)
	if !valid {
		return nativeUpdate{}, errors.New("更新服务器没有返回有效的版本号")
	}
	if number <= current {
		return nativeUpdate{}, nil
	}
	prefix := nativeReleasePrefix()
	if prefix == "" {
		return nativeUpdate{}, errors.New("这个安装包没有配置项目地址，无法确认新版本的发布页")
	}
	if !strings.HasPrefix(latest.URL, prefix) {
		return nativeUpdate{}, errors.New("更新服务器返回的发布页不属于本项目，已忽略")
	}
	assetPrefix := nativeAssetPrefix()
	assets := make([]nativeUpdateAsset, 0, len(latest.Assets))
	for _, asset := range latest.Assets {
		if strings.HasPrefix(asset.URL, assetPrefix) {
			assets = append(assets, asset)
		}
	}
	return nativeUpdate{
		Available: true,
		Version:   latest.Version,
		URL:       latest.URL,
		Assets:    assets,
	}, nil
}

type githubRelease struct {
	TagName string `json:"tag_name"`
	HTMLURL string `json:"html_url"`
	Assets  []struct {
		Name               string `json:"name"`
		BrowserDownloadURL string `json:"browser_download_url"`
		Size               int64  `json:"size"`
		Digest             string `json:"digest"`
	} `json:"assets"`
}

func (engine *nativeEngine) fetchGitHubLatest(ctx context.Context) (nativeUpdate, error) {
	endpoint := "https://api.github.com/repos/" + nativeUpdateRepo + "/releases/latest"
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nativeUpdate{}, err
	}
	request.Header.Set("Accept", "application/vnd.github+json")
	request.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	request.Header.Set("User-Agent", UserAgent)
	response, err := engine.downloader.client.Do(request)
	if err != nil {
		return nativeUpdate{}, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nativeUpdate{}, fmt.Errorf("检查更新失败：HTTP %d", response.StatusCode)
	}
	var release githubRelease
	if err := json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&release); err != nil {
		return nativeUpdate{}, err
	}
	latest := nativeUpdate{
		Version: strings.TrimPrefix(strings.TrimSpace(release.TagName), "v"),
		URL:     release.HTMLURL,
	}
	for _, asset := range release.Assets {
		latest.Assets = append(latest.Assets, nativeUpdateAsset{
			Name:   asset.Name,
			URL:    asset.BrowserDownloadURL,
			Size:   asset.Size,
			Digest: asset.Digest,
		})
	}
	return latest, nil
}

func (engine *nativeEngine) fetchLatest(ctx context.Context, server string) (nativeUpdate, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, server+"/v1/latest", nil)
	if err != nil {
		return nativeUpdate{}, err
	}
	response, err := engine.downloader.client.Do(request)
	if err != nil {
		return nativeUpdate{}, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nativeUpdate{}, fmt.Errorf("检查更新失败：HTTP %d", response.StatusCode)
	}
	var latest nativeUpdate
	return latest, json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(&latest)
}
