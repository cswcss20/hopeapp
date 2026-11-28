package core

import (
	"context"
	"encoding/json"
	"errors"
	"maps"
	"net/url"
	"reflect"
	"slices"
	"strings"
	"sync"
)

type SourceDescriptor struct {
	ID                 string
	Name               string
	Description        string
	Group              string
	GroupName          string
	EntryName          string
	Adult              bool
	SkipVIPPrompt      bool
	Aliases            []string
	HostSuffixes       []string
	// Hosts 是站源声明的可访问域名（模块清单 hosts 已归一后写在这里），
	// 供 WebView 验证桥接按域名匹配。未声明时为 nil。
	Hosts              []string
	MatchesHost        func(host string) bool
	BaseURL            string
	AllowEmptyCatalog  bool
	NoHostRotation     bool
	KeepDetailEpisodes bool
	ContinuousFeed     bool
	BrowserFingerprint bool
	// CoverAlign 是模組在 manifest 申報的封面裁切方向（"right"/"left"/""），
	// 供前端決定橫幅 DVD 封面在直身卡片的裁切位置。
	CoverAlign string
	// AuthURL 是模組在 manifest 申報的瀏覽器登入/驗證頁地址（跟
	// CoverAlign 同一管線）；前端有此欄位且模組有 account 能力時，
	// 在模組頁顯示瀏覽器登入入口。未申報時為空字串。
	AuthURL string
	// LibraryKinds 是模組在 manifest 申報的帳號收藏種類清單（跟
	// CoverAlign 同一管線）：前端按申報順序在追劇頁「{來源} 收藏」
	// tab 生成子頁。id="favorites" 是協議約定的同步/寫入 kind
	// （拉取存 site list＋詳情頁收藏掣 write-through 對象），其餘
	// kind 即時攞、不存檔。未申報時為 nil，前端預設只有 favorites。
	LibraryKinds []LibraryKind
	// Auth 是模組在 manifest 申報的登入方式（跟 CoverAlign 同一
	// 管線）：前端按申報決定模組頁顯示邊種登入入口（browser
	// 瀏覽器登入／form 表格登入／captcha 滑塊驗證登入）。未申報
	// 時為 nil，前端行舊模組 fallback（authUrl 優先）。
	Auth *ModuleAuth
	// Settings 是模組在 manifest 申報的設定項清單：前端在模組頁
	// 自動生成設定入口同泛用設定頁，值經 host.settings() 交模組
	// 讀取。未申報時為 nil。
	Settings []ModuleSetting
	// DetailActions 是模組在 manifest 申報的詳情頁自訂動作：前端
	// 按申報出掣，撳咗呼叫模組的 detailAction(id, drama) export。
	// 未申報時為 nil。
	DetailActions []ModuleDetailAction
	// BrowserFetch 是模組申報「攞頁要行瀏覽器橋接」：前端在模組
	// 卡自動出「瀏覽器驗證」入口（行 verifySource 自愈流程），
	// 唔使等錯誤先觸發。
	BrowserFetch bool
	// VerifyURL 是模組申報的瀏覽器驗證頁地址：sourceChallengeURL
	// 優先用申報值，冇先用 BaseURL 推斷。
	VerifyURL string
	// CoverAspect 是模組申報的封面卡預設比例（"portrait"/
	// "landscape"）：前端用作該來源 tab 的預設比例，使用者
	// per-tab 設定優先。未申報時為空字串。
	CoverAspect        string
	ValidCategory      func(category string) bool
	Rankings           []RankingBoard
}

// ModuleAuth 是模組申報的登入方式。Type 決定前端入口形態：
// "browser" 用瀏覽器登入頁（URL 為登入頁，SaveMode "auto" 係
// cf_clearance 出現即自動保存、"manual" 係只准手動保存，Bridge
// 決定保存後登記 WebView 橋接與否）；"form" 用泛用表格登入頁
// （Fields 申報欄位，值經 sourceAccount("login", {fieldId: 值})
// 交模組）；"captcha" 用滑塊驗證碼登入頁（RegisterURL 為可選
// 的註冊頁地址）。
type ModuleAuth struct {
	Type        string            `json:"type"`
	URL         string            `json:"url,omitempty"`
	SaveMode    string            `json:"saveMode,omitempty"`
	Bridge      bool              `json:"bridge,omitempty"`
	Fields      []ModuleAuthField `json:"fields,omitempty"`
	RegisterURL string            `json:"registerUrl,omitempty"`
}

// ModuleAuthField 是表格登入的一個欄位申報：ID 是交畀模組的
// payload key，Label 是前端顯示名，Type 只認 "text"/"password"。
type ModuleAuthField struct {
	ID       string `json:"id"`
	Label    string `json:"label"`
	Type     string `json:"type"`
	Required bool   `json:"required,omitempty"`
	Hint     string `json:"hint,omitempty"`
}

// normalizeModuleAuth 清理模組申報的登入方式：Type 只認
// browser/form/captcha，其餘當未申報（nil）；browser 的 SaveMode
// 只認 "auto"，其餘一律 "manual"；form 欄位去空白、丟空 id、
// 按 id 去重、Label 缺省用 ID、Type 只認 "password"，其餘 "text"；
// form 冇有效欄位時當未申報。
func normalizeModuleAuth(in *ModuleAuth) *ModuleAuth {
	if in == nil {
		return nil
	}
	auth := &ModuleAuth{
		Type:        strings.TrimSpace(in.Type),
		URL:         strings.TrimSpace(in.URL),
		RegisterURL: strings.TrimSpace(in.RegisterURL),
	}
	switch auth.Type {
	case "browser":
		auth.SaveMode = "manual"
		if strings.TrimSpace(in.SaveMode) == "auto" {
			auth.SaveMode = "auto"
		}
		auth.Bridge = in.Bridge
	case "form":
		seen := map[string]bool{}
		for _, field := range in.Fields {
			id := strings.TrimSpace(field.ID)
			if id == "" || seen[id] {
				continue
			}
			seen[id] = true
			label := strings.TrimSpace(field.Label)
			if label == "" {
				label = id
			}
			fieldType := "text"
			if strings.TrimSpace(field.Type) == "password" {
				fieldType = "password"
			}
			auth.Fields = append(auth.Fields, ModuleAuthField{
				ID: id, Label: label, Type: fieldType,
				Required: field.Required, Hint: strings.TrimSpace(field.Hint),
			})
		}
		if len(auth.Fields) == 0 {
			return nil
		}
	case "captcha":
	default:
		return nil
	}
	return auth
}

// ModuleSetting 是模組申報的一個設定項：ID 是 host.settings()
// 回傳物件的 key，Label 是前端顯示名，Type 只認
// "text"/"toggle"/"select"，Default 是未設定時的預設值（text/
// select 為字串、toggle 為布林），Options 是 select 的選項清單。
type ModuleSetting struct {
	ID      string               `json:"id"`
	Label   string               `json:"label"`
	Type    string               `json:"type"`
	Default any                  `json:"default,omitempty"`
	Options []ModuleSettingOption `json:"options,omitempty"`
}

// ModuleSettingOption 是 select 設定的一個選項：ID 是存入的值，
// Name 是前端顯示名（缺省用 ID）。
type ModuleSettingOption struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// normalizeModuleSettings 清理模組申報的設定項：去空白、丟空
// id、按 id 去重、Label 缺省用 ID、Type 只認 toggle/select，
// 其餘一律 text；select 冇有效選項時降級做 text。
func normalizeModuleSettings(in []ModuleSetting) []ModuleSetting {
	seen := map[string]bool{}
	var out []ModuleSetting
	for _, setting := range in {
		id := strings.TrimSpace(setting.ID)
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		label := strings.TrimSpace(setting.Label)
		if label == "" {
			label = id
		}
		settingType := "text"
		switch strings.TrimSpace(setting.Type) {
		case "toggle":
			settingType = "toggle"
		case "select":
			settingType = "select"
		}
		var options []ModuleSettingOption
		if settingType == "select" {
			optionSeen := map[string]bool{}
			for _, option := range setting.Options {
				optionID := strings.TrimSpace(option.ID)
				if optionID == "" || optionSeen[optionID] {
					continue
				}
				optionSeen[optionID] = true
				name := strings.TrimSpace(option.Name)
				if name == "" {
					name = optionID
				}
				options = append(options, ModuleSettingOption{ID: optionID, Name: name})
			}
			if len(options) == 0 {
				settingType = "text"
			}
		}
		out = append(out, ModuleSetting{
			ID: id, Label: label, Type: settingType,
			Default: setting.Default, Options: options,
		})
	}
	return out
}

// ModuleDetailAction 是模組申報的一個詳情頁自訂動作：ID 是呼叫
// 模組 detailAction(id, drama) 時的動作標識，Label 是前端掣名。
type ModuleDetailAction struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

// normalizeDetailActions 清理模組申報的詳情頁動作：去空白、丟
// 空 id、按 id 去重、Label 缺省用 ID。
func normalizeDetailActions(in []ModuleDetailAction) []ModuleDetailAction {
	seen := map[string]bool{}
	var out []ModuleDetailAction
	for _, action := range in {
		id := strings.TrimSpace(action.ID)
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		label := strings.TrimSpace(action.Label)
		if label == "" {
			label = id
		}
		out = append(out, ModuleDetailAction{ID: id, Label: label})
	}
	return out
}

// normalizeCoverAspect 只認 "portrait"/"landscape"，其餘回空。
func normalizeCoverAspect(in string) string {
	switch strings.TrimSpace(in) {
	case "portrait", "landscape":
		return strings.TrimSpace(in)
	}
	return ""
}

// LibraryKind 是模組申報的一個帳號收藏種類：ID 是 libraryItems 的
// kind 參數，Name 是前端子頁標籤（缺省用 ID），Style 是渲染方式
// （"cover" 標準封面卡格／"avatar" 圓形頭像格，未知值當 "cover"）。
type LibraryKind struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Style string `json:"style"`
}

// normalizeLibraryKinds 清理模組申報的收藏種類：去空白、丟空 id、
// 按 id 去重（保留首次申報次序）、Name 缺省用 ID、Style 只認
// "avatar"，其餘一律 "cover"。
func normalizeLibraryKinds(in []LibraryKind) []LibraryKind {
	seen := map[string]bool{}
	var out []LibraryKind
	for _, kind := range in {
		id := strings.TrimSpace(kind.ID)
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		name := strings.TrimSpace(kind.Name)
		if name == "" {
			name = id
		}
		style := "cover"
		if strings.TrimSpace(kind.Style) == "avatar" {
			style = "avatar"
		}
		out = append(out, LibraryKind{ID: id, Name: name, Style: style})
	}
	return out
}

type Provider interface {
	Descriptor() SourceDescriptor
	Categories(ctx context.Context, force bool) ([]Category, error)
	CatalogPage(ctx context.Context, page int, category string) ([]Drama, bool, error)
	Detail(ctx context.Context, sourceID string) (Drama, []Chapter, error)
	ResolveMedia(ctx context.Context, task Task) (ProviderMedia, error)
}

var ErrSourceLogin = errors.New("站源需要登录")

type SourceLoginError string

func (err SourceLoginError) Error() string { return string(err) }

func (err SourceLoginError) Is(target error) bool { return target == ErrSourceLogin }

type Sited interface {
	BaseURL() string
}

type URLRotator interface {
	URLCandidates(rawURL string) []string
}

type CoverRepairer interface {
	RepairCover(drama LibraryDrama) string
}

type MediaAuthorizer interface {
	AuthorizesMedia(address *url.URL) bool
	MediaAuthorization(ctx context.Context, address *url.URL, referer string) (header, value string, err error)
	RejectMediaAuthorization(address *url.URL, value string)
}

type Searcher interface {
	Search(ctx context.Context, page int, query string) ([]Drama, bool, error)
}

type WarningSearcher interface {
	SearchWithWarning(ctx context.Context, page int, query string) ([]Drama, bool, string, error)
}

type FilterOption struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type FilterGroup struct {
	ID      string         `json:"id"`
	Name    string         `json:"name"`
	Options []FilterOption `json:"options"`
}

// FilterProvider is an optional provider capability: the module exports
// filters(category) and returns the filter groups for a catalog category.
// It is asserted directly (not via providerAs) because modules do not
// declare it in their manifest capabilities.
type FilterProvider interface {
	Filters(ctx context.Context, category string) ([]FilterGroup, error)
}

// FilteredCataloger is an optional provider capability: the module's
// catalogPage accepts the user's filter picks as a third argument.
type FilteredCataloger interface {
	CatalogPageFiltered(ctx context.Context, page int, category string, filters map[string]string) ([]Drama, bool, error)
}

// FilteredSearcher is an optional provider capability: the module's
// search accepts the user's filter picks as a third argument. Asserted
// directly (not via providerAs), like FilteredCataloger, because modules
// do not declare it in their manifest capabilities.
type FilteredSearcher interface {
	SearchFiltered(ctx context.Context, page int, query string, filters map[string]string) ([]Drama, bool, error)
}

// FilteredWarningSearcher is the warning-carrying counterpart of
// FilteredSearcher, mirroring WarningSearcher.
type FilteredWarningSearcher interface {
	SearchWithWarningFiltered(ctx context.Context, page int, query string, filters map[string]string) ([]Drama, bool, string, error)
}

type CatalogStateful interface {
	CatalogState() json.RawMessage
	RestoreCatalogState(raw json.RawMessage)
}

type LibraryMoreKey struct{}

type LibraryKnownKey struct{}

type Suggester interface {
	Suggestions(ctx context.Context, query string) ([]string, error)
}

type RecommendationPage struct {
	Dramas  []Drama
	Cursor  json.RawMessage
	HasMore bool
}

type Recommender interface {
	ValidRecommendation(genre string, cursor json.RawMessage) error
	Recommendations(ctx context.Context, genre string, cursor json.RawMessage, seen []string) (RecommendationPage, error)
}

type DanmakuItem struct {
	ID     string `json:"id"`
	Text   string `json:"text"`
	TimeMS int64  `json:"timeMs"`
}

type DanmakuPage struct {
	EpisodeID string        `json:"episodeId"`
	Items     []DanmakuItem `json:"items"`
	StartMS   int64         `json:"startMs"`
	NextMS    int64         `json:"nextMs"`
	Total     int64         `json:"total"`
}

type DanmakuProvider interface {
	DanmakuIDs(task Task) (series, video string, ok bool)
	Danmaku(ctx context.Context, series, video string, startMS, durationMS int64) (DanmakuPage, error)
}

type DeviceProvider interface {
	Devices(ctx context.Context, register bool) (bool, error)
}

type AccountProvider interface {
	Account(ctx context.Context, command string, payload json.RawMessage) (any, error)
}

// LibraryProvider 是模組申報的站方個人收藏能力（manifest capability
// "library"）：LibraryItems 分頁回傳站方收藏列表（kind 區分
// favorites 等收藏種類），供前端同步引擎合併入本地追劇；
// LibraryWrite 將本地新增/移除推送回站方。寫入未實作時模組應拋
// 帶 notImplemented 標記的錯誤（見 ErrLibraryWriteUnsupported），
// 同步引擎會保留本地狀態下次再試，絕不丟失本地收藏。
type LibraryProvider interface {
	LibraryItems(ctx context.Context, kind string, page int) ([]Drama, bool, error)
	LibraryWrite(ctx context.Context, kind string, drama LibraryDrama, add bool) error
}

// DetailActionResult 是模組 detailAction 的回傳：OK 表示動作
// 成功，Message 是前端 snackbar 顯示的訊息（可空）。
type DetailActionResult struct {
	OK      bool   `json:"ok"`
	Message string `json:"message,omitempty"`
}

// DetailActioner 是模組的詳情頁自訂動作能力（manifest 申報
// detailActions，非 capability 字串，跟 FilterProvider 一樣
// 直接 assert）：前端按申報出掣，撳咗呼叫模組的
// detailAction(id, drama) export。
type DetailActioner interface {
	DetailAction(ctx context.Context, actionID string, drama LibraryDrama) (DetailActionResult, error)
}

var ErrLibraryWriteUnsupported = errors.New("站源未支援寫入收藏")

type LibraryWriteUnsupportedError string

func (err LibraryWriteUnsupportedError) Error() string { return string(err) }

func (err LibraryWriteUnsupportedError) Is(target error) bool {
	return target == ErrLibraryWriteUnsupported
}

type Ranker interface {
	RankingPage(ctx context.Context, board RankingBoard, page int) (RankingPage, error)
}

type CoverResolver interface {
	CoverAddress(ctx context.Context, drama LibraryDrama, sourceID string) (string, error)
}

type CoverRefererProvider interface {
	CoverReferer(address string) string
}

type MetadataEnricher interface {
	NeedsExtraMetadata(drama LibraryDrama) bool
	ExtraMetadata(ctx context.Context, drama LibraryDrama, sourceID string) (LibraryDrama, error)
}

type Season struct {
	Number int
	Drama  Drama
}

type SeasonProvider interface {
	Seasons(ctx context.Context, sourceID string) ([]Season, error)
}

var ErrCategoriesIncomplete = errors.New("categories incomplete")

type ProviderFactory func(host Host) Provider

type CapabilityLimiter interface {
	ProvidesCapability(capability reflect.Type) bool
}

func providerAs[T any](p Provider) (T, bool) {
	capability, ok := p.(T)
	if limiter, limited := p.(CapabilityLimiter); ok && limited && !limiter.ProvidesCapability(reflect.TypeFor[T]()) {
		var none T
		return none, false
	}
	return capability, ok
}

var providerRegistry = struct {
	sync.RWMutex
	factories   map[string]ProviderFactory
	descriptors map[string]SourceDescriptor
	aliases     map[string]string
	revisions   map[string]uint64
	order       []string
}{factories: map[string]ProviderFactory{}, descriptors: map[string]SourceDescriptor{}, aliases: map[string]string{}, revisions: map[string]uint64{}}

func Unregister(source string) {
	id := strings.ToLower(strings.TrimSpace(source))
	providerRegistry.Lock()
	defer providerRegistry.Unlock()
	if _, ok := providerRegistry.factories[id]; !ok {
		return
	}
	delete(providerRegistry.factories, id)
	delete(providerRegistry.descriptors, id)
	maps.DeleteFunc(providerRegistry.aliases, func(_, target string) bool { return target == id })
	providerRegistry.revisions[id]++
}

func Register(descriptor SourceDescriptor, factory ProviderFactory) {
	id := strings.ToLower(strings.TrimSpace(descriptor.ID))
	if id == "" || factory == nil {
		panic("core.Register: empty source id or nil factory")
	}
	descriptor.ID = id
	providerRegistry.Lock()
	defer providerRegistry.Unlock()
	if _, dup := providerRegistry.factories[id]; dup {
		panic("core.Register: duplicate source " + id)
	}
	registerProviderLocked(id, descriptor, factory)
}

func Replace(descriptor SourceDescriptor, factory ProviderFactory) {
	id := strings.ToLower(strings.TrimSpace(descriptor.ID))
	if id == "" || factory == nil {
		panic("core.Replace: empty source id or nil factory")
	}
	descriptor.ID = id
	providerRegistry.Lock()
	defer providerRegistry.Unlock()
	if _, existed := providerRegistry.factories[id]; existed {
		maps.DeleteFunc(providerRegistry.aliases, func(_, target string) bool { return target == id })
		providerRegistry.revisions[id]++
	}
	registerProviderLocked(id, descriptor, factory)
}

func registerProviderLocked(id string, descriptor SourceDescriptor, factory ProviderFactory) {
	providerRegistry.factories[id] = factory
	providerRegistry.descriptors[id] = descriptor
	if !slices.Contains(providerRegistry.order, id) {
		providerRegistry.order = append(providerRegistry.order, id)
	}
	providerRegistry.aliases[id] = id
	for _, alias := range descriptor.Aliases {
		providerRegistry.aliases[strings.ToLower(strings.TrimSpace(alias))] = id
	}
}

func registeredSource(alias string) (string, bool) {
	providerRegistry.RLock()
	defer providerRegistry.RUnlock()
	alias = strings.ToLower(strings.TrimSpace(alias))
	if id, ok := providerRegistry.aliases[alias]; ok {
		return id, true
	}
	for id, descriptor := range providerRegistry.descriptors {
		for _, suffix := range descriptor.HostSuffixes {
			if strings.HasSuffix(alias, suffix) {
				return id, true
			}
		}
		if descriptor.MatchesHost != nil && descriptor.MatchesHost(alias) {
			return id, true
		}
	}
	return "", false
}

func registeredDescriptors() []SourceDescriptor {
	providerRegistry.RLock()
	defer providerRegistry.RUnlock()
	out := make([]SourceDescriptor, 0, len(providerRegistry.order))
	for _, id := range providerRegistry.order {
		if descriptor, ok := providerRegistry.descriptors[id]; ok {
			out = append(out, descriptor)
		}
	}
	return out
}

func registeredDescriptor(source string) (SourceDescriptor, bool) {
	providerRegistry.RLock()
	defer providerRegistry.RUnlock()
	descriptor, ok := providerRegistry.descriptors[source]
	return descriptor, ok
}

func (d *Downloader) provider(source string) (Provider, bool) {
	source = canonicalProviderSource(source)
	d.providersMu.Lock()
	defer d.providersMu.Unlock()
	providerRegistry.RLock()
	factory, ok := providerRegistry.factories[source]
	revision := providerRegistry.revisions[source]
	providerRegistry.RUnlock()
	if p, cached := d.providers[source]; cached && d.providerRevisions[source] == revision {
		return p, true
	}
	if !ok {
		delete(d.providers, source)
		return nil, false
	}
	if d.providers == nil {
		d.providers = map[string]Provider{}
	}
	if d.providerRevisions == nil {
		d.providerRevisions = map[string]uint64{}
	}
	p := factory(d)
	d.providers[source] = p
	d.providerRevisions[source] = revision
	return p, true
}

func ProviderDramaID(source, sourceID string) string {
	return source + ":" + strings.TrimSpace(sourceID)
}

func ProviderChapterID(source, sourceID, chapterKey string) string {
	return source + ":" + strings.TrimSpace(sourceID) + ":" + strings.TrimSpace(chapterKey)
}

func SplitProviderDramaID(id string) (source, sourceID string, ok bool) {
	source, sourceID, ok = strings.Cut(strings.TrimSpace(id), ":")
	source = canonicalProviderSource(source)
	if !ok || strings.TrimSpace(sourceID) == "" || !registeredProviderSource(source) {
		return "", "", false
	}
	return source, strings.TrimSpace(sourceID), true
}

func registeredProviderSource(source string) bool {
	_, ok := registeredDescriptor(canonicalProviderSource(source))
	return ok
}

func canonicalProviderSource(source string) string {
	trimmed := strings.ToLower(strings.TrimSpace(source))
	if id, ok := registeredSource(trimmed); ok {
		return id
	}
	return strings.TrimSpace(source)
}
