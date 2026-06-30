# Customer Support — analiza (pod auto-odpowiedzi)

Analiza historii supportu klientów Framky (skrzynka `hello@framky.com`) jako baza pod system automatycznych odpowiedzi. Okno: **60 dni** (~11.04–10.06.2026).

## Zawartość
| Plik | Co zawiera |
|---|---|
| [01-support-analysis.md](01-support-analysis.md) | **Przegląd**: źródła, metoda, kluczowe odkrycia, kategorie, rekomendacje |
| [02-granular-breakdown.md](02-granular-breakdown.md) | Granularny rozkład 21 podkategorii + % opłaconych zamówień |
| [03-matched-orders.md](03-matched-orders.md) | Dopasowanie problem→zamówienie→data, wiek zamówienia, prawdziwa defektowość |
| [data/category_summary.csv](data/category_summary.csv) | Tabela: kategoria, temat, wiadomości, dystynktni klienci, % zamówień |
| [data/problem_order_match.csv](data/problem_order_match.csv) | Per zanonimizowany klient: problem, nr zamówienia, data, wiek (dni) |

## Najważniejsze w skrócie
- **Support dzieje się głównie poza Chatwootem** (216 ręcznych odpowiedzi z Gmaila / 60 dni vs ~91 w Chatwoocie) — warunek wstępny automatyzacji: kierować wszystkie odpowiedzi przez system.
- **Nr 1 problem: montaż/wieszaki** (12,3% wolumenu zamówień), ale **realna wada produktu <1%** — większość to dozamówienia części i pytania o montaż (idealne pod samoobsługę).
- Mianownik: **163 opłacone zamówienia / 151 klientów** (frami_composer).

## Prywatność
Dane zanonimizowane: brak e-maili/nazwisk/treści; klienci jako stabilne hashe `customer_id`. Surowe pary Q&A i maile pozostają poza repo.

## Odtwarzalność
Skrypty i surowe dane: lokalny katalog roboczy `tmp/support-analysis/` (poza repo) — ekstrakcja IMAP (Gmail Sent), parowanie Q→A, klasyfikacja, dopasowanie do `orders_order`.
