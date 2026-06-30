# Problemy dopasowane do zamówień i ich dat (60-dniowe okno zgłoszeń)

Każde zgłoszenie (dedup po mailu) dopasowane do konkretnego zamówienia: numer z treści maila → `orders_order`, fallback po e-mailu (najnowsze opłacone zamówienie ≤ data kontaktu). Liczę **wiek zamówienia w chwili zgłoszenia**.

Mianowniki (opłacone, bez reprintów): 60d=163 · 120d=413 · 180d=890 · 365d=2625.
Pełne dopasowanie wiersz-po-wierszu: `data/problem_order_match.csv`.

## Wiek zamówienia w chwili zgłoszenia — dzieli problemy na 2 typy

| Kod | Problem | Klienci | Dopasow. | Mediana wieku zam. | Rozkład wieku |
|---|---|---|---|---|---|
| M1 | wieszaki spadły | 8 | 7 | **125 dni** | 61-120d:3 · 121-365d:4 |
| M2 | wieszaki brakujące | 2 | 2 | 93 dni | ≤60d:1 · 61-120d:1 |
| M3 | dozamówienie wieszaków | 9 | 8 | **243 dni** | ≤60d:3 · 121-365d:3 · >365d:2 |
| M4 | instrukcja montażu | 3 | 3 | 14 dni | ≤60d:3 |
| Q1 | uszkodzenie w transporcie | 1 | 1 | 34 dni | ≤60d:1 |
| Q2 | defekt druku / kolor | 4 | 4 | 15 dni | ≤60d:4 |
| Q3 | złe ułożenie / kadr | 1 | 1 | 16 dni | ≤60d:1 |
| S1 | zły link śledzenia | 3 | 3 | 9 dni | ≤60d:3 |
| S2 | zaginiona / opóźniona | 4 | 4 | 17 dni | ≤60d:4 |
| S3 | status / kiedy / gdzie | 9 | 9 | 15 dni | ≤60d:9 |
| E1 | filtr nie zapisany | 2 | 2 | 2 dni | ≤60d:2 |
| E2 | podmiana zdjęcia | 4 | 4 | 9 dni | ≤60d:3 · >365d:1 |
| E3 | inna edycja | 4 | 3 | 2 dni | ≤60d:2 |
| R1 | anulacja | 2 | 2 | 3 dni | ≤60d:2 |
| R2 | zwrot towaru | 4 | 4 | 34 dni | ≤60d:4 |
| R3 | nadpłata / płatność | 3 | 3 | 128 dni | mixed |
| V1 | voucher: przedłużenie | 2 | 1 | (przed zam.) | — |
| V2 | voucher: kod | 1 | 1 | 7 dni | ≤60d:1 |
| V3 | rabat | 2 | 2 | 5 dni | ≤60d:2 |
| P1 | przedsprzedaż | 8 | 6 | 1 dzień | ≤60d:5 (+2 bez zam.) |
| P2 | inne | 10 | 9 | 21 dni | ≤60d:8 |

**Dwa typy problemów:**
- **„Świeże zamówienie" (mediana ≤ ~3 tyg.):** edycja projektu, status/wysyłka, anulacja, defekt druku, kadr, przedsprzedaż, vouchery, zwrot. Dotyczą zamówień z bieżącego okna → metryka „% bieżących zamówień" jest tu sensowna.
- **„Po dostawie / stare zamówienie" (mediana 3–8 mies.):** wieszaki spadły (125 dni), brakujące (93), dozamówienie (243 — część >1 rok). Zgłaszane długo po dostawie → dotyczą zamówień sprzed okna; „% bieżących zamówień" ich NIE opisuje.

## Prawdziwa defektowość (dopasowane zamówienia ÷ opłacone w tym samym oknie wieku)

| Problem | dotknięte zam. (≤120d) | % z 413 | dotknięte (≤180d) | % z 890 |
|---|---|---|---|---|
| Wieszaki spadły + brakujące | 4 | 1,0% | 6 | **0,7%** |
| — z tego spadły | 3 | 0,7% | 5 | 0,6% |
| Uszkodzenie w transporcie | 1 | 0,2% | 1 | 0,1% |
| Defekt druku / kolor | 4 | 1,0% | 4 | 0,4% |
| **Reklamacje jakości łącznie** | 6 | 1,5% | 6 | **0,7%** |

> ⚠️ To **dolne ograniczenia**: zgłoszenia mają opóźnienie (galeria dostarczona niedawno nie zdążyła jeszcze zgłosić odpadających wieszaków — mediana wieku zgłoszenia o wieszaki to 125 dni). Dla dojrzałej oceny patrz na zamówienia ≥2–3 mies. Mimo to twardy wniosek: realna wada produktu (wieszaki/uszkodzenia/druk) dotyczy **<1%** opłaconych zamówień.

## Wniosek
- Wcześniejsze „12,3% zamówień = wieszaki" to **wskaźnik wolumenu zgłoszeń**, nie defektowość: większość to dozamówienia (popyt na części, mediana 243 dni) i reklamacje starych zamówień.
- **Realna wada „wieszaki spadły" ≈ 0,6–1% zamówień.** Wciąż to nr 1 wśród wad i silny sygnał (klej na ścianach gładkich/fakturowanych), ale skala defektu jest niska — większy jest **popyt na dozamówienia i pytania o montaż**, które można obsłużyć samoobsługą/automatem.
