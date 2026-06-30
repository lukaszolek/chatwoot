# Analiza supportu klientów Framky — okno 60 dni

> Cel: baza pod system automatycznych odpowiedzi na pytania/problemy supportowe.
> Okres: ~11.04–10.06.2026. Wszystkie liczby zagregowane; dane per-klient zanonimizowane (patrz „Prywatność").

## Źródła danych
- **Chatwoot**, skrzynka **Hello** (`hello@framky.com`) — rozmowy klient↔support.
- **Gmail** tej skrzynki, folder **„Wysłane"** — ręczne odpowiedzi wysyłane z pominięciem Chatwoota.
- **frami_composer** `orders_order` — zamówienia (mianownik do liczenia %).

## Metoda (skrót)
- Odpowiedzi człowieka wykrywane po podpisie agenta oraz **domenie Message-ID**: ręczne = `@mail.gmail.com`/`@spark`; automaty aplikacji = `@server.framky.com`/`@prod.frami.app`.
- **Pary pytanie→odpowiedź**: nasze odpowiedzi sparowane z pytaniami klientów po `In-Reply-To` (precyzyjnie) lub po e-mailu+czasie.
- Usunięto **outreach** (kampanie współpracy z influencerami) i **faktury/B2B**.
- Mianownik: **opłacone** zamówienia (`paid_at` ustawione, bez reprintów `original_id`).

## Kluczowe odkrycia

1. **Większość supportu dzieje się POZA Chatwootem.** W 60 dni: **216 ręcznych odpowiedzi z Gmaila** vs ~91 zapisanych w Chatwoocie. Kryterium „0 wiadomości wychodzących w Chatwoocie" **nie znaczy** „bez odpowiedzi" — na 228 rozmów „bez odpowiedzi" aż **54 (24%) obsłużono poza systemem** (klient cytuje naszą odpowiedź). Warunek wstępny automatyzacji: **kierować wszystkie odpowiedzi przez system** (audyt, dane treningowe, brak dublowania).
2. **Korpus:** 126 par pytanie→odpowiedź (po usunięciu outreachu/faktur), wielojęzyczny: EN 59 · DE 26 · NL 15 · PL 12 · FR 7 · IT 5 · ES 2.
3. **Baza zamówień:** **163 opłacone zamówienia / 151 płacących klientów** (60 dni). **67 różnych klientów** zgłosiło sprawę (41% wolumenu; **55** to problem z istniejącym zamówieniem, reszta to przedsprzedaż).

## Najczęstsze problemy (% opłaconych zamówień, dedup po mailu)

| Temat | Klienci | % zamówień |
|---|---|---|
| **Montaż / wieszaki** | 20 | **12,3%** |
| Przedsprzedaż / inne | 18 | 11,0% |
| Wysyłka / status | 15 | 9,2% |
| Edycja zamówienia | 10 | 6,1% |
| Zwroty / płatności | 9 | 5,5% |
| Reklamacje / jakość | 6 | 3,7% |
| Vouchery / rabaty | 5 | 3,1% |

Granularnie (21 podkategorii): zob. [`data/category_summary.csv`](data/category_summary.csv) i [02-granular-breakdown.md](02-granular-breakdown.md).

## Wieszaki — granularnie i prawdziwa defektowość

Z 22 zgłoszeń montażowych (20 klientów): **spadły 8 · dozamówienie 9 · brakujące 2 · instrukcja 3**.

Po **dopasowaniu do konkretnych zamówień** (zob. [03-matched-orders.md](03-matched-orders.md)) widać, że problemy podostawowe dotyczą **starych** zamówień:
- „wieszaki spadły" — mediana wieku zamówienia **125 dni**; „dozamówienie" — **243 dni** (część >1 rok).

**Prawdziwa defektowość** (dotknięte zamówienia ÷ opłacone w tym samym oknie wieku):

| Wada | % zamówień |
|---|---|
| Wieszaki spadły + brakujące | **0,7%** (≤180d) |
| Defekt druku / kolor | 0,4% |
| Uszkodzenie w transporcie | 0,1% |
| **Reklamacje jakości łącznie** | **~0,7%** |

→ Realna wada produktu dotyczy **<1%** opłaconych zamówień (dolne ograniczenie — zgłoszenia mają opóźnienie). Wcześniejsze „12,3%" to **wskaźnik wolumenu zgłoszeń**, nie defektowości: większość „wieszakowego" ruchu to **dozamówienia (popyt na części)** i pytania o montaż.

## Rekomendacje dla systemu auto-odpowiedzi

- **Triage:** odfiltruj szum (bounce, outreach, faktury, B2B), wykryj **język**, sklasyfikuj do kategorii; **auto-taguj**, by nic nie ginęło.
- **Pełna automatyzacja (🟢):** dozamówienie wieszaków/szablonu (link „Edytuj galerię" + dobór mocowania wg typu ściany), status/śledzenie (lookup zamówienia), pytania produktowe (DPI/rozmiary/jak działa), vouchery, faktury.
- **Asysta agenta (🟡):** reklamacje/uszkodzenia, zwroty, rozbieżności płatności.
- **Sygnał produktowy:** przyczepność wieszaków na ścianach gładkich (tapeta) i fakturowanych — rozważyć domyślny montaż na gwoździe dla trudnych ścian + jaśniejszą komunikację.
- **Operacyjnie:** wymusić, by **wszystkie** odpowiedzi szły przez Chatwoota.

## Pliki w tym folderze
- [01-support-analysis.md](01-support-analysis.md) — ten dokument (przegląd).
- [02-granular-breakdown.md](02-granular-breakdown.md) — granularny rozkład + % zamówień.
- [03-matched-orders.md](03-matched-orders.md) — dopasowanie problem→zamówienie→data + defektowość.
- [`data/category_summary.csv`](data/category_summary.csv) — 21 podkategorii (wiadomości, dystynktni klienci, % zamówień).
- [`data/problem_order_match.csv`](data/problem_order_match.csv) — per zanonimizowany klient: problem, nr zamówienia, data, wiek (dni).

## Prywatność
Pliki w repo są **zanonimizowane**: brak e-maili, nazwisk i treści maili. Klienci występują jako stabilne hashe (`customer_id` = `c`+sha256(email)[:8]). Numery zamówień i daty zachowane (dane operacyjne). Surowe pary Q&A i maile pozostają **poza repo** (lokalnie).
