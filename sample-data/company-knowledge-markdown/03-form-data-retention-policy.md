# Polityka przechowywania danych z formularza kontaktowego

Właściciel: Inspektor Ochrony Danych
Wersja: 1.2, obowiązuje od 1 marca 2026

## Zakres
Dotyczy danych osobowych przesłanych przez formularz kontaktowy: imię i nazwisko, e-mail, telefon, treść wiadomości, załączniki.

## Gdzie przechowujemy dane
- Treść formularza: baza danych formularzy (Cloudflare D1).
- Załączniki: magazyn plików (Cloudflare R2), dostęp tylko przez link podpisany ważny maksymalnie 7 dni.
- Dane kontaktowe i historia rozmów: CRM (Attio).

## Okres przechowywania
- Zgłoszenia, które nie przeszły do etapu oferty: 12 miesięcy od daty zgłoszenia, potem usuwamy wiersz z bazy i załącznik.
- Zgłoszenia oznaczone jako Spam: 30 dni.
- Dane klientów, z którymi podpisaliśmy umowę: zgodnie z umową i przepisami rachunkowymi.

## Zasady dla systemów AI
- Modele językowe mogą przetwarzać treść zgłoszenia w celu klasyfikacji i przygotowania szkicu odpowiedzi.
- Agent AI ma dostęp do bazy formularzy wyłącznie kluczem tylko do odczytu. Zmiany statusu wykonuje proces automatyczny po klasyfikacji albo człowiek.
- Do zewnętrznej wyszukiwarki internetowej nie wysyłamy danych osobowych, tylko nazwę firmy.

## Zgoda marketingowa
Brak zgody marketingowej (marketing_consent = 0) oznacza, że kontaktujemy się wyłącznie w sprawie tego zgłoszenia i nie dodajemy osoby do newslettera.
