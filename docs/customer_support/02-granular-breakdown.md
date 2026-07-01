# Granularny rozkład problemów supportowych + % zamówień (60 dni)

**Baza:** 126 par pytanie→odpowiedź (outreach i faktury już usunięte), sklasyfikowane do 21 podkategorii.
**Mianownik:** **163 opłacone zamówienia** w oknie 60 dni (frami_composer `orders_order`, `paid_at` ustawione, bez reprintów `original_id`); **151 płacących klientów**.
**Licznik:** dystynktne e-maile klientów per problem (deduplikacja po mailu). Wykluczono kontakty B2B kuriera `@global24.com`.

> ⚠️ **Jak czytać „% zamówień":** to (liczba różnych klientów ze zgłoszeniem) ÷ 163. Część zgłoszeń dotyczy **zamówień sprzed okna** (np. „wieszaki spadły" pojawia się po dostawie, więc dotyczy starszego zamówienia) — dlatego kolumna „płacący w oknie" bywa niska/zerowa. Dla problemów POdostawowych to raczej wskaźnik wolumenu (zgłoszeń na 100 bieżących zamówień), nie defektowości pojedynczego zamówienia. Pełną defektowość dałoby dopasowanie każdego zgłoszenia do daty jego konkretnego zamówienia.

## Podsumowanie

- **67 różnych klientów** zgłosiło sprawę → **41% względem 163 zamówień** (z czego 27 to klienci z opłaconym zamówieniem w oknie; reszta dotyczy starszych zamówień lub to pytania przedsprzedażowe).
- **55 klientów** miało problem z **istniejącym zamówieniem** (bez pytań przedsprzedażowych) → **33,7%**.
- Tylko **6 osób** to czyste pytania przedsprzedażowe (bez innego problemu).

## Rollup po temacie

| Temat | Klienci | % zamówień | płacący w oknie |
|---|---|---|---|
| Montaż / wieszaki | 20 | **12,3%** | 5 |
| Przedsprzedaż / inne | 18 | 11,0% | 9 |
| Wysyłka / status | 15 | 9,2% | 7 |
| Edycja zamówienia | 10 | 6,1% | 6 |
| Zwroty / płatności | 9 | 5,5% | 5 |
| Reklamacje / jakość | 6 | 3,7% | 1 |
| Vouchery / rabaty | 5 | 3,1% | 4 |

## Granularnie (21 podkategorii)

| Kod | Problem | Wiad. | Klienci (dedup) | % zamówień |
|---|---|---|---|---|
| **M1** | **Wieszaki spadły / nie trzymają** | 11 | **8** | **4,9%** |
| M2 | Wieszaki brakujące w paczce | 2 | 2 | 1,2% |
| **M3** | **Dozamówienie wieszaków/szablonu** (przeprowadzka, zapas) | 15 | **9** | **5,5%** |
| M4 | Instrukcja montażu / szablon | 3 | 3 | 1,8% |
| Q1 | Uszkodzenie w transporcie | 1 | 1 | 0,6% |
| Q2 | Defekt druku / kolor / piksele | 5 | 4 | 2,5% |
| Q3 | Złe ułożenie / kadr / zła ramka | 3 | 1 | 0,6% |
| S1 | Link śledzenia nie działa | 3 | 3 | 1,8% |
| S2 | Paczka zaginiona / opóźniona | 12 | 4 | 2,5% |
| **S3** | **Status / kiedy / gdzie paczka** | 9 | **9** | **5,5%** |
| E1 | Filtr nie zapisany (sepia/cz-b) | 2 | 2 | 1,2% |
| E2 | Podmiana / dodanie zdjęcia | 7 | 4 | 2,5% |
| E3 | Inna edycja (układ/rozmiar/obrót) | 4 | 4 | 2,5% |
| R1 | Anulacja zamówienia | 2 | 2 | 1,2% |
| R2 | Zwrot towaru | 5 | 4 | 2,5% |
| R3 | Nadpłata / błąd płatności | 6 | 3 | 1,8% |
| V1 | Voucher: przedłużenie ważności | 2 | 2 | 1,2% |
| V2 | Voucher: brak/wadliwy kod | 2 | 1 | 0,6% |
| V3 | Prośba o rabat | 2 | 2 | 1,2% |
| P1 | Pytanie przedsprzedażowe/produktowe | 10 | 8 | 4,9% |
| P2 | Inne / podziękowanie / niejasne | 13 | 10 | 6,1% |

## Wniosek dot. wieszaków (odpowiedź na pytanie)

Z 22 zgłoszeń o wieszaki/montaż (20 różnych klientów, 12,3% zamówień):
- **Spadły / nie trzymają (M1): 8 klientów (4,9%)** — najczęściej ściany gładkie z tapetą lub fakturowane.
- **Dozamówienie / przeprowadzka / zapas (M3): 9 klientów (5,5%)** — chcą nowy zestaw (zmiana ściany, zużyte naklejki).
- **Brakujące w paczce (M2): 2 klientów (1,2%).**
- **Instrukcja / szablon (M4): 3 klientów (1,8%).**

Tj. realny defekt (spadły + brakujące) ≈ 10 klientów; reszta to dozamówienia/pytania.

## Źródła / odtwarzalność
- Dane: `data/category_summary.csv`, `data/problem_order_match.csv`. Surowe pary Q&A i maile (PII) pozostają poza repo.
