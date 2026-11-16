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
    ["All rooms (group)"] = "Wszystkie pokoje (grupa)",
    ["Volume slider controls"] = "Suwak głośności steruje",
    ["Volume of this room"] = "Głośność tego pokoju",
    ["All"] = "Wszystkie",
    ["The speakers did not confirm the change. Check the Sonos app."] = "Głośniki nie potwierdziły zmiany. Sprawdź w aplikacji Sonos.",
    ["Removing %1 from the group…"] = "Odłączam %1 od grupy…",
    ["Switching to %1…"] = "Przełączam na %1…",
    ["Moving the music to %1…"] = "Przenoszę muzykę do: %1…",
    ["Adding %1 to the group…"] = "Dołączam %1 do grupy…",
    ["Like"] = "Polub",
    ["Liked"] = "Polubione",
    ["Added to Liked Songs"] = "Dodano do polubionych",
    ["Removed from Liked Songs"] = "Usunięto z polubionych",
    ["Spotify needs a new permission. Link the account again (Settings → Account → Add account)"] = "Spotify potrzebuje nowego uprawnienia. Połącz konto ponownie (Ustawienia → Konto → Dodaj konto)",
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
    ["This section needs Spotify to be linked again (new permissions).\nSettings → Account → Add account."] =
        "Ta sekcja wymaga ponownego połączenia ze Spotify (nowe uprawnienia).\nUstawienia → Konto → Dodaj konto.",
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
    ["This Kindle is not linked to Spotify (Settings → Account → Add account)"] =
        "Kindle nie jest połączony ze Spotify (Ustawienia → Konto → Dodaj konto)",
    ["+ Add account with your phone…"] = "+ Dodaj konto telefonem…",
    ["Spotify linked: %1\n\nFor playback through Sonos, add this Spotify account in the Sonos app too."] =
        "Połączono Spotify: %1\n\nŻeby grać przez Sonos, dodaj to konto Spotify także w aplikacji Sonos.",
    ["This Kindle is not linked to Spotify yet. Link an account now with your phone?"] =
        "Ten Kindle nie jest jeszcze połączony ze Spotify. Połączyć konto teraz telefonem?",
    ["Link"] = "Połącz",
    ["Note: without Spotify Premium, playback control through Spotify Connect will not work."] =
        "Uwaga: bez Spotify Premium sterowanie przez Spotify Connect nie będzie działać.",
    ["Add a Spotify account"] = "Dodaj konto Spotify",
    ["1. Connect your phone to the same Wi-Fi as this Kindle.\n2. Scan the code with the phone's camera.\n3. Follow the steps on the phone and sign in. No Spotify app yet? The phone guides you through creating one."] =
        "1. Połącz telefon z tą samą siecią Wi-Fi co Kindle.\n2. Zeskanuj kod aparatem telefonu.\n3. Postępuj według kroków na telefonie i zaloguj się. Nie masz aplikacji Spotify? Telefon przeprowadzi Cię przez jej założenie.",
    ["Connect the Kindle to Wi-Fi first."] = "Najpierw połącz Kindle z Wi-Fi.",
    ["Could not open the link page on this Kindle: %1"] = "Nie udało się uruchomić strony łączenia na Kindlu: %1",
    ["Scan the QR code on the Kindle again."] = "Zeskanuj ponownie kod QR z Kindla.",
    ["32 letters and digits"] = "32 litery i cyfry",
    ["Kindle Music uses your own free Spotify developer app. One person in the household creates it once, which takes about 5 minutes. You need Spotify Premium."] = "Kindle Music korzysta z Twojej własnej, darmowej aplikacji deweloperskiej Spotify. Jedna osoba w domu zakłada ją raz, zajmuje to około 5 minut. Potrzebne jest Spotify Premium.",
    ["Do you already have a Spotify app with a Client ID?"] = "Masz już aplikację Spotify z Client ID?",
    ["No, show me how to create it"] = "Nie, pokaż jak ją założyć",
    ["Yes, I have a Client ID"] = "Tak, mam Client ID",
    ["Paste the Client ID of your Spotify app (developer.spotify.com → Dashboard → your app → Settings)."] = "Wklej Client ID swojej aplikacji Spotify (developer.spotify.com → Dashboard → Twoja aplikacja → Settings).",
    ["In the Spotify app, the Redirect URI must be exactly:"] = "W aplikacji Spotify Redirect URI musi być dokładnie:",
    ["No Spotify app yet? Step-by-step guide"] = "Nie masz jeszcze aplikacji Spotify? Instrukcja krok po kroku",
    ["Open developer.spotify.com"] = "Otwórz developer.spotify.com",
    ["Add the Redirect URI"] = "Dodaj Redirect URI",
    ["Other people in the household (optional)"] = "Inni domownicy (opcjonalnie)",
    ["Copy the Client ID"] = "Skopiuj Client ID",
    ["Create your Spotify app"] = "Załóż aplikację Spotify",
    ["Back"] = "Wstecz",
    ["Next"] = "Dalej",
    ["Step %1 of %2"] = "Krok %1 z %2",
    ["Guide with more detail:"] = "Dokładniejsza instrukcja:",
    ["Open the Spotify developer website"] = "Otwórz stronę Spotify dla deweloperów",
    ["Tap the button below. The Spotify for Developers website opens in a new tab."] = "Stuknij przycisk poniżej. Strona Spotify for Developers otworzy się w nowej karcie.",
    ["Tap “Log in” and sign in with the same Spotify account you use to listen to music."] = "Stuknij „Log in” i zaloguj się tym samym kontem Spotify, którego używasz do słuchania muzyki.",
    ["Keep this page open. After each step, switch back to this tab and tap “Next”."] = "Nie zamykaj tej strony. Po każdym kroku wróć do tej karty i stuknij „Dalej”.",
    ["It's free and does not change your Spotify subscription."] = "To nic nie kosztuje i nie zmienia Twojej subskrypcji Spotify.",
    ["First time only: accept the terms"] = "Tylko za pierwszym razem: zaakceptuj warunki",
    ["If Spotify shows “Developer Terms of Service”, tick the box and tap “Accept the terms”."] = "Jeśli Spotify pokaże „Developer Terms of Service”, zaznacz pole i stuknij „Accept the terms”.",
    ["If it asks you to verify your e-mail, open the e-mail from Spotify, tap the link in it, then go back to the dashboard."] = "Jeśli poprosi o potwierdzenie e-maila, otwórz wiadomość od Spotify, stuknij link w niej i wróć do panelu.",
    ["Nothing like this appeared? Just tap “Next”."] = "Nic takiego się nie pokazało? Po prostu stuknij „Dalej”.",
    ["Start a new app"] = "Rozpocznij nową aplikację",
    ["On the dashboard tap “Create app”. On a phone you may need to scroll to find it."] = "W panelu stuknij „Create app”. Na telefonie może być trzeba przewinąć stronę, żeby go znaleźć.",
    ["A form called “Create app” opens. The next steps fill it in."] = "Otworzy się formularz „Create app”. Kolejne kroki pokazują, jak go wypełnić.",
    ["Name the app"] = "Nazwij aplikację",
    ["App name: type Kindle Music"] = "App name: wpisz Kindle Music",
    ["App description: type Remote for my Kindle"] = "App description: wpisz Remote for my Kindle",
    ["Website: leave it empty."] = "Website: zostaw puste.",
    ["The names don't matter. Only you will see them."] = "Nazwy nie mają znaczenia. Widzisz je tylko Ty.",
    ["Tap the green “Copy the address” button below."] = "Stuknij zielony przycisk „Kopiuj adres” poniżej.",
    ["Go back to the Spotify form, tap the “Redirect URIs” field, paste the address and tap “Add”."] = "Wróć do formularza Spotify, stuknij pole „Redirect URIs”, wklej adres i stuknij „Add”.",
    ["The address now appears in a list under the field. It must be exactly the same, including the slash at the end."] = "Adres pojawi się na liście pod polem. Musi być dokładnie taki sam, razem z ukośnikiem na końcu.",
    ["Can't paste? Type it by hand, carefully."] = "Nie da się wkleić? Przepisz go ręcznie, uważnie.",
    ["Tick Web API and save"] = "Zaznacz Web API i zapisz",
    ["Under “Which API/SDKs are you planning to use?” tick “Web API”. Leave the others unticked."] = "Przy „Which API/SDKs are you planning to use?” zaznacz „Web API”. Pozostałych nie zaznaczaj.",
    ["Tick the box “I understand and agree with Spotify's Developer Terms of Service…”."] = "Zaznacz pole „I understand and agree with Spotify's Developer Terms of Service…”.",
    ["Tap “Save”. The page of your new app opens."] = "Stuknij „Save”. Otworzy się strona Twojej nowej aplikacji.",
    ["An error about the Redirect URI? Check the previous step: the address must start with https:// and end with a slash."] = "Błąd przy Redirect URI? Sprawdź poprzedni krok: adres musi zaczynać się od https:// i kończyć ukośnikiem.",
    ["Only if someone else will link their own Spotify account to a Kindle."] = "Tylko jeśli ktoś jeszcze połączy z Kindlem swoje własne konto Spotify.",
    ["On your app's page tap “Settings”, then the “User Management” tab."] = "Na stronie aplikacji stuknij „Settings”, a potem zakładkę „User Management”.",
    ["Type their name and the e-mail address of their Spotify account and tap “Add user”. Up to 5 people."] = "Wpisz imię i adres e-mail jego konta Spotify i stuknij „Add user”. Maksymalnie 5 osób.",
    ["Not needed for your own account."] = "Dla własnego konta nie jest to potrzebne.",
    ["On your app's page tap “Settings”."] = "Na stronie aplikacji stuknij „Settings”.",
    ["Under “Basic Information” you see “Client ID”: a long code of 32 letters and digits. Copy it (press and hold to select it, then Copy)."] = "W sekcji „Basic Information” jest „Client ID”: długi kod z 32 liter i cyfr. Skopiuj go (przytrzymaj palec, żeby go zaznaczyć, potem Kopiuj).",
    ["Come back here, paste it into the field below and tap “Sign in with Spotify”."] = "Wróć tutaj, wklej go w pole poniżej i stuknij „Sign in with Spotify”.",
    ["Don't copy the “Client secret”. It is not needed and should stay private."] = "Nie kopiuj „Client secret”. Nie jest potrzebny i powinien zostać prywatny.",
    ["Copied ✓ Now paste it in Spotify"] = "Skopiowano ✓ Teraz wklej go w Spotify",
    ["Address selected: tap Copy in the menu"] = "Adres zaznaczony: wybierz Kopiuj z menu",
    ["Copy the address"] = "Kopiuj adres",
    ["Link Spotify to your Kindle"] = "Połącz Spotify z Kindlem",
    ["Sign in with Spotify"] = "Zaloguj się przez Spotify",
    ["That doesn't look like a Client ID (32 letters and digits)."] = "To nie wygląda na Client ID (32 litery i cyfry).",
    ["Spotify was not linked"] = "Nie połączono Spotify",
    ["Try again"] = "Spróbuj ponownie",
    ["Spotify said: %1"] = "Odpowiedź Spotify: %1",
    ["This sign-in does not belong to this Kindle. Start again from the QR code."] = "To logowanie nie pasuje do tego Kindla. Zacznij od nowa od kodu QR.",
    ["Spotify refused the sign-in (%1). Check that the Redirect URI in your Spotify app is exactly %2"] =
        "Spotify odrzucił logowanie (%1). Sprawdź, czy Redirect URI w Twojej aplikacji Spotify to dokładnie %2",
    ["Linked: %1"] = "Połączono: %1",
    ["You can close this page. The Kindle is ready."] = "Możesz zamknąć tę stronę. Kindle jest gotowy.",
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
