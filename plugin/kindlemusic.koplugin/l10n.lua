--[[--
Tiny translation layer. The plugin is written in English; other languages are lookup tables
keyed by the English text. Placeholders %1, %2… are filled in after translation.

Language setting (Settings → Language): "en" (default), "pl", or "auto" (follow KOReader).

To add a language: copy the `pl` table below, translate the values, add it to LANGS and NAMES.

@module l10n
--]]

local L10n = { lang = "en" }

local pl = {
    -- remote
    ["No speakers"] = "Brak głośników",
    ["Group rooms…"] = "Grupuj pokoje…",
    ["Other devices…"] = "Inne urządzenia…",
    ["Find speakers"] = "Szukaj głośników",
    ["▶ Playing"] = "▶ Gra",
    ["Paused"] = "Pauza",
    ["Stopped"] = "Zatrzymane",
    ["Loading…"] = "Ładowanie…",
    ["Pause"] = "Pauza",
    ["Play"] = "Graj",
    ["Vol. %1"] = "Gł. %1",
    ["Shuffle: %1"] = "Losowo: %1",
    ["on"] = "wł.",
    ["off"] = "wył.",
    ["all"] = "wszystko",
    ["track"] = "utwór",
    ["Repeat: %1"] = "Powtarzaj: %1",
    ["Sleep timer: %1"] = "Wyłącznik: %1",
    ["Radio: %1"] = "Radio: %1",
    ["Sonos favorites"] = "Ulubione Sonos",
    ["Refresh"] = "Odśwież",
    ["Settings"] = "Ustawienia",
    ["Now playing on: %1"] = "Teraz gra na: %1",
    ["Nothing is playing"] = "Nic nie gra",
    ["computer"] = "komputer",
    ["phone"] = "telefon",
    ["speaker"] = "głośnik",
    ["tablet"] = "tablet",
    ["car"] = "auto",
    ["AV receiver"] = "amplituner",
    ["set-top box"] = "dekoder",
    ["no remote control"] = "bez sterowania",
    ["No other Spotify devices.\nThe device must be on and have Spotify open\n(TV, computer, phone, speaker)."] =
        "Brak innych urządzeń Spotify.\nUrządzenie musi być włączone i mieć otwarte Spotify\n(TV, komputer, telefon, głośnik).",
    ["Close"] = "Zamknij",
    ["Other devices (Spotify Connect)"] = "Inne urządzenia (Spotify Connect)",
    ["No favorites or playlists.\n\nIn the Sonos app, add playlists (e.g. from Spotify) to Favorites (My Sonos) and open this list again."] =
        "Brak ulubionych i playlist.\n\nW aplikacji Sonos dodaj playlisty (np. ze Spotify) do „Ulubione” (Moje Sonos) i otwórz tę listę ponownie.",
    ["Playlists — %1"] = "Playlisty — %1",
    ["This Kindle is not linked to Spotify.\n\nOn your computer run:\npython3 tools/link_spotify.py <Kindle IP>\nand sign in with your Spotify account."] =
        "Ten Kindle nie jest połączony ze Spotify.\n\nNa komputerze uruchom:\npython3 tools/link_spotify.py <IP Kindla>\ni zaloguj się swoim kontem Spotify.",
    ["Starting…"] = "Uruchamiam…",
    ["%1: volume lowered %2 → %3 (to match the group)"] = "%1: obniżono głośność %2 → %3 (jak w grupie)",
    ["Done"] = "Gotowe",
    ["Room volumes in this group"] = "Głośność pokoi w grupie",
    ["main"] = "główny",
    ["All rooms"] = "Wszystkie pokoje",
    ["Ungroup"] = "Rozgrupuj",
    ["Volume of each room…"] = "Głośność poszczególnych pokoi…",
    ["Playing together with: %1\nTick the rooms that should play the same music."] =
        "Grają razem z: %1\nZaznacz pokoje, które mają grać to samo.",
    ["The sleep timer only works with Sonos speakers"] = "Wyłącznik czasowy działa tylko z głośnikami Sonos",
    ["Music will stop in %1 min"] = "Muzyka wyłączy się za %1 min",
    ["Sleep timer off"] = "Wyłącznik czasowy wyłączony",
    ["Go back to the Kindle home screen?"] = "Wrócić do ekranu głównego Kindle?",
    ["Exit"] = "Wyjdź",
    ["Stay in KOReader"] = "Zostań w KOReader",
    -- playback
    ["No liked songs"] = "Brak polubionych utworów",
    ["Unsupported content type"] = "Nieobsługiwany typ treści",
    ["Spotify can't see the speaker “%1”"] = "Spotify nie widzi głośnika „%1”",
    ["Radio only works on Sonos speakers (Spotify doesn't offer radio through its API)"] =
        "Radio działa tylko na głośnikach Sonos (Spotify nie udostępnia radia przez API)",
    -- accounts and settings
    ["Active Spotify account: %1"] = "Aktywne konto Spotify: %1",
    ["Remove"] = "Usuń",
    ["Remove the Spotify account “%1” from this Kindle?\n\nYou can also revoke access at spotify.com → Account → Apps."] =
        "Usunąć konto Spotify „%1” z tego Kindla?\n\nDostęp możesz też odwołać na spotify.com → Konto → Aplikacje.",
    ["+ Add account…"] = "+ Dodaj konto…",
    ["To add a Spotify account to this Kindle, run on your computer:\n\npython3 tools/link_spotify.py <Kindle IP>\n\nand sign in with that account. The account must be added in the Spotify dashboard (User Management, max. 5 people), and for playback through Sonos also in the Sonos app.\nThen restart KOReader."] =
        "Aby dodać konto Spotify do tego Kindla, na komputerze uruchom:\n\npython3 tools/link_spotify.py <IP Kindla>\n\ni zaloguj się tym kontem. Konto musi być dodane w panelu Spotify (User Management, maks. 5 osób), a do odtwarzania przez Sonosa także w aplikacji Sonos.\nPotem zrestartuj KOReader.",
    ["Spotify accounts on this Kindle"] = "Konta Spotify na tym Kindlu",
    ["No linked Spotify accounts"] = "Brak połączonych kont Spotify",
    ["Looking for Sonos speakers on the network…"] = "Szukam głośników Sonos w sieci…",
    ["No Sonos speakers found on this network"] = "Nie znaleziono głośników Sonos w tej sieci",
    ["New system: %1\nGroups: %2"] = "Nowy system: %1\nGrup: %2",
    ["System: %1\nGroups: %2"] = "System: %1\nGrup: %2",
    ["System: %1"] = "System: %1",
    ["not found"] = "nie wykryto",
    ["Rename system…"] = "Zmień nazwę systemu…",
    ["Sonos system name"] = "Nazwa systemu Sonos",
    ["Cancel"] = "Anuluj",
    ["Save"] = "Zapisz",
    ["Visible rooms"] = "Widoczne pokoje",
    ["Language: %1"] = "Język: %1",
    ["Sleep screen: now playing"] = "Ekran uśpienia: teraz gra",
    ["+%1 more"] = "+%1 więcej",
    ["More"] = "Więcej",
    ["PLAYING ON"] = "GRA NA",
    ["Radio"] = "Radio",
    ["Repeat 1"] = "Powtórz 1",
    ["Repeat"] = "Powtarzaj",
    ["Sleep timer"] = "Wyłącznik",
    ["%1 min"] = "%1 min",
    ["Turn off"] = "Wyłącz",
    ["End of this track"] = "Do końca utworu",
    ["Music will stop after this track"] = "Muzyka wyłączy się po tym utworze",
    ["Sleep timer · %1 left"] = "Wyłącznik · zostało %1",
    ["Music is playing here"] = "Tu gra muzyka",
    ["Remove from group"] = "Odłącz od grupy",
    ["Play only here"] = "Graj tylko tutaj",
    ["Play here instead (move the music)"] = "Graj tutaj (przenieś muzykę)",
    ["Add to group (play together)"] = "Dołącz do grupy (grajcie razem)",
    ["Control this room"] = "Steruj tym pokojem",
    ["Other devices (Spotify)…"] = "Inne urządzenia (Spotify)…",
    ["Speakers"] = "Głośniki",
    ["Like"] = "Polub",
    ["Liked"] = "Polubione",
    ["Added to Liked Songs"] = "Dodano do polubionych",
    ["Removed from Liked Songs"] = "Usunięto z polubionych",
    ["Spotify needs a new permission. Run tools/link_spotify.py on your computer again"] = "Spotify potrzebuje nowego uprawnienia. Uruchom ponownie tools/link_spotify.py na komputerze",
    ["Sleep screen: wake up to show the next song"] = "Ekran uśpienia: budź się na kolejny utwór",
    ["Account: %1"] = "Konto: %1",
    ["none"] = "brak",
    ["change / add / remove"] = "zmień / dodaj / usuń",
    ["Spotify account in the Sonos app: %1"] = "Konto Spotify w aplikacji Sonos: %1",
    ["auto"] = "auto",
    ["Other Sonos systems"] = "Inne systemy Sonos",
    ["“%1” is on another network.\n\nThe Kindle only controls the system on the network it is connected to. Connect the Kindle to %2 and the plugin will switch by itself."] =
        "„%1” jest w innej sieci.\n\nKindle steruje tylko systemem w sieci, z którą jest połączony. Połącz Kindle z %2, a plugin przełączy się sam.",
    ["the Wi-Fi “%1”"] = "Wi-Fi „%1”",
    ["that system's Wi-Fi"] = "Wi-Fi tamtego systemu",
    ["Find speakers again"] = "Szukaj głośników ponownie",
    ["Kindle Music settings"] = "Ustawienia Kindle Music",
    ["IP of any Sonos speaker"] = "IP dowolnego głośnika Sonos",
    ["Invalid IP address"] = "Niepoprawny adres IP",
    ["Open remote"] = "Otwórz pilota",
    ["Settings…"] = "Ustawienia…",
    ["not linked"] = "niepołączony",
    ["Set speaker IP…"] = "Ustaw IP głośnika…",
    -- Spotify browser
    ["Empty"] = "Pusto",
    ["‹ Back"] = "‹ Wstecz",
    ["This section needs Spotify to be linked again (new permissions).\nRun tools/link_spotify.py on your computer."] =
        "Ta sekcja wymaga ponownego połączenia ze Spotify (nowe uprawnienia).\nUruchom tools/link_spotify.py na komputerze.",
    ["▶ Play"] = "▶ Odtwórz",
    ["Radio from this song"] = "Radio z tego utworu",
    ["Artist mix: %1"] = "Mix artysty: %1",
    ["Go to album"] = "Przejdź do albumu",
    ["Go to artist"] = "Przejdź do artysty",
    ["Shuffle play"] = "Odtwórz losowo",
    ["Open"] = "Otwórz",
    ["Artist radio"] = "Radio artysty",
    ["Artist mix"] = "Mix artysty",
    ["Mix: %1"] = "Mix: %1",
    ["Search"] = "Szukaj",
    ["♥ Liked"] = "♥ Polubione",
    ["Liked songs"] = "Polubione utwory",
    ["Playlists"] = "Playlisty",
    ["Albums"] = "Albumy",
    ["Saved albums"] = "Zapisane albumy",
    ["No saved albums"] = "Brak zapisanych albumów",
    ["Top artists"] = "Top artyści",
    ["Your top artists"] = "Twoi top artyści",
    ["No data"] = "Brak danych",
    ["Top tracks"] = "Top utwory",
    ["Your top tracks"] = "Twoje top utwory",
    ["▶ Play all"] = "▶ Odtwórz wszystkie",
    ["Following"] = "Obserwowani",
    ["Followed artists"] = "Obserwowani artyści",
    ["You don't follow any artists"] = "Nie obserwujesz artystów",
    ["Recently played items will appear here"] = "Ostatnio odtwarzane pojawią się tutaj",
    ["Recently played"] = "Ostatnio odtwarzane",
    ["Your playlists"] = "Twoje playlisty",
    ["As in Spotify"] = "Jak w Spotify",
    ["Recently changed"] = "Ostatnio zmienione",
    ["Number of tracks"] = "Liczba utworów",
    ["Playlist order"] = "Jak w playliście",
    ["Recently added"] = "Ostatnio dodane",
    ["changed %1"] = "zm. %1",
    ["added %1"] = "dod. %1",
    ["%1 tracks"] = "%1 utw.",
    ["Sort: %1"] = "Sortuj: %1",
    ["Sorting…"] = "Sortuję…",
    ["Sort playlists"] = "Sortuj playlisty",
    ["Sort tracks"] = "Sortuj utwory",
    ["No playlists"] = "Brak playlist",
    ["Albums and singles"] = "Albumy i single",
    ["No albums"] = "Brak albumów",
    ["Couldn't load the tracks. You can still play the whole album"] =
        "Nie udało się pobrać utworów — możesz odtworzyć cały album",
    ["▶ Play album"] = "▶ Odtwórz album",
    ["Shuffle"] = "Losowo",
    ["Spotify doesn't share the tracks of this playlist. You can still play all of it"] =
        "Spotify nie udostępnia listy utworów tej playlisty — możesz ją odtworzyć w całości",
    ["Empty playlist"] = "Pusta playlista",
    ["Search Spotify"] = "Szukaj w Spotify",
    ["Nothing found"] = "Nic nie znaleziono",
    ["Playlist"] = "Playlista",
    ["Artist"] = "Artysta",
    -- errors
    ["Nothing to play (queue is empty)"] = "Brak czego odtwarzać (kolejka pusta)",
    ["No next / previous track"] = "Brak następnego / poprzedniego utworu",
    ["Cannot skip to this track"] = "Nie można przejść do tego utworu",
    ["Speaker is not the group coordinator"] = "Głośnik nie jest koordynatorem grupy",
    ["Sonos error %1"] = "Błąd Sonos %1",
    ["Speaker is not responding (timeout)"] = "Głośnik nie odpowiada (timeout)",
    ["Network error: %1"] = "Błąd sieci: %1",
    ["This Kindle is not linked to Spotify (run tools/link_spotify.py on your computer)"] =
        "Kindle nie jest połączony ze Spotify (uruchom tools/link_spotify.py na komputerze)",
    ["Spotify access expired or was revoked. Link the account again"] =
        "Dostęp do Spotify wygasł lub został odwołany — połącz ponownie",
    ["Playback control requires Spotify Premium"] = "Sterowanie odtwarzaniem wymaga Spotify Premium",
    ["Spotify can't see an active speaker"] = "Spotify nie widzi aktywnego głośnika",
    ["Spotify refused the request"] = "Spotify odmówił wykonania",
    ["Spotify is not responding (timeout)"] = "Spotify nie odpowiada (timeout)",
    -- sleep screen
    ["Now playing"] = "Teraz gra",
    ["Kindle Music · as of %1"] = "Kindle Music · stan z %1",
}

local LANGS = { pl = pl }
local NAMES = { en = "English", pl = "Polski", auto = "Auto (KOReader)" }

local active = nil -- translation table in use (nil = English)

--- lang: "en", "pl", ... or "auto" (KOReader's UI language).
function L10n.setLanguage(lang)
    if lang == "auto" then
        local ko = G_reader_settings and G_reader_settings:readSetting("language") or ""
        lang = tostring(ko):match("^(%a%a)") or "en"
    end
    L10n.lang = LANGS[lang] and lang or "en"
    active = LANGS[L10n.lang]
end

function L10n.languageName(setting)
    return NAMES[setting] or setting
end

--- Translate `text` and fill %1, %2… with the extra arguments.
function L10n.T(text, ...)
    local s = active and active[text] or text
    if select("#", ...) > 0 then
        local args = { ... }
        s = s:gsub("%%(%d)", function(i)
            local v = args[tonumber(i)]
            return v ~= nil and tostring(v) or ""
        end)
    end
    return s
end

return L10n
