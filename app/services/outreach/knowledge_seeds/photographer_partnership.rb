# Knowledge base for the photographer_partnership campaign.
#
# Two entry points:
#   * `seed!(campaign)` — initial insert when a campaign has zero
#     knowledge_documents (called from BlueprintApplier on first apply).
#   * `sync!(campaign)` — upsert by (kind, locale) so CI/CD can roll out
#     content updates from this file without losing operator-added docs
#     whose (kind, locale) does not match a seeded entry. See the
#     `outreach:knowledge:sync` rake task.
#
# Source material:
#   - https://framky.com/pl-pl/program-partnerski/dla-fotografow
#   - https://framky.com/pl-pl/program-partnerski/regulamin
# (refreshed 2026-04-28 — concrete commission rates landed in the regulamin)
module Outreach::KnowledgeSeeds
  module PhotographerPartnership
    module_function

    def seed!(campaign)
      raise ArgumentError, 'campaign required' unless campaign

      DOCUMENTS.each do |attrs|
        campaign.knowledge_documents.create!(attrs)
      end
    end

    # Idempotent upsert: matches existing documents by (kind, locale) and
    # rewrites title/content/position/active. Operator-added documents whose
    # (kind, locale) is not in DOCUMENTS are left untouched.
    def sync!(campaign)
      raise ArgumentError, 'campaign required' unless campaign

      DOCUMENTS.each do |attrs|
        doc = campaign.knowledge_documents.find_or_initialize_by(
          kind: attrs.fetch(:kind),
          locale: attrs[:locale]
        )
        doc.assign_attributes(
          title: attrs.fetch(:title),
          content: attrs.fetch(:content),
          position: attrs.fetch(:position),
          active: true
        )
        doc.save!
      end
    end

    DOCUMENTS = [
      {
        kind: 'goal',
        locale: 'pl',
        position: 0,
        title: 'Cel kampanii',
        content: <<~TEXT
          Pozyskać polskich i europejskich fotografów (PL, DE, AT, CH, FR, NL, IT, ES, CZ, SK, HU, RO, HR, DK, FI, SE, GR) do programu partnerskiego Framky. Dwa równoważne typy sukcesu:

          1. **Polecenie pierwszego poziomu (klient → Framky)** — fotograf zarejestrowany w Panelu Partnera (`https://framky.com/pl-pl/program-partnerski/rejestracja`), pierwszy klient skutecznie złożył zamówienie z linku polecającego w 30-dniowym oknie konwersji.

          2. **Polecenie drugiego poziomu (partner → partner)** — fotograf nie tylko poleca Framky swoim klientom, ale też **poleca program znajomym fotografom**. Za każdego takiego poleconego fotografa zarabia 2% prowizji od jego sprzedaży — bezterminowo. To ciche serce kampanii: jeden zaangażowany ambasador przyciąga kolejnych, a my im to wynagradzamy.

          Każdy mail outreach ma być **personalny**, zorientowany na konkretną wartość dla fotografa, **bez sztucznej presji**, z minimalnym CTA (jedno słowo w odpowiedzi wystarczy). Outreach jest osobistą propozycją, nie marketingową kampanią masową.
        TEXT
      },
      {
        kind: 'product',
        locale: nil,
        position: 0,
        title: 'Framky — produkt',
        content: <<~TEXT
          Framky to wysokiej jakości galerie zdjęć ścienne, dostarczane w formie gotowego zestawu do montażu w kilka minut.

          - Druk fine-art na 12-tuszowej maszynie pigmentowej
          - Matowy papier fotograficzny — bez odbłysków
          - Ramki z MDF — lekkie, **bez szkła**
          - Zestaw zawiera szablon montażowy + samoprzylepne wieszaki (opcjonalnie montaż na 2 gwoździe)
          - Zero ramiarza, zero żmudnego mierzenia, zero wiercenia
          - Dostępne kompozycje: pojedyncze odbitki + galerie wielokadrowe (ready-to-order)

          Przewaga vs. zwykły lab/druku w studio: gotowy do powieszenia produkt, w pudełku, z instrukcją. Klient fotografa otrzymuje fizyczne dzieło, które ląduje na ścianie — nie w folderze na pulpicie.
        TEXT
      },
      {
        kind: 'program_rules',
        locale: 'pl',
        position: 0,
        title: 'Regulamin programu — najważniejsze zasady',
        content: <<~TEXT
          Źródło: `https://framky.com/pl-pl/program-partnerski/regulamin`. Zacytuj te zasady DOSŁOWNIE, kiedy fotograf pyta o szczegóły. **Nie wymyślaj liczb, których tu nie ma.**

          1. **Wymagania dla partnera** (§ 2 ust. 5; § 3 ust. 1; § 15 ust. 1):
             - Ukończone 18 lat
             - Wypełniony formularz z danymi: imię/nazwa, e-mail, adres strony/social media, dane do identyfikacji podatkowej
             - Co najmniej jedna aktywna obecność online (firmowa strona, portfolio, profil w mediach społecznościowych)
             - Akceptacja wniosku przez Administratora w ciągu 5 dni roboczych

          2. **Stawki prowizji** (§ 4 — w regulaminie i w Panelu Partnera):
             - **20% od kwoty netto** zamówienia każdego klienta, który wejdzie przez **link polecający** partnera (po odjęciu rabatu klienta, bez VAT, kosztów wysyłki, zwrotów).
             - **25% rabat** dla klienta partnera od ceny katalogowej — automatycznie naliczany, gdy klient korzysta z linku polecającego.
             - **2% od kwoty netto** zamówień klientów **partnera poleconego** — czyli innego fotografa, który zarejestrował się z Twojego polecenia. To prowizja drugiego poziomu, naliczana **bezterminowo**, dopóki obaj jesteście aktywnymi partnerami.
             - Struktura kończy się na pierwszym poziomie polecenia partner→partner (regulamin nie przewiduje kaskady głębiej niż jeden poziom).

          3. **Warunki naliczenia prowizji** (§ 4 ust. 4–5):
             - Klient/partner wszedł przez link polecający, zakup w **30-dniowym oknie konwersji**, model **last-click**, zamówienie nie anulowane/zwrócone, płatność zrealizowana.

          4. **Wypłaty** (§ 6 ust. 2-5):
             - Minimalny próg wypłaty: **50 EUR** (poniżej — przeniesione na kolejny miesiąc)
             - Wypłaty do **10. dnia każdego miesiąca** za prowizje naliczone w miesiącu poprzednim
             - Metody: SEPA dla UE, PayPal, inne uzgodnione
             - Partner musi dostarczyć ważną dokumentację podatkową i dane do płatności
             - Partner odpowiada za podatki od prowizji

          5. **Obowiązki partnera** (§ 7):
             - Wyłącznie zatwierdzone materiały marketingowe
             - Wyraźnie identyfikować się jako niezależny partner (nie pracownik)
             - **Zakaz**: spam, mylące domeny, strony z treściami dla dorosłych/przemocą

          6. **RODO** (§ 9):
             - Dane klientów tylko do śledzenia przypisania
             - Po rozwiązaniu umowy — usunięte
             - Nigdy nie sprzedawane

          7. **Rozwiązanie umowy** (§ 10):
             - Każda strona — 30-dniowy okres wypowiedzenia (pisemny)
             - Administrator może rozwiązać natychmiastowo: naruszenie regulaminu, oszustwa, nieaktywność > **12 miesięcy**
             - Po rozwiązaniu — usunięcie linków/materiałów; niewypłacone prowizje wypłacane standardowo
        TEXT
      },
      {
        kind: 'tone',
        locale: 'pl',
        position: 0,
        title: 'Ton kampanii — PL',
        content: <<~TEXT
          - **Persona**: Łukasz Olek, założyciel Framky. First-person, warm, matter-of-fact.
          - **Rejestr**: moderate, **Ty** (nie Pan/Pani). "Cześć {{first_name}}".
          - **Bez superlatyw**: nie pisz "uwielbiam Twoje zdjęcia", "Twoje portfolio jest niesamowite". Lazy and generic.
          - **Konkret nad ogólnik**: jeśli widać website snippet — wpleć JEDEN konkretny detal stylistyczny / niszowy.
          - **Sygnatura**:
            ```
            Pozdrawiam,

            Łukasz
            Framky Founder
            ```
          - **CTA**: "Jedno słowo w odpowiedzi wystarczy" — nigdy presji, nigdy "ostatnia szansa".
          - **Gender agreement**: dobierz formy z imienia ("byłbyś" / "byłabyś" / neutralna gdy niepewne).
          - **Długość**: intro ≤ 12 zdań; reminder ≤ 7 zdań; breakup ≤ 5 zdań.
        TEXT
      },
      {
        kind: 'tone',
        locale: 'en',
        position: 0,
        title: 'Tone — EN',
        content: <<~TEXT
          - **Persona**: Łukasz Olek, founder of Framky. First-person, warm, matter-of-fact.
          - **Register**: moderate, first-name basis. "Hi {{first_name}}".
          - **No clichés**: avoid "I love your work", "your photos are amazing".
          - **Specific over generic**: weave in one concrete detail from the website snippet if available.
          - **Signature**:
            ```
            Best,

            Łukasz
            Framky Founder
            ```
          - **CTA**: "A one-line reply is enough" — never pressure.
          - **Length**: intro ≤ 12 sentences; reminder ≤ 7 sentences; breakup ≤ 5 sentences.
        TEXT
      },
      {
        kind: 'tone',
        locale: 'de',
        position: 0,
        title: 'Ton — DE',
        content: <<~TEXT
          - **Persona**: Łukasz Olek, Gründer von Framky. Erste Person, warm, sachlich.
          - **Register**: very-formal, **Sie/Ihre**. Erstkontakt: "Guten Tag {{first_name}}" (kein "Hallo").
          - **Keine Floskeln**: kein "Ich liebe Ihre Arbeit", kein "Ihre Fotos sind großartig".
          - **Konkret statt generisch**: ein konkretes Detail aus dem Website-Snippet einbauen, wenn vorhanden.
          - **Signatur** (immer voller Name in formellen Märkten):
            ```
            Mit freundlichen Grüßen,

            Łukasz Olek
            Framky Founder
            ```
          - **CTA**: "Eine kurze Antwort reicht" — niemals Druck.
          - **Länge**: Intro ≤ 12 Sätze; Reminder ≤ 7 Sätze; Breakup ≤ 5 Sätze.
        TEXT
      },
      {
        kind: 'intro_seed',
        locale: 'pl',
        position: 0,
        title: 'Intro seed — bullets do pierwszego maila (PL)',
        content: <<~TEXT
          Bullets do pierwszego maila wysyłanego do fotografa. Komponer (intro) ma je przepisać DOSŁOWNIE — można dopasować tylko opener (anchor z website snippet) i sygnaturę. Nie generalizuj, nie skracaj, nie zamieniaj na "atrakcyjna prowizja".

          **Co dostajesz w programie partnerskim Framky:**

          - **20% prowizji** od kwoty netto każdego zamówienia klienta, który wejdzie przez Twój **link polecający** (last-click, 30-dniowe okno konwersji).
          - **25% rabat dla Twojego klienta** od ceny katalogowej — naliczany automatycznie, gdy klient kupuje przez link polecający. Czyli klient zyskuje, Ty zyskujesz, bez żadnej dodatkowej sztuczki.
          - **2% prowizji bezterminowo, gdy polecisz Framky innemu fotografowi** — zarabiasz na każdym zamówieniu klientów tego fotografa, dopóki jest aktywny w programie. To "drugi poziom" polecania: pasywny strumień, w który warto włożyć jeden mail do znajomego z branży.
          - **Voucher 20 EUR na start**, żebyś sam przetestował jakość naszych galerii zanim cokolwiek polecisz klientowi.
          - **Wypłaty co miesiąc** (SEPA dla UE / PayPal), próg 50 EUR, do 10. dnia za miesiąc poprzedni.
          - **Bez limitu** liczby klientów, bez limitu czasu zarabiania, bez ekskluzywności.

          CTA: jedno zdanie w odpowiedzi (np. "wchodzę") — odeślę link do rejestracji + voucher startowy.
        TEXT
      },
      {
        kind: 'copywriting',
        locale: 'pl',
        position: 0,
        title: 'Copywriting — zasady cold-mail (PL)',
        content: <<~TEXT
          Reguły komponowania każdego maila w kampanii (intro / reminder / breakup / reply).

          1. **Każde zdanie zarabia swoje miejsce.** Wytnij wszystko, co czytelnik pominie wzrokiem.
          2. **Konkret > ogólnik.** "20% prowizji" zamiast "atrakcyjna prowizja". "25% rabat dla klienta" zamiast "ciekawe warunki". Zero korpomowy.
          3. **Bez clickbaitu w temacie.** 2-4 słowa, lowercase, brzmi jak wewnętrzna notatka. Bez imienia adresata, bez procentów, bez emoji. Przykłady: "galerie na ścianę", "kursy i wydruki", "szybka propozycja".
          4. **Bez fałszywej presji.** Żadnych "ostatnia szansa", "tylko dziś", "specjalnie dla Ciebie".
          5. **Bez clichés.** Zero "uwielbiam Twoje zdjęcia", "podziwiam Twój styl", "I hope this finds you well", "natknąłem się na Twoje portfolio".
          6. **Polecanie drugiego poziomu — nie chowaj go.** Bullet o 2% od poleconych fotografów to często najmocniejszy hak (pasywny przychód) — wymień go z naciskiem, nie zakopuj na dole.
          7. **Link polecający, nie "kod", nie "handle".** Ujednolicona terminologia: zawsze mówimy "link polecający" (lub "Twój link"). Nigdy "handle", nigdy "kod afiliacyjny".
          8. **Sygnatura zawsze pełna**: imię + "Framky Founder". Nawet w reply.
        TEXT
      },
      {
        kind: 'faq',
        locale: 'pl',
        position: 0,
        title: 'FAQ ze strony "dla fotografów"',
        content: <<~TEXT
          Pytania, które fotografowie zadają najczęściej (źródło: `framky.com/pl-pl/program-partnerski/dla-fotografow` + regulamin):

          - **Czy program jest tylko dla profesjonalistów?** Nie, program jest otwarty dla wszystkich fotografów — zarówno profesjonalnych, jak i hobbystów. (Uwaga: w regulaminie wymóg ≥1 aktywnej obecności online + 18 lat.)
          - **Ile dokładnie zarabiam?** **20% od kwoty netto** każdego zamówienia klienta, który wszedł przez Twój link polecający. Plus **2% od kwoty netto** zamówień klientów fotografów, których polecisz do programu — bezterminowo.
          - **Co dostaje mój klient?** **25% rabat** od ceny katalogowej, naliczany automatycznie, gdy klient wejdzie przez Twój link polecający.
          - **Co dostaję, gdy polecę innego fotografa?** Gdy znajomy fotograf zarejestruje się z Twojego polecenia i zacznie polecać Framky swoim klientom, **dostajesz 2% od każdego zamówienia jego klientów — bezterminowo**, dopóki jesteście oboje aktywnymi partnerami. To pasywny strumień przychodu — jeden mail do koleżanki z branży może procentować latami.
          - **Czy łańcuch poleceń jest głębszy niż 2 poziomy?** Nie, regulamin przewiduje dokładnie jeden poziom polecenia partner→partner. Twój polecony fotograf nie może już polecić kolejnego "z Twojego drzewa" tak, żebyś dostał z tego prowizję.
          - **Jak działa rozliczenie?** Comiesięczne rozliczenia na fakturę lub umowę. Wypłata do 10. dnia każdego miesiąca za prowizje z miesiąca poprzedniego, gdy saldo ≥ 50 EUR.
          - **Co dostaję na start?** Voucher 20 EUR na przetestowanie produktu, indywidualny **link polecający** + materiały marketingowe w Panelu Partnera.
          - **Jak długo trwa weryfikacja?** Do 5 dni roboczych po wypełnieniu formularza.

          Link do rejestracji (PL): `https://framky.com/pl-pl/program-partnerski/rejestracja`
          Link do regulaminu: `https://framky.com/pl-pl/program-partnerski/regulamin`
        TEXT
      },
      {
        kind: 'open_issues',
        locale: nil,
        position: 0,
        title: 'Open issues — co wymaga ostrożności w outboundzie',
        content: <<~TEXT
          Stan na 2026-04-28. Stawki prowizji 20% / 25% rabatu klienta / 2% drugiego poziomu są **potwierdzone w regulaminie** (§ 4) — można ich używać z imienia i nazwiska. Wcześniejsze obawy o "ujawnianie procentów" są nieaktualne.

          Co warto trzymać miękko:

          1. **Voucher 20 EUR**: na stronie obiecane jako "voucher na przetestowanie". Szczegóły operacyjne (kiedy aktywuje się, kiedy wygasa) — w Panelu Partnera. W mailu można wspomnieć fakt, ale szczegóły kierować do Panelu.

          2. **Wymóg 18+**: na stronie nieeksponowany; w regulaminie tak. Pominąć w pierwszym mailu, podać przy konkretnym pytaniu.

          3. **Klauzula 12 mies. nieaktywności = rozwiązanie**: w regulaminie tak; nieeksponowane na stronie. Pominąć w outboundzie.

          4. **Materiały marketingowe**: regulamin mówi "wyłącznie zatwierdzone". Nie obiecywać "róbcie co chcecie" — kierować do Panelu po rejestracji.

          5. **Stawki są zmienne** (§ 4 ust. 2 — Administrator może je zmieniać, w tym po kategoriach produktów / okresach promocyjnych). 20% / 25% / 2% to aktualny stan **bazowy**; jeśli ktoś dopytuje o stałość, trzeba uczciwie powiedzieć, że Administrator zastrzega sobie prawo do zmian, ale obowiązuje stawka z momentu zamówienia.
        TEXT
      }
    ].freeze
  end
end
