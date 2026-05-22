# rubocop:disable Metrics/ModuleLength, Style/ClassAndModuleChildren
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
          - **Persona**: Łukasz Olek, założyciel Framky. Pierwsza osoba, ciepło, konkretnie, bez marketingowego tonu.
          - **Rejestr**: profesjonalnie, ale po ludzku. Używaj **Ty/Twoje**. Pierwszy kontakt: "Cześć {{first_name}}", jeśli imię jest znane; inaczej "Dzień dobry".
          - **Bez superlatyw**: nie pisz "uwielbiam Twoje zdjęcia", "Twoje portfolio jest niesamowite", "jestem zachwycony". Bez generycznych komplementów.
          - **Konkret nad ogólnik**: jeśli jest website snippet, dodaj jedno konkretne zdanie otwierające. Jeśli nie ma snippetu, nie twierdź, że widzieliśmy portfolio.
          - **Struktura**: spersonalizowany opener daj w osobnym krótkim akapicie. Dopiero potem zacznij standardowe przedstawienie Łukasza/Framky.
          - **Terminologia**: używaj "link polecający", "prowizja", "galeria ścienna", "fine-art print", "oprawa bez szkła". Nie pisz o drewnianych ramach, szkle ani lakierze UV.
          - **Stopka prawna**: zawsze dodaj informację, skąd mamy dane, link do polityki prywatności, STOP opt-out i pełne dane Framky.
          - **Sygnatura**:

            Pozdrawiam,

            Łukasz
            Framky Founder

          - **CTA**: "Jedno słowo w odpowiedzi wystarczy" albo "Odpisz po prostu 'tak', a wyślę link do rejestracji". Bez presji.
          - **Gender agreement**: dobierz formy z imienia ("byłbyś" / "byłabyś" / neutralna gdy niepewne).
          - **Długość**: Intro ≤ 12 zdań bez obowiązkowej stopki; reminder ≤ 7 zdań; breakup ≤ 5 zdań.
          - **Zgodność liczby adresata**: jeśli profil, nazwa firmy, opis strony lub snippet wskazuje na dwie osoby / duet / małżeństwo / zespół, cały mail pisz konsekwentnie w liczbie mnogiej: „tworzycie”, „Wasz klient”, „otrzymujecie”, „jeśli chcecie dołączyć”, „odpiszcie”. Nie mieszaj liczby mnogiej w openerze z liczbą pojedynczą w dalszej części maila. Jeśli nie ma pewności, że to duet/zespół, użyj neutralnej formy albo liczby pojedynczej zgodnej z imieniem.

          ## Reguły pierwszego akapitu / personalizacji
          - Nie zaczynaj od metadanych typu: „Prowadzisz [nazwa firmy]”, „działasz pod marką…”, „regularnie publikujesz na Instagramie”, „budujesz portfolio online”, jeśli dostępny jest jakikolwiek opis stylu, podejścia do sesji albo realnej oferty fotograficznej. Takie zdania są słabe i nic nie wnoszą.
          - Priorytet źródeł do pierwszego akapitu:
            1. opis „o mnie”,
            2. opis podejścia do sesji,
            3. opis fotografii ślubnej / rodzinnej / portretowej,
            4. typy sesji dobrze pasujące do zdjęć do domu: ślubne, rodzinne, dziecięce, noworodkowe, ciążowe, portretowe, kobiece, narzeczeńskie.
          - Jeśli fotograf oferuje kilka obszarów, wybierz w openerze ten najbardziej pasujący do galerii ściennej w domu: śluby, rodziny, dzieci, noworodki, ciąża, portrety, sesje kobiece, pary. Pomijaj fotografię produktową, biznesową, reklamową, wnętrzarską, gastronomiczną, stomatologiczną, dokumentową, wirtualne spacery i film, chyba że to jedyne dostępne informacje.
          - Skupiaj się na fotografii, nie na filmach, rolkach, spacerach wirtualnych, social mediach ani samej marce/studiu.
          - Nie wybieraj przypadkowych, pobocznych szczegółów tylko dlatego, że są konkretne. Konkret ma być trafny sprzedażowo: ma prowadzić do myśli, że zdjęcia klienta mogą trafić na ścianę.
          - Jeśli dostępne informacje są ubogie, lepiej użyć bezpiecznego ogólnego openeru o typie sesji niż udawać głęboką personalizację.
          - Unikaj zdań w stylu „Właśnie takie kadry zyskują najwięcej…”, jeśli wcześniej nie ma jasnego, konkretnego podmiotu. Zadbaj, żeby pierwsze dwa zdania były gramatycznie samodzielne i naturalne po polsku.

          **Nie używaj takich openerów:**
          - „Prowadzisz [nazwa firmy] i aktywnie budujesz markę online.”
          - „Prowadzisz portfolio pod marką…”
          - „Regularnie publikujesz nowe prace na Instagramie.”
          - „W Twoim portfolio widać szeroki zakres usług.”
          - „Działasz w [miasto] i dojeżdżasz do klientów.”
          - „Tworzysz wirtualne spacery i filmy…” — jeśli są też sesje zdjęciowe.

          **Przykłady lepszych openerów:**
          - „W sesjach rodzinnych i dziecięcych stawiasz na swobodę, bliskość i prawdziwe momenty. To właśnie takie zdjęcia rodzice najczęściej chcą mieć na ścianie, nie tylko w galerii online.”
          - „Fotografujesz śluby w naturalny, reportażowy sposób, bez sztywnego pozowania. Takie kadry łatwo stają się pamiątką, do której para chce wracać codziennie, nie tylko na ekranie.”
          - „W portretach i sesjach kobiecych ważne są dla Ciebie atmosfera, zaufanie i to, żeby osoba przed obiektywem poczuła się swobodnie. Gotowy wydruk może być naturalnym przedłużeniem takiej sesji.”

        TEXT
      },
      {
        kind: 'tone',
        locale: 'en',
        position: 0,
        title: 'Tone — EN',
        content: <<~TEXT
          - **Persona**: Łukasz Olek, founder of Framky. First-person, warm, matter-of-fact, not corporate.
          - **Register**: polite and professional, usually first-name basis. First touch: "Hi {{first_name}}" if a first name is known; otherwise "Hello".
          - **No clichés**: avoid "I love your work", "your photos are amazing", "I came across your portfolio", "I hope this finds you well", and generic praise.
          - **Specific over generic**: weave in one concrete detail from the website snippet if available. If there is no snippet, do not claim we looked at the website or portfolio.
          - **Terminology**: use "personal referral link", "commission", "wall gallery", "fine-art print", "MDF frame without glass". Do not call Framky frames wooden and do not claim glass or UV varnish.
          - **Structure**: put the personalized opener in its own short paragraph. Start a new paragraph before introducing Łukasz/Framky.
          - **Legal footer**: always include why the recipient receives the email, a privacy policy link, STOP opt-out, and full Framky company details.
          - **Signature**:
            ```
            Best,

            Łukasz Olek
            Framky Founder
            ```
          - **CTA**: "Just reply 'yes' and I will send the registration link." Keep it low-friction, never pushy.
          - **Length**: intro ≤ 12 sentences excluding the required legal footer; reminder ≤ 7 sentences; breakup ≤ 5 sentences.
          - **Recipient number agreement**: if the profile, business name, website snippet, or salutation points to two photographers, a couple, a married pair, or a team, keep the whole email consistently plural: "your clients", "your personal referral link", "you receive", "if you would like to join". Do not open in plural and then switch to singular benefits or CTA.

          ## First Paragraph / Personalization Rules
          - Do not open with metadata such as "You run [studio name]", "you work under the brand...", "you regularly post on Instagram", or "you are building your online portfolio" if there is any information about style, approach, or real photography services.
          - Prioritize these sources for the opener:
            1. "about me" text,
            2. description of the shooting experience or approach,
            3. wedding, family, children, newborn, maternity, portrait, boudoir, or couples photography,
            4. session types that naturally fit photos displayed at home.
          - If the photographer offers several areas, choose the one that best fits a wall gallery at home: weddings, families, children, newborn, maternity, portraits, boudoir, couples. Skip product, corporate, real estate/interior, food, dental/medical, passport/document photography, virtual tours, and video unless that is the only information available.
          - Focus on photography, not films, reels, virtual tours, social media, or the studio/brand name alone.
          - Do not pick a random side detail just because it is concrete. The detail should logically lead to the idea that clients' photos can live on a wall.
          - If the available information is thin, use a safe general opener about the session type instead of forcing deep personalization.
          - Make the first two sentences grammatically complete and natural in English. Avoid vague references such as "these images" if it is not clear what images you mean.

          **Do not use openers like:**
          - "You run [studio name] and actively build your online brand."
          - "You regularly publish new work on Instagram."
          - "Your portfolio shows a wide range of services."
          - "You work in [city] and the surrounding area."
          - "You create virtual tours and videos..." if photo sessions are also available.

          **Better opener examples:**
          - "Your family and children's sessions seem to focus on ease, closeness, and real moments. Those are exactly the kind of images parents often want to see at home, not only in an online gallery."
          - "You photograph weddings in a natural, documentary way, without forcing stiff poses. That kind of work often becomes something couples want to return to every day, not only on a screen."
          - "In portraits and boudoir sessions, trust and a relaxed atmosphere seem central to your work. A finished print can be a natural continuation of that kind of personal session."

          **Subject lines**: 2-4 words, calm and concrete, no first name, urgency, percentages, or emoji. Good shapes: "photos on the wall", "wall galleries", "prints for clients", "quick question", "framky partnership".
        TEXT
      },
      {
        kind: 'tone',
        locale: 'fr',
        position: 0,
        title: 'Ton — FR',
        content: <<~TEXT
          - **Persona** : Łukasz Olek, fondateur de Framky. Première personne, chaleureux, concret, sans ton marketing.
          - **Registre** : professionnel et poli, **vous/votre**. Premier contact : "Bonjour {{first_name}}" si le prénom est connu ; sinon "Bonjour". Pas de ton trop familier.
          - **Pas de clichés** : éviter "j'adore votre travail", "vos photos sont magnifiques", "je suis impressionné", "je suis tombé sur votre portfolio" et les compliments génériques.
          - **Le concret avant le générique** : intégrer un seul détail concret issu du snippet du site si disponible. S'il n'y a pas de snippet, ne pas prétendre avoir consulté le site ou le portfolio.
          - **Terminologie** : utiliser "lien de parrainage personnel", "commission", "galerie murale", "tirage fine-art", "cadre MDF sans verre". Ne pas dire que les cadres sont en bois et ne pas mentionner de verre ni de vernis UV.
          - **Structure** : placer l'ouverture personnalisée dans un court paragraphe séparé. Commencer ensuite un nouveau paragraphe pour présenter Łukasz/Framky.
          - **Mention légale** : toujours ajouter pourquoi le destinataire reçoit l'e-mail, un lien vers la politique de confidentialité, l'option STOP et les coordonnées complètes de Framky.
          - **Signature** :

            Bien cordialement,

            Łukasz Olek
            Founder, Framky

          - **CTA** : "Répondez simplement « oui » et je vous enverrai le lien d'inscription." Simple, sans pression.
          - **Longueur** : intro ≤ 12 phrases hors mention légale obligatoire ; reminder ≤ 7 phrases ; breakup ≤ 5 phrases.
          - **Accord du destinataire** : si le profil, le nom de l'entreprise, le snippet ou la salutation indique deux photographes, un couple, un duo marié ou une équipe, écrire tout l'e-mail de manière cohérente au pluriel : "vos clients", "votre lien de parrainage", "vous recevez", "si vous souhaitez rejoindre". Ne pas commencer au pluriel puis passer au singulier.

          ## Règles pour le premier paragraphe / la personnalisation
          - Ne pas commencer par des métadonnées comme : "Vous dirigez [nom du studio]", "vous travaillez sous la marque...", "vous publiez régulièrement sur Instagram", "vous développez votre portfolio en ligne", s'il existe une information sur le style, l'approche ou une vraie offre photographique.
          - Priorité pour l'ouverture :
            1. texte "à propos",
            2. description de l'approche pendant les séances,
            3. photographie de mariage, famille, enfants, nouveau-né, grossesse, portrait, boudoir ou couple,
            4. types de séances qui correspondent naturellement à des photos affichées à la maison.
          - Si le photographe propose plusieurs domaines, choisir celui qui correspond le mieux à une galerie murale chez un client : mariage, famille, enfants, nouveau-né, grossesse, portraits, boudoir, couples. Éviter produit, corporate, immobilier/intérieur, gastronomie, médical/dentaire, photos d'identité/documents, visites virtuelles et vidéo, sauf si c'est la seule information disponible.
          - Se concentrer sur la photographie, pas sur les films, reels, visites virtuelles, réseaux sociaux ou seulement le nom du studio.
          - Ne pas choisir un détail secondaire au hasard simplement parce qu'il est concret. Le détail doit mener naturellement à l'idée que les photos des clients peuvent vivre sur un mur.
          - Si les informations sont faibles, utiliser une ouverture générale mais sûre sur le type de séance plutôt qu'une personnalisation forcée.
          - Les deux premières phrases doivent être autonomes et naturelles en français. Éviter les références vagues comme "ces images" si le sujet n'est pas clair.

          **Ne pas utiliser ce type d'ouverture :**
          - "Vous dirigez [nom du studio] et développez activement votre marque en ligne."
          - "Vous publiez régulièrement de nouveaux travaux sur Instagram."
          - "Votre portfolio montre une large gamme de services."
          - "Vous travaillez à [ville] et dans les environs."
          - "Vous créez des visites virtuelles et des vidéos..." s'il y a aussi des séances photo.

          **Exemples de meilleures ouvertures :**
          - "Dans vos séances famille et enfants, l'accent semble mis sur la douceur, la proximité et les vrais moments. Ce sont justement des images que les parents veulent souvent voir chez eux, pas seulement dans une galerie en ligne."
          - "Vous photographiez les mariages dans un style naturel et reportage, sans poses figées. Ce type de photos devient vite un souvenir auquel un couple veut revenir au quotidien, pas seulement sur un écran."
          - "Dans vos portraits et séances boudoir, la confiance et une atmosphère détendue semblent essentielles. Un tirage fini peut être le prolongement naturel d'une séance aussi personnelle."

          **Objets d'e-mail** : 2-4 mots, calmes et concrets, sans prénom, urgence, pourcentage ni emoji. Bons exemples : "photos au mur", "galeries murales", "tirages clients", "petite question", "partenariat framky".
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
        kind: 'tone',
        locale: 'nl',
        position: 0,
        title: 'Tone - NL',
        content: <<~TEXT
          - **Persona**: Łukasz Olek, oprichter van Framky. Eerste persoon, warm, zakelijk en concreet.
          - **Register**: beleefd-professioneel, **u/uw**. Eerste contact: "Beste {{first_name}}" als de voornaam bekend is; anders "Beste fotograaf". Geen "Hoi".
          - **Geen clichés**: geen "Ik ben onder de indruk van uw werk", geen "uw foto’s zijn prachtig", geen overdreven complimenten.
          - **Concreet boven generiek**: verwerk één concreet detail uit de website-snippet als die beschikbaar is. Als er geen snippet is, beweer niet dat we de website of het portfolio hebben bekeken.
          - **Terminologie**: gebruik "persoonlijke verwijzingslink", "commissie", "wandgalerie", "fotoprint", "MDF-lijst zonder glas". Noem Framky geen houten lijsten en claim geen glas of UV-vernis.
          - **Structuur**: zet de gepersonaliseerde openingszin in een eigen korte alinea. Begin daarna een nieuwe alinea met de introductie van
            Łukasz/Framky.
          - **Juridische afsluiting**: voeg altijd toe waarom de ontvanger de e-mail krijgt, een link naar de privacyverklaring, een STOP-opt-out en de volledige bedrijfsgegevens van
            Framky.
          - **Signatuur**:

            Met vriendelijke groet,

            Łukasz Olek
            Founder, Framky

          - **CTA**: "Antwoord gewoon met ‘ja’, dan stuur ik u de registratielink." Laagdrempelig, nooit druk.
          - **Lengte**: Intro ≤ 12 zinnen exclusief de verplichte juridische afsluiting; Reminder ≤ 7 zinnen; Breakup ≤ 5 zinnen.
          - **Aantal aanspreekvorm**: als het profiel, de bedrijfsnaam, de website-snippet of de aanhef wijst op twee fotografen, een koppel, een echtpaar of een team, schrijf dan de hele e-mail consequent in het meervoud: "jullie klanten", "jullie persoonlijke verwijzingslink", "jullie ontvangen", "als jullie willen meedoen", "antwoord dan gewoon met 'ja'". Wissel niet tussen een meervoudige opening en enkelvoudige voordelen of CTA. Als het niet duidelijk is dat het om een duo/team gaat, gebruik dan de formele enkelvoudsvorm "u/uw".

          ## Regels voor de eerste alinea / personalisatie
          - Begin niet met metadata zoals: "U runt [studionaam]", "u werkt onder de naam...", "u publiceert regelmatig op Instagram", "u bouwt online aan uw portfolio", als er ook maar enige informatie beschikbaar is over stijl, werkwijze of een echte fotografische dienst. Zulke zinnen voegen weinig toe.
          - Prioriteit voor de opening:
            1. een "over mij"-tekst,
            2. beschrijving van de aanpak tijdens shoots,
            3. beschrijving van trouw-, gezins-, kinder-, newborn-, zwangerschaps-, portret-, boudoir- of koppelshoots,
            4. relevante sessietypes die goed passen bij foto's voor thuis aan de muur.
          - Als een fotograaf meerdere diensten aanbiedt, kies in de opening het onderwerp dat het best past bij een wandgalerie thuis: bruiloften, gezinnen, kinderen, newborn, zwangerschap, portretten, boudoir, koppels. Laat productfotografie, bedrijfsfotografie, vastgoed/interieur, horeca, tandarts/medische fotografie, documentfoto's, virtuele tours en video weg, tenzij dat de enige beschikbare informatie is.
          - Richt de opening op fotografie, niet op films, reels, virtuele rondleidingen, social media of alleen de studio/merknaam.
          - Kies geen willekeurig detail alleen omdat het concreet is. Het detail moet logisch leiden naar het idee dat foto's van klanten een plek aan de muur kunnen krijgen.
          - Als de beschikbare informatie dun is, gebruik liever een veilige algemene opening over het type shoot dan een geforceerd persoonlijke zin.
          - Zorg dat de eerste twee zinnen grammaticaal zelfstandig en natuurlijk Nederlands zijn. Vermijd vage verwijzingen zoals "zulke beelden" als niet duidelijk is welke beelden bedoeld worden.

          **Gebruik zulke openingen niet:**
          - "U runt [studionaam] en bouwt actief aan uw online merk."
          - "U publiceert regelmatig nieuw werk op Instagram."
          - "Uw portfolio laat een breed aanbod zien."
          - "U werkt in [stad] en omgeving."
          - "U maakt virtuele tours en video’s..." als er ook fotosessies beschikbaar zijn.

          **Voorbeelden van betere openingen:**
          - "In uw gezins- en kindersessies draait het om rust, nabijheid en echte momenten. Juist dat soort beelden willen ouders vaak niet alleen in een online galerij bewaren, maar ook thuis aan de muur zien."
          - "U fotografeert bruiloften op een natuurlijke, reportagestijl manier, zonder geforceerde poses. Zulke foto's worden snel herinneringen waar een koppel dagelijks naar wil terugkijken."
          - "Bij portretten en boudoirsessies lijkt vertrouwen en een ontspannen sfeer centraal te staan. Een afgewerkte print kan een logisch vervolg zijn op zo'n persoonlijke shoot."

          **Onderwerpregels**: 2-4 woorden, rustig en concreet, zonder naam, urgentie, percentages of emoji. Goede vormen: "foto's aan de muur", "wandgalerie voor klanten", "prints voor uw klanten", "korte vraag", "framky samenwerking".
        TEXT
      },
      {
        kind: 'intro_seed',
        locale: 'pl',
        position: 0,
        title: 'Intro seed — pierwszy mail (PL)',
        content: <<~TEXT
          Napisz pierwszy mail outreach do fotografa po polsku. Użyj poniższej treści jako stałej bazy. Możesz lekko dopasować tylko powitanie na podstawie dostępnych danych profilu i dodać maksymalnie jedno konkretne zdanie otwierające na podstawie website snippet, jeśli taki snippet faktycznie istnieje.

          WAŻNE: obowiązkową stopkę prawną poniżej zawsze wstaw dosłownie na końcu maila. Nie streszczaj, nie usuwaj, nie przenoś. Stopka zaczyna się od "---" i kończy na "Tel.: +48 22 270 1091". Stopka nie liczy się do limitu długości.

          Cześć {{first_name}},

          Nazywam się Łukasz Olek i jestem założycielem Framky. Drukujemy i oprawiamy zdjęcia, które klienci wieszają u siebie w domu. Salon klienta to często najlepsza wizytówka fotografa.

          Wydruk, który trafi do klienta, to fine-art print na papierze fotograficznym: dwanaście tuszy pigmentowych, 99% pokrycia przestrzeni PANTONE®, oprawiony przez nas bez szkła, żeby kolory nie traciły głębi. Zależy nam na wydruku, który odpowiada wartości Twojej pracy.

          Chcemy zaprosić Cię do programu partnerskiego Framky:

          - Twój klient zamawia galerię ścienną w naszym sklepie przez Twój osobisty link polecający.
          - Otrzymujesz 20% prowizji od każdego zamówienia.
          - Otrzymujesz dodatkowo 2% prowizji od obrotu fotografów, których polecisz do Framky.
          - Średnia galeria ścienna za 200 euro netto daje 40 euro prowizji.
          - Produkcję, oprawę, wysyłkę i obsługę klienta bierzemy w całości na siebie.

          Rejestracja zajmuje około dwóch minut. Po rejestracji otrzymasz osobisty link polecający, dostęp do panelu rozliczeń oraz rabat na zamówienia do własnego studia.

          Jeśli chcesz dołączyć, odpisz po prostu „TAK” — wtedy wyślę Ci link do rejestracji.

          Pozdrawiam,

          Łukasz
          Framky Founder

          ---
          Otrzymujesz tę wiadomość, ponieważ znaleźliśmy Twoje publicznie dostępne dane kontaktowe opublikowane na stronie Twojego studia. Więcej informacji o tym, jak przetwarzamy dane osobowe, znajdziesz w naszej polityce prywatności: https://framky.com/pl-PL/polityka-prywatnosci

          Jeśli nie chcesz otrzymywać od nas kolejnych wiadomości, odpowiedz „STOP”.

          Framky Sp. z o.o.
          ul. Heliotropów 29
          04-796 Warszawa, Polska
          E-mail: hello@framky.pl
          Tel.: +48 22 270 1091

          Ważne:
          - Zachowaj dokładnie prowizje: 20% od zamówień klientów i 2% od poleconych fotografów.
          - Nie dodawaj P.S. ani informacji o tymczasowej promocji.
          - Nie dodawaj vouchera, rabatu 25%, kodów klienta ani innych benefitów, jeśli nie ma ich powyżej.
          - Użyj informacji o dwunastu tuszach pigmentowych i 99% pokrycia przestrzeni PANTONE® tylko w dokładnym kontekście powyżej.
          - Nie twierdź, że ramy są drewniane. Nie wspominaj o szkle ani lakierze UV.
          - Pisz na „Ty”, ale profesjonalnie i bez przesadnej poufałości.
          - Jeśli nie masz pewności co do płci odbiorcy, używaj neutralnych form.
          - Nie pomijaj obowiązkowej stopki prawnej.
          - Jeśli odbiorcą jest duet, małżeństwo, studio prowadzone przez dwie osoby albo zespół, dostosuj CAŁY mail do liczby mnogiej. Dotyczy to nie tylko pierwszego akapitu, ale też bulletów, CTA, stopki prawnej i opt-out.
        TEXT
      },
      {
        kind: 'intro_seed',
        locale: 'nl',
        position: 0,
        title: 'Intro seed - eerste mail (NL)',
        content: <<~TEXT
          Schrijf de eerste outreach-mail aan een fotograaf in het Nederlands. Gebruik deze inhoud als vaste basis. Pas alleen de aanhef licht aan op basis van beschikbare profielgegevens en voeg maximaal één concreet detail uit de website-snippet toe als dat echt beschikbaar is.

          BELANGRIJK: neem de juridische afsluiting hieronder altijd letterlijk op aan het einde van de e-mail. Niet samenvatten, niet weglaten, niet verplaatsen. De juridische afsluiting begint bij "---" en eindigt bij "Tel.: +48 22 270 1091". Deze afsluiting telt niet mee voor de lengterichtlijn.


          Beste {{first_name}},

          Mijn naam is Łukasz Olek, oprichter van Framky. Wij printen en lijsten foto’s in die uw klanten thuis aan de muur kunnen hangen. De woonkamer van een klant is vaak de beste visitekaart die een fotograaf kan hebben.

          Onze prints zijn fine-art prints op fotopapier: twaalf pigmentinkten, 99% dekking van het PANTONE®-kleurbereik, door ons ingelijst zonder glas zodat de kleuren hun diepte niet verliezen. Ons doel is een print die past bij de waarde van uw werk.

          We nodigen u uit voor het Framky-partnerprogramma:

          - Uw klant bestelt een wandgalerie in onze shop via uw persoonlijke verwijzingslink.
          - U ontvangt 20% commissie op elke bestelling.
          - U ontvangt daarnaast 2% commissie over de omzet van fotografen die u bij Framky aanbrengt.
          - Een gemiddelde wandgalerie van 200 euro netto levert 40 euro commissie op.
          - Productie, inlijsten, verzending en klantenservice verzorgen wij volledig.

          Aanmelden duurt ongeveer twee minuten. Na registratie ontvangt u uw persoonlijke verwijzingslink, toegang tot het uitbetalingsportaal en een korting op bestellingen voor uw eigen studio.

          Wilt u meedoen? Antwoord dan gewoon met “ja”, dan stuur ik u de registratielink.

          Met vriendelijke groet,

          Łukasz Olek
          Founder, Framky

          ---
          U ontvangt deze e-mail omdat wij uw zakelijke contactgegevens hebben gevonden die openbaar zijn gepubliceerd op uw studio-website. Meer informatie over hoe wij persoonsgegevens verwerken vindt u in onze privacyverklaring: https://framky.com/nl-NL/privacybeleid

          Als u geen verdere berichten van ons wilt ontvangen, antwoord dan met “STOP”.

          Framky Sp. z o.o.
          ul. Heliotropów 29
          04-796 Warszawa, Polen
          E-mail: hello@framky.pl
          Tel.: +48 22 270 1091


          Belangrijk:
          - Behoud de commissiepercentages exact: 20% voor bestellingen van klanten en 2% voor aangebrachte fotografen.
          - Gebruik geen P.S. over tijdelijke verhoging van commissie.
          - Gebruik de claim over twaalf pigmentinkten en 99% dekking van het PANTONE®-kleurbereik alleen in de exacte context hierboven.
          - Claim geen UV-vernis, houten lijsten of glas.
          - Gebruik “u/uw”, niet “je/jij”.
          - Voeg geen extra voordelen toe die niet hierboven staan.
          - Als de ontvanger een duo, echtpaar of team is, herschrijf de hele e-mail consequent naar "jullie": "jullie klant", "jullie persoonlijke verwijzingslink", "jullie ontvangen", "als jullie willen meedoen", "antwoord dan gewoon met 'ja'". Pas ook de juridische afsluiting en STOP-zin aan naar meervoud.
          - Begin de e-mail niet met een opening over alleen de studionaam, Instagram, locatie of "online portfolio" als er informatie is over stijl, werkwijze of diensten.
          - Kies in de openingsalinea eerst fotografie die goed past bij een wandgalerie thuis: bruiloft, gezin, kinderen, newborn, zwangerschap, portret, boudoir, koppels. Vermijd vastgoed/interieur, product, bedrijf, documentfoto's, video en virtuele tours als er ook zulke persoonlijke sessies beschikbaar zijn.
          - Als de snippet weinig zegt, gebruik dan een veilige algemene opening over het type shoot in plaats van een geforceerd persoonlijk detail.
          - Gebruik in de opening niet steeds de formule "maar veel bestanden blijven na de shoot vooral op een scherm staan". Dat klinkt negatief en te sjabloonmatig. Maak liever een positieve brug naar het product: "verdienen een plek aan de muur", "passen goed bij een tastbare plek in huis", "willen ouders/koppels vaak dagelijks terugzien".
          - Houd de opening natuurlijk en concreet. Goede vormen:
            - "In uw newborn-, zwangerschaps- en gezinsfotografie draait het om kleine, intieme momenten die voor ouders veel waarde houden. Dat zijn precies de beelden die vaak een vaste plek in huis verdienen."
            - "Uw paardenfotografie draait om kracht, rust en de band tussen mens en dier. Juist zulke beelden lenen zich goed voor een plek aan de muur, niet alleen voor een digitale galerij."
            - "U fotografeert momenten rond liefde, nieuw leven en communies: beelden die voor gezinnen vaak een blijvende emotionele waarde hebben. Juist zulke foto's passen goed bij een tastbare plek in huis."
        TEXT
      },
      {
        kind: 'intro_seed',
        locale: 'en',
        position: 0,
        title: 'Intro seed — first email (EN)',
        content: <<~TEXT
          Write the first outreach email to a photographer in English. Use the content below as the fixed base. You may only adjust the greeting based on available profile data and add at most one concrete opening sentence from the website snippet if that snippet actually exists.

          IMPORTANT: always include the legal footer below verbatim at the end of the email. Do not summarize, remove, or move it. The legal footer starts with "---" and ends with "Tel.: +48 22 270 1091". The footer does not count toward the length guideline.

          Hi {{first_name}},

          My name is Łukasz Olek, founder of Framky. We print and frame photos that clients hang at home. A client's living room is often the best showcase a photographer can have.

          The print your client receives is a fine-art print on photographic paper: twelve pigment inks, 99% coverage of the PANTONE® color space, framed by us without glass so the colors keep their depth. We care about a print that matches the value of your work.

          We would like to invite you to the Framky partner program:

          - Your client orders a wall gallery in our shop through your personal referral link.
          - You receive 20% commission on every order.
          - You also receive 2% commission on the revenue of photographers you refer to Framky.
          - An average wall gallery worth 200 euro net gives you 40 euro commission.
          - We handle production, framing, shipping, and customer service in full.

          Registration takes about two minutes. After registering, you receive your personal referral link, access to the payout panel, and a discount on orders for your own studio.

          If you would like to join, just reply "yes" and I will send you the registration link.

          Best,

          Łukasz Olek
          Framky Founder

          ---
          You are receiving this email because we found your publicly available business contact details published on your studio website. You can find more information about how we process personal data in our privacy policy: https://framky.com/en-gb/privacy-policy

          If you do not want to receive further messages from us, reply "STOP".

          Framky Sp. z o.o.
          ul. Heliotropów 29
          04-796 Warsaw, Poland
          E-mail: hello@framky.pl
          Tel.: +48 22 270 1091

          Important:
          - Keep the commission rates exactly: 20% for client orders and 2% for referred photographers.
          - Do not add a P.S. or any temporary promotion.
          - Do not add vouchers, a 25% client discount, client codes, or other benefits if they are not listed above.
          - Use the claim about twelve pigment inks and 99% PANTONE® color-space coverage only in the exact context above.
          - Do not claim that the frames are wooden. Do not mention glass or UV varnish.
          - If the recipient is a duo, married pair, studio run by two people, or a team, adapt the whole email consistently to plural address. This applies to the opener, bullets, CTA, legal footer, and opt-out.
          - Do not open with only the studio name, Instagram, location, or "online portfolio" if there is information about style, approach, or services.
          - In the opening paragraph, prefer photography that fits a home wall gallery: wedding, family, children, newborn, maternity, portrait, boudoir, couples. Avoid real estate/interior, product, corporate, passport/document, video, and virtual tours if personal sessions are also available.
          - If the snippet is thin, use a safe general opener about the session type instead of a forced personal detail.
        TEXT
      },
      {
        kind: 'intro_seed',
        locale: 'fr',
        position: 0,
        title: 'Intro seed — premier e-mail (FR)',
        content: <<~TEXT
          Rédige le premier e-mail outreach à un photographe en français. Utilise le contenu ci-dessous comme base fixe. Tu peux seulement ajuster légèrement la salutation selon les données du profil et ajouter au maximum une phrase d'ouverture concrète issue du snippet du site, si ce snippet existe réellement.

          IMPORTANT : ajoute toujours la mention légale ci-dessous telle quelle à la fin de l'e-mail. Ne la résume pas, ne la supprime pas, ne la déplace pas. La mention légale commence par "---" et se termine par "Tel.: +48 22 270 1091". Elle ne compte pas dans la limite de longueur.

          Bonjour {{first_name}},

          Je m'appelle Łukasz Olek et je suis le fondateur de Framky. Nous imprimons et encadrons des photos que les clients accrochent chez eux. Le salon d'un client est souvent la meilleure vitrine qu'un photographe puisse avoir.

          Le tirage reçu par le client est un tirage fine-art sur papier photo : douze encres pigmentaires, 99 % de couverture de l'espace couleur PANTONE®, encadré par nos soins sans verre afin que les couleurs gardent leur profondeur. Nous voulons un tirage à la hauteur de la valeur de votre travail.

          Nous aimerions vous inviter au programme partenaire Framky :

          - Votre client commande une galerie murale dans notre boutique via votre lien de parrainage personnel.
          - Vous recevez 20 % de commission sur chaque commande.
          - Vous recevez aussi 2 % de commission sur le chiffre d'affaires des photographes que vous recommandez à Framky.
          - Une galerie murale moyenne de 200 euros net génère 40 euros de commission.
          - Nous prenons entièrement en charge la production, l'encadrement, l'expédition et le service client.

          L'inscription prend environ deux minutes. Après l'inscription, vous recevez votre lien de parrainage personnel, l'accès au panneau de paiement et une remise sur les commandes pour votre propre studio.

          Si vous souhaitez rejoindre le programme, répondez simplement « oui » et je vous enverrai le lien d'inscription.

          Bien cordialement,

          Łukasz Olek
          Founder, Framky

          ---
          Vous recevez cet e-mail parce que nous avons trouvé vos coordonnées professionnelles publiquement disponibles sur le site de votre studio. Vous trouverez plus d'informations sur la manière dont nous traitons les données personnelles dans notre politique de confidentialité : https://framky.com/fr-FR/politique-confidentialite

          Si vous ne souhaitez plus recevoir de messages de notre part, répondez « STOP ».

          Framky Sp. z o.o.
          ul. Heliotropów 29
          04-796 Varsovie, Pologne
          E-mail: hello@framky.pl
          Tel.: +48 22 270 1091

          Important :
          - Conserve exactement les taux de commission : 20 % sur les commandes des clients et 2 % sur les photographes parrainés.
          - N'ajoute pas de P.S. ni d'information sur une promotion temporaire.
          - N'ajoute pas de bon, de remise client de 25 %, de code client ou d'autre avantage s'ils ne figurent pas ci-dessus.
          - Utilise l'information sur les douze encres pigmentaires et les 99 % de couverture de l'espace PANTONE® uniquement dans le contexte exact ci-dessus.
          - Ne dis pas que les cadres sont en bois. Ne mentionne pas de verre ni de vernis UV.
          - Utilise "vous/votre", pas "tu/ton".
          - Si le destinataire est un duo, un couple marié, un studio géré par deux personnes ou une équipe, adapte tout l'e-mail au pluriel de manière cohérente. Cela concerne l'ouverture, les bullets, le CTA, la mention légale et l'opt-out.
          - Ne commence pas par une phrase sur le seul nom du studio, Instagram, la localisation ou le "portfolio en ligne" s'il existe une information sur le style, l'approche ou les services.
          - Dans le premier paragraphe, choisis d'abord une photographie qui correspond bien à une galerie murale chez le client : mariage, famille, enfants, nouveau-né, grossesse, portrait, boudoir, couples. Évite immobilier/intérieur, produit, corporate, documents, vidéo et visites virtuelles si des séances personnelles sont aussi disponibles.
          - Si le snippet est pauvre, utilise une ouverture générale sûre sur le type de séance plutôt qu'un détail personnel forcé.
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
# rubocop:enable Metrics/ModuleLength, Style/ClassAndModuleChildren
