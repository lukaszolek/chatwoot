# Initial knowledge base for the photographer_partnership campaign.
# Inserted only when a campaign has zero knowledge_documents — operator
# edits in the UI are then the source of truth. Re-applying the blueprint
# leaves these alone.
#
# Source material:
#   - https://framky.com/pl-pl/program-partnerski/dla-fotografow
#   - https://framky.com/pl-pl/program-partnerski/regulamin
# (fetched 2026-04-23; consistency notes in the open_issues document below)
module Outreach::KnowledgeSeeds
  module PhotographerPartnership
    module_function

    def seed!(campaign)
      raise ArgumentError, 'campaign required' unless campaign

      DOCUMENTS.each do |attrs|
        campaign.knowledge_documents.create!(attrs)
      end
    end

    DOCUMENTS = [
      {
        kind: 'goal',
        locale: 'pl',
        position: 0,
        title: 'Cel kampanii',
        content: <<~TEXT
          Pozyskać polskich i europejskich fotografów (PL, DE, AT, CH, FR, NL, IT, ES, CZ, SK, HU, RO, HR, DK, FI, SE, GR) do programu partnerskiego Framky. Sukcesem jest:
            - Fotograf zarejestrowany w Panelu Partnera (`https://framky.com/pl-pl/program-partnerski/rejestracja`)
            - Pierwszy klient skutecznie złożył zamówienie z kodem partnera w 30-dniowym oknie konwersji

          Każdy mail outreach ma być **personalny**, zorientowany na konkretną wartość dla fotografa, **bez sztucznego presji**, z minimalnym CTA (jedno słowo w odpowiedzi wystarczy). Outreach jest osobistą propozycją, nie marketingową kampanią masową.
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

          2. **Prowizja** (§ 4 ust. 2, 4, 5):
             - Stawki ustalane przez Administratora, dostępne w Panelu Partnera; **mogą się różnić** w zależności od kategorii produktu, wolumenu sprzedaży, okresów promocyjnych
             - Liczona od **kwoty sprzedaży NETTO** (bez podatków, kosztów wysyłki, po odjęciu rabatów i zwrotów)
             - Warunki naliczenia: klient wszedł przez link partnera, zakup w **30-dniowym oknie konwersji**, zamówienie nie anulowane/zwrócone, płatność zrealizowana

          3. **Wypłaty** (§ 6 ust. 2-5):
             - Minimalny próg wypłaty: **50 EUR** (poniżej — przeniesione na kolejny miesiąc)
             - Wypłaty do **10. dnia każdego miesiąca** za prowizje naliczone w miesiącu poprzednim
             - Metody: SEPA dla UE, PayPal, inne uzgodnione
             - Partner musi dostarczyć ważną dokumentację podatkową i dane do płatności
             - Partner odpowiada za podatki od prowizji

          4. **Obowiązki partnera** (§ 7):
             - Wyłącznie zatwierdzone materiały marketingowe
             - Wyraźnie identyfikować się jako niezależny partner (nie pracownik)
             - **Zakaz**: spam, mylące domeny, strony z treściami dla dorosłych/przemocą

          5. **RODO** (§ 9):
             - Dane klientów tylko do śledzenia przypisania
             - Po rozwiązaniu umowy — usunięte
             - Nigdy nie sprzedawane

          6. **Rozwiązanie umowy** (§ 10):
             - Każda strona — 30-dniowy okres wypowiedzenia (pisemny)
             - Administrator może rozwiązać natychmiastowo: naruszenie regulaminu, oszustwa, nieaktywność > **12 miesięcy**
             - Po rozwiązaniu — usunięcie linków/materiałów; niewypłacone prowizje wypłacane standardowo

          7. **Co NIE jest w regulaminie** (zob. open_issues — NIE PORUSZAJ tego w mailach, dopóki nie zostanie wyjaśnione):
             - Konkretne procenty prowizji
             - Voucher 20 EUR przy rejestracji
             - System polecania innych fotografów (two-tier)
             - Rabat dla klientów partnera
             - Osobny rabat dla samego partnera
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
        kind: 'faq',
        locale: 'pl',
        position: 0,
        title: 'FAQ ze strony "dla fotografów"',
        content: <<~TEXT
          Pytania, które fotografowie zadają najczęściej (źródło: `framky.com/pl-pl/program-partnerski/dla-fotografow`):

          - **Czy program jest tylko dla profesjonalistów?** Nie, program jest otwarty dla wszystkich fotografów — zarówno profesjonalnych, jak i hobbystów. (Uwaga: w regulaminie wymóg ≥1 aktywnej obecności online + 18 lat.)
          - **Jak działa rozliczenie?** Comiesięczne rozliczenia na fakturę lub umowę. Wypłata do 10. dnia każdego miesiąca za prowizje z miesiąca poprzedniego, gdy saldo ≥ 50 EUR.
          - **Co dostaje klient?** Dedykowany kod rabatowy z linkiem partnera (konkretna stawka — zob. Panel Partnera po rejestracji).
          - **Co dostaję ja jako fotograf?** Voucher 20 EUR na przetestowanie produktu, prowizja od zamówień klientów (stawka w Panelu).
          - **Materiały marketingowe?** Tak, gotowe szablony wiadomości i grafiki w Panelu Partnera.
          - **Jak długo trwa weryfikacja?** Do 5 dni roboczych po wypełnieniu formularza.

          Link do rejestracji (PL): `https://framky.com/pl-pl/program-partnerski/rejestracja`
          Link do regulaminu: `https://framky.com/pl-pl/program-partnerski/regulamin`
        TEXT
      },
      {
        kind: 'open_issues',
        locale: nil,
        position: 0,
        title: 'Open issues — NIE poruszaj w mailach',
        content: <<~TEXT
          Niespójności między marketingiem a regulaminem (stan na 2026-04-23). Dopóki nie zostaną wyjaśnione przez biznes, **LLM ma się powstrzymać** od poruszania ich w outboundzie.

          1. **Two-tier (polecenia fotografów)**: strona "dla fotografów" obiecuje "Polecaj innym fotografom, zarabiaj bezterminowo" + "prowizja od zamówień jego klientów — bezterminowo". W regulaminie BRAK jakiegokolwiek paragrafu o tym. Ryzyko prawne. → Nie wspominać two-tier w mailach.

          2. **Konkretne procenty prowizji**: ani regulamin (§ 4 ust. 2: "ustalane przez Administratora"), ani strona ("atrakcyjna prowizja") nie podają. Stary outreach mail obiecywał 25%/20%/40% bez podkładki. → Mówić "atrakcyjna prowizja, szczegóły w Panelu Partnera po rejestracji".

          3. **Voucher 20 EUR**: na stronie obiecane jako "voucher na przetestowanie". W regulaminie BRAK. → Można wspomnieć ze strony, ale uprzedzić, że szczegóły w Panelu.

          4. **Rabat klienta**: na stronie "dedykowany kod rabatowy" (bez procentu). W regulaminie BRAK. → "Klient dostanie kod ze zniżką, szczegóły po rejestracji."

          5. **Osobny rabat dla fotografa**: w starym mailu mówiło się o -40%. NIE WSPOMINAĆ.

          6. **Wymóg 18+**: na stronie nieeksponowany; w regulaminie tak. → Można pominąć w pierwszym mailu, podać przy konkretnym pytaniu.

          7. **Klauzula 12 mies. nieaktywności = rozwiązanie**: w regulaminie tak; nieeksponowane na stronie. → Pominąć w outbounddzie.
        TEXT
      }
    ].freeze
  end
end
