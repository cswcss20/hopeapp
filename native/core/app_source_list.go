package core

type nativeSourceInfo struct {
	ID              string `json:"id"`
	Name            string `json:"name"`
	Description     string `json:"description"`
	Group           string `json:"group"`
	GroupName       string `json:"groupName"`
	EntryName       string `json:"entryName"`
	Available       bool   `json:"available"`
	Search          bool   `json:"search"`
	Suggestions     bool   `json:"suggestions"`
	Recommendations bool   `json:"recommendations"`
	Danmaku         bool   `json:"danmaku"`
	Devices         bool   `json:"devices"`
	Account         bool   `json:"account"`
	Metadata        bool   `json:"metadata"`
	Library         bool   `json:"library"`
	Adult           bool   `json:"adult"`
	VIPPrompt       bool   `json:"vipPrompt"`
	CoverAlign      string               `json:"coverAlign,omitempty"`
	AuthURL         string               `json:"authUrl,omitempty"`
	LibraryKinds    []LibraryKind        `json:"libraryKinds,omitempty"`
	BaseURL         string               `json:"baseUrl,omitempty"`
	Hosts           []string             `json:"hosts,omitempty"`
	Auth            *ModuleAuth          `json:"auth,omitempty"`
	Settings        []ModuleSetting      `json:"settings,omitempty"`
	DetailActions   []ModuleDetailAction `json:"detailActions,omitempty"`
	BrowserFetch    bool                 `json:"browserFetch,omitempty"`
	VerifyURL       string               `json:"verifyUrl,omitempty"`
	CoverAspect     string               `json:"coverAspect,omitempty"`
	Live            bool                 `json:"live,omitempty"`
	LivePublic      bool                 `json:"livePublic,omitempty"`
}

func (engine *nativeEngine) sourceList() []nativeSourceInfo {
	registered := registeredDescriptors()
	list := make([]nativeSourceInfo, 0, len(registered))
	for _, descriptor := range registered {
		id := descriptor.ID
		p, ok := engine.downloader.provider(id)
		if !ok {
			continue
		}
		info := nativeSourceInfo{
			ID: id, Name: descriptor.Name, Description: descriptor.Description,
			Group: descriptor.Group, GroupName: descriptor.GroupName, EntryName: descriptor.EntryName,
			Available: nativeSourceAvailable(id), VIPPrompt: !descriptor.SkipVIPPrompt, Adult: descriptor.Adult,
			CoverAlign: descriptor.CoverAlign, AuthURL: descriptor.AuthURL, LibraryKinds: descriptor.LibraryKinds,
			BaseURL: descriptor.BaseURL, Hosts: descriptor.Hosts, Auth: descriptor.Auth, Settings: descriptor.Settings,
			DetailActions: descriptor.DetailActions, BrowserFetch: descriptor.BrowserFetch, VerifyURL: descriptor.VerifyURL,
			CoverAspect: descriptor.CoverAspect, Live: descriptor.Live, LivePublic: descriptor.LivePublic,
		}
		_, search := providerAs[Searcher](p)
		_, warningSearch := providerAs[WarningSearcher](p)
		info.Search = search || warningSearch
		_, info.Suggestions = providerAs[Suggester](p)
		_, info.Recommendations = providerAs[Recommender](p)
		_, info.Danmaku = providerAs[DanmakuProvider](p)
		_, info.Devices = providerAs[DeviceProvider](p)
		_, info.Account = providerAs[AccountProvider](p)
		_, info.Metadata = providerAs[MetadataEnricher](p)
		_, info.Library = providerAs[LibraryProvider](p)
		list = append(list, info)
	}
	return list
}
