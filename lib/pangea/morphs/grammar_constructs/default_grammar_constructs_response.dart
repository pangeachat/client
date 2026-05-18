/// English-targeted offline fallback for the choreographer's
/// `POST /choreo/grammar_constructs` endpoint.
///
/// Shape mirrors the choreographer's `GrammarConstructsJoinedResponse`:
/// `{target_language, user_l1, source_l1, features: [{feature,
/// feature_title, values: [{value, display, sequence_position, example,
/// title, description}]}]}`. See
/// `2-step-choreographer/app/handlers/grammar_constructs/router.py` for
/// the authoritative schema.
///
/// `display`/`sequence_position`/`example` are L1-invariant facts the
/// canonical handler decides per-target_language. For an offline default
/// we pick reasonable values for English: common UD pairs that manifest
/// in English are `display: true`; typological/utility labels
/// (Antipassive, exotic cases, SPACE/SYM/X) are `false`.
/// `sequence_position` uses CEFR band midpoints (A1=1.5, A2=2.5, B1=3.5,
/// B2=4.5, C1=5.5, C2=6.0) per the choreographer schema's
/// `CEFR_BAND_MIDPOINT`.
const Map<String, dynamic> defaultGrammarConstructsResponse = {
  "target_language": "en",
  "user_l1": "en",
  "source_l1": "en",
  "features": [
    {
      "feature": "pos",
      "feature_title": "Part of speech",
      "values": [
        {"value": "ADJ", "display": true, "sequence_position": 1.5, "example": "a *happy* child", "title": "Adjective", "description": "A word that describes a noun, like 'happy' or 'blue'."},
        {"value": "ADP", "display": true, "sequence_position": 1.5, "example": "*in* the box", "title": "Adposition", "description": "A preposition or postposition, like 'in', 'on', or 'under'."},
        {"value": "ADV", "display": true, "sequence_position": 1.5, "example": "she ran *quickly*", "title": "Adverb", "description": "A word that modifies a verb, adjective, or other adverb, like 'quickly' or 'very'."},
        {"value": "AFFIX", "display": false, "sequence_position": 5.5, "example": "un-, -ness, -ing", "title": "Affix", "description": "A piece added to a word to change its meaning, like a prefix or suffix."},
        {"value": "AUX", "display": true, "sequence_position": 1.5, "example": "she *is* running", "title": "Auxiliary", "description": "A helping verb used with a main verb, like 'is', 'have', or 'will'."},
        {"value": "CCONJ", "display": true, "sequence_position": 1.5, "example": "bread *and* butter", "title": "Coordinating conjunction", "description": "A word that joins equal parts of a sentence, like 'and', 'but', or 'or'."},
        {"value": "COMPN", "display": true, "sequence_position": 3.5, "example": "*toothbrush*", "title": "Compound noun", "description": "A noun made of two or more words working as one, like 'toothbrush'."},
        {"value": "DET", "display": true, "sequence_position": 1.5, "example": "*the* book", "title": "Determiner", "description": "A word that introduces a noun, like 'the', 'a', 'this', or 'some'."},
        {"value": "IDIOM", "display": true, "sequence_position": 4.5, "example": "*kick the bucket*", "title": "Idiom", "description": "A fixed phrase with a meaning different from its literal words, like 'kick the bucket'."},
        {"value": "INTJ", "display": true, "sequence_position": 1.5, "example": "*wow*, that's amazing", "title": "Interjection", "description": "A short word expressing emotion, like 'oh', 'wow', or 'ouch'."},
        {"value": "NOUN", "display": true, "sequence_position": 1.5, "example": "the *book*", "title": "Noun", "description": "A word for a person, place, thing, or idea, like 'book' or 'happiness'."},
        {"value": "NUM", "display": true, "sequence_position": 1.5, "example": "*three* cats", "title": "Numeral", "description": "A number word, like 'three' or 'first'."},
        {"value": "PART", "display": true, "sequence_position": 2.5, "example": "*to* go", "title": "Particle", "description": "A small function word that adds grammatical meaning, like 'to' in 'to go'."},
        {"value": "PHRASALV", "display": true, "sequence_position": 3.5, "example": "*give up*", "title": "Phrasal verb", "description": "A verb combined with a particle that changes its meaning, like 'give up'."},
        {"value": "PRON", "display": true, "sequence_position": 1.5, "example": "*she* runs", "title": "Pronoun", "description": "A word that stands in for a noun, like 'he', 'she', 'it', or 'they'."},
        {"value": "PUNCT", "display": false, "sequence_position": 1.5, "example": ". , ! ?", "title": "Punctuation", "description": "Marks like commas, periods, and question marks that structure writing."},
        {"value": "SCONJ", "display": true, "sequence_position": 2.5, "example": "*because* it rained", "title": "Subordinating conjunction", "description": "A word that joins a dependent clause to a main one, like 'because' or 'although'."},
        {"value": "SPACE", "display": false, "sequence_position": 1.5, "example": "(whitespace)", "title": "Space", "description": "Whitespace between words or tokens."},
        {"value": "SYM", "display": false, "sequence_position": 1.5, "example": "\$ % &", "title": "Symbol", "description": "A non-letter symbol used in text, like '\$' or '%'."},
        {"value": "VERB", "display": true, "sequence_position": 1.5, "example": "she *runs*", "title": "Verb", "description": "A word for an action or state, like 'run', 'is', or 'become'."},
        {"value": "X", "display": false, "sequence_position": 1.5, "example": "unclassified token", "title": "Other", "description": "A word that doesn't fit a standard part of speech."},
      ],
    },
    {
      "feature": "advtype",
      "feature_title": "Adverb type",
      "values": [
        {"value": "Adverbial", "display": true, "sequence_position": 2.5, "example": "she ran *fast*", "title": "Adverbial", "description": "An adverbial word or phrase modifying a verb or sentence."},
        {"value": "Tim", "display": true, "sequence_position": 1.5, "example": "*yesterday* I left", "title": "Time", "description": "An adverb of time, like 'yesterday' or 'soon'."},
      ],
    },
    {
      "feature": "aspect",
      "feature_title": "Aspect",
      "values": [
        {"value": "Imp", "display": true, "sequence_position": 3.5, "example": "she *was walking*", "title": "Imperfective", "description": "An ongoing or incomplete action, like 'was walking'."},
        {"value": "Perf", "display": true, "sequence_position": 3.5, "example": "she *has walked*", "title": "Perfective", "description": "A completed action viewed as a whole, like 'walked'."},
        {"value": "Prog", "display": true, "sequence_position": 2.5, "example": "she *is walking*", "title": "Progressive", "description": "An action in progress, like 'is walking'."},
        {"value": "Hab", "display": false, "sequence_position": 3.5, "example": "she *used to walk*", "title": "Habitual", "description": "A repeated or customary action, like 'used to walk'."},
      ],
    },
    {
      "feature": "case",
      "feature_title": "Case",
      "values": [
        {"value": "Nom", "display": true, "sequence_position": 1.5, "example": "*she* runs", "title": "Nominative", "description": "The case of the subject of a sentence."},
        {"value": "Acc", "display": true, "sequence_position": 2.5, "example": "I see *her*", "title": "Accusative", "description": "The case of the direct object."},
        {"value": "Dat", "display": false, "sequence_position": 3.5, "example": "I gave *her* a book", "title": "Dative", "description": "The case of the indirect object, often 'to' or 'for' someone."},
        {"value": "Gen", "display": true, "sequence_position": 2.5, "example": "the cat's *tail*", "title": "Genitive", "description": "The case showing possession or relation, like 'of' or 's."},
        {"value": "Voc", "display": false, "sequence_position": 5.5, "example": "O *Caesar*!", "title": "Vocative", "description": "The case used to address someone directly."},
        {"value": "Abl", "display": false, "sequence_position": 5.5, "example": "from the *house*", "title": "Ablative", "description": "The case marking movement away from or source."},
        {"value": "Loc", "display": false, "sequence_position": 5.5, "example": "at *home*", "title": "Locative", "description": "The case marking location, like 'in' or 'at' a place."},
        {"value": "All", "display": false, "sequence_position": 5.5, "example": "toward *home*", "title": "Allative", "description": "The case marking movement toward a place."},
        {"value": "Ins", "display": false, "sequence_position": 5.5, "example": "with a *pen*", "title": "Instrumental", "description": "The case marking the means or instrument of an action."},
        {"value": "Ess", "display": false, "sequence_position": 6.0, "example": "as a *teacher*", "title": "Essive", "description": "The case marking a temporary state, like 'as a teacher'."},
        {"value": "Tra", "display": false, "sequence_position": 6.0, "example": "became a *teacher*", "title": "Translative", "description": "The case marking change of state, like 'into' a teacher."},
        {"value": "Com", "display": false, "sequence_position": 5.5, "example": "with *friends*", "title": "Comitative", "description": "The case marking accompaniment, like 'with' someone."},
        {"value": "Par", "display": false, "sequence_position": 5.5, "example": "some *of the bread*", "title": "Partitive", "description": "The case marking a part of a whole."},
        {"value": "Adv", "display": false, "sequence_position": 5.5, "example": "adverbial form", "title": "Adverbial", "description": "A case used to form adverbial expressions."},
        {"value": "Ref", "display": false, "sequence_position": 6.0, "example": "referential form", "title": "Referential", "description": "A case used to refer to or about something."},
        {"value": "Rel", "display": false, "sequence_position": 6.0, "example": "relative form", "title": "Relative", "description": "A case marking a relationship between elements."},
        {"value": "Equ", "display": false, "sequence_position": 6.0, "example": "as big as *X*", "title": "Equative", "description": "The case marking equality or comparison, like 'as big as'."},
        {"value": "Dis", "display": false, "sequence_position": 6.0, "example": "one *per person*", "title": "Distributive", "description": "The case marking distribution, like 'one per person'."},
        {"value": "Abs", "display": false, "sequence_position": 6.0, "example": "absolutive form", "title": "Absolutive", "description": "In ergative languages, the case of subjects of intransitive verbs and objects of transitive ones."},
        {"value": "Erg", "display": false, "sequence_position": 6.0, "example": "ergative form", "title": "Ergative", "description": "In ergative languages, the case of the subject of a transitive verb."},
        {"value": "Cau", "display": false, "sequence_position": 6.0, "example": "because of *X*", "title": "Causal", "description": "The case marking cause or reason, like 'because of'."},
        {"value": "Ben", "display": false, "sequence_position": 5.5, "example": "for *someone*", "title": "Benefactive", "description": "The case marking the beneficiary of an action, like 'for someone'."},
        {"value": "Sub", "display": false, "sequence_position": 6.0, "example": "onto *X*", "title": "Sublative", "description": "The case marking movement onto or under a surface."},
        {"value": "Sup", "display": false, "sequence_position": 6.0, "example": "on *X*", "title": "Superessive", "description": "The case marking position on top of something."},
        {"value": "Tem", "display": false, "sequence_position": 5.5, "example": "on *Monday*", "title": "Temporal", "description": "The case marking a time, like 'on Monday'."},
        {"value": "Obl", "display": false, "sequence_position": 5.5, "example": "oblique form", "title": "Oblique", "description": "A general non-subject form of a noun or pronoun."},
        {"value": "Acc,Dat", "display": false, "sequence_position": 5.5, "example": "syncretic form", "title": "Accusative/Dative", "description": "A form that serves as both accusative and dative."},
        {"value": "Acc,Nom", "display": false, "sequence_position": 5.5, "example": "syncretic form", "title": "Accusative/Nominative", "description": "A form that serves as both accusative and nominative."},
        {"value": "Pre", "display": false, "sequence_position": 5.5, "example": "prepositional form", "title": "Prepositional", "description": "A case used after prepositions, common in some Slavic languages."},
      ],
    },
    {
      "feature": "conjtype",
      "feature_title": "Conjunction type",
      "values": [
        {"value": "Coord", "display": true, "sequence_position": 1.5, "example": "bread *and* butter", "title": "Coordinating", "description": "Joins equal parts of a sentence, like 'and' or 'but'."},
        {"value": "Sub", "display": true, "sequence_position": 2.5, "example": "*because* it rained", "title": "Subordinating", "description": "Connects a dependent clause to a main clause, like 'because'."},
        {"value": "Cmp", "display": true, "sequence_position": 3.5, "example": "taller *than* me", "title": "Comparative", "description": "Used in comparisons, like 'than' or 'as'."},
      ],
    },
    {
      "feature": "definite",
      "feature_title": "Definiteness",
      "values": [
        {"value": "Def", "display": true, "sequence_position": 1.5, "example": "*the* book", "title": "Definite", "description": "Refers to a specific known thing, like 'the' in English."},
        {"value": "Ind", "display": true, "sequence_position": 1.5, "example": "*a* book", "title": "Indefinite", "description": "Refers to a non-specific thing, like 'a' in English."},
        {"value": "Cons", "display": false, "sequence_position": 6.0, "example": "construct state form", "title": "Construct state", "description": "A noun form used in possessive constructions, common in Semitic languages."},
      ],
    },
    {
      "feature": "degree",
      "feature_title": "Degree",
      "values": [
        {"value": "Pos", "display": true, "sequence_position": 1.5, "example": "*big*", "title": "Positive", "description": "The base form of an adjective or adverb, like 'big'."},
        {"value": "Cmp", "display": true, "sequence_position": 2.5, "example": "*bigger*", "title": "Comparative", "description": "The comparing form, like 'bigger' or 'more big'."},
        {"value": "Sup", "display": true, "sequence_position": 2.5, "example": "*biggest*", "title": "Superlative", "description": "The highest-degree form, like 'biggest' or 'most big'."},
        {"value": "Abs", "display": false, "sequence_position": 5.5, "example": "*very big*", "title": "Absolute superlative", "description": "A very high degree without direct comparison, like 'very big'."},
      ],
    },
    {
      "feature": "evident",
      "feature_title": "Evidentiality",
      "values": [
        {"value": "Fh", "display": false, "sequence_position": 5.5, "example": "I saw it", "title": "Firsthand", "description": "Information the speaker directly experienced."},
        {"value": "Nfh", "display": false, "sequence_position": 5.5, "example": "apparently it happened", "title": "Non-firsthand", "description": "Information learned indirectly, like hearsay or inference."},
      ],
    },
    {
      "feature": "foreign",
      "feature_title": "Foreign",
      "values": [
        {"value": "Yes", "display": true, "sequence_position": 4.5, "example": "*café*, *sushi*", "title": "Foreign word", "description": "A word borrowed from another language."},
      ],
    },
    {
      "feature": "gender",
      "feature_title": "Gender",
      "values": [
        {"value": "Masc", "display": false, "sequence_position": 2.5, "example": "*he*, *him*", "title": "Masculine", "description": "Grammatically masculine, like 'he' or 'el chico'."},
        {"value": "Fem", "display": false, "sequence_position": 2.5, "example": "*she*, *her*", "title": "Feminine", "description": "Grammatically feminine, like 'she' or 'la chica'."},
        {"value": "Neut", "display": false, "sequence_position": 2.5, "example": "*it*", "title": "Neuter", "description": "Grammatically neither masculine nor feminine, like 'it' or German 'das'."},
        {"value": "Com", "display": false, "sequence_position": 5.5, "example": "common gender form", "title": "Common", "description": "A combined non-neuter gender used in some languages."},
      ],
    },
    {
      "feature": "mood",
      "feature_title": "Mood",
      "values": [
        {"value": "Ind", "display": true, "sequence_position": 1.5, "example": "she *runs*", "title": "Indicative", "description": "States a fact, like 'she runs'."},
        {"value": "Imp", "display": true, "sequence_position": 2.5, "example": "*run!*", "title": "Imperative", "description": "Gives a command, like 'run!'"},
        {"value": "Sub", "display": true, "sequence_position": 4.5, "example": "if I *were* you", "title": "Subjunctive", "description": "Expresses wishes, doubts, or hypotheticals, like 'if I were'."},
        {"value": "Cnd", "display": true, "sequence_position": 3.5, "example": "I *would* run", "title": "Conditional", "description": "Expresses what would happen, like 'I would run'."},
        {"value": "Opt", "display": false, "sequence_position": 5.5, "example": "*may* you live long", "title": "Optative", "description": "Expresses a wish, like 'may you live long'."},
        {"value": "Jus", "display": false, "sequence_position": 5.5, "example": "*let* them go", "title": "Jussive", "description": "A third-person command, like 'let them go'."},
        {"value": "Adm", "display": false, "sequence_position": 6.0, "example": "admirative form", "title": "Admirative", "description": "Expresses surprise about new information."},
        {"value": "Des", "display": false, "sequence_position": 5.5, "example": "*wants to* run", "title": "Desiderative", "description": "Expresses desire to do something, like 'wants to run'."},
        {"value": "Nec", "display": false, "sequence_position": 4.5, "example": "*must* run", "title": "Necessitative", "description": "Expresses necessity, like 'must run'."},
        {"value": "Pot", "display": false, "sequence_position": 4.5, "example": "*might* run", "title": "Potential", "description": "Expresses possibility, like 'might run'."},
        {"value": "Prp", "display": false, "sequence_position": 5.5, "example": "*in order to* run", "title": "Purposive", "description": "Expresses purpose, like 'in order to run'."},
        {"value": "Qot", "display": false, "sequence_position": 5.5, "example": "they *said*", "title": "Quotative", "description": "Marks reported speech, like 'they said'."},
        {"value": "Int", "display": true, "sequence_position": 1.5, "example": "*do* you run?", "title": "Interrogative", "description": "Forms a question, like 'do you run?'"},
      ],
    },
    {
      "feature": "nountype",
      "feature_title": "Noun type",
      "values": [
        {"value": "Prop", "display": true, "sequence_position": 1.5, "example": "*Paris*", "title": "Proper noun", "description": "A name of a specific person, place, or thing, like 'Paris'."},
        {"value": "Comm", "display": true, "sequence_position": 1.5, "example": "*city*", "title": "Common noun", "description": "A general noun, like 'city' or 'book'."},
        {"value": "Not_proper", "display": false, "sequence_position": 1.5, "example": "*book*", "title": "Not proper", "description": "A noun that is not a proper name."},
      ],
    },
    {
      "feature": "numform",
      "feature_title": "Number form",
      "values": [
        {"value": "Digit", "display": false, "sequence_position": 1.5, "example": "*7*", "title": "Digit", "description": "A number written with digits, like '7'."},
        {"value": "Word", "display": true, "sequence_position": 1.5, "example": "*seven*", "title": "Word", "description": "A number written as a word, like 'seven'."},
        {"value": "Roman", "display": false, "sequence_position": 4.5, "example": "*VII*", "title": "Roman numeral", "description": "A number written with Roman numerals, like 'VII'."},
        {"value": "Letter", "display": false, "sequence_position": 6.0, "example": "letter-based numeral", "title": "Letter", "description": "A number written using letters, like Hebrew alphabet numerals."},
      ],
    },
    {
      "feature": "numtype",
      "feature_title": "Number type",
      "values": [
        {"value": "Card", "display": true, "sequence_position": 1.5, "example": "*one*, *three*", "title": "Cardinal", "description": "A counting number, like 'one' or 'three'."},
        {"value": "Ord", "display": true, "sequence_position": 2.5, "example": "*first*, *third*", "title": "Ordinal", "description": "A ranking number, like 'first' or 'third'."},
        {"value": "Mult", "display": true, "sequence_position": 3.5, "example": "*twice*, *triple*", "title": "Multiplicative", "description": "Expresses how many times, like 'twice' or 'triple'."},
        {"value": "Frac", "display": true, "sequence_position": 3.5, "example": "*half*, *quarter*", "title": "Fractional", "description": "A fraction, like 'half' or 'quarter'."},
        {"value": "Sets", "display": false, "sequence_position": 4.5, "example": "*pair*, *dozen*", "title": "Sets", "description": "A number describing sets, like 'pair' or 'dozen'."},
        {"value": "Range", "display": false, "sequence_position": 4.5, "example": "*two to five*", "title": "Range", "description": "A range of numbers, like 'two to five'."},
        {"value": "Dist", "display": false, "sequence_position": 5.5, "example": "*one each*", "title": "Distributive", "description": "Distributes a number, like 'one each'."},
      ],
    },
    {
      "feature": "number",
      "feature_title": "Number",
      "values": [
        {"value": "Sing", "display": true, "sequence_position": 1.5, "example": "*cat*", "title": "Singular", "description": "Refers to one, like 'cat'."},
        {"value": "Plur", "display": true, "sequence_position": 1.5, "example": "*cats*", "title": "Plural", "description": "Refers to more than one, like 'cats'."},
        {"value": "Dual", "display": false, "sequence_position": 5.5, "example": "dual form", "title": "Dual", "description": "Refers to exactly two, used in some languages."},
        {"value": "Tri", "display": false, "sequence_position": 6.0, "example": "trial form", "title": "Trial", "description": "Refers to exactly three, found in a few languages."},
        {"value": "Pauc", "display": false, "sequence_position": 6.0, "example": "paucal form", "title": "Paucal", "description": "Refers to a few, distinct from singular and plural."},
        {"value": "Grpa", "display": false, "sequence_position": 6.0, "example": "greater paucal form", "title": "Greater paucal", "description": "Refers to a larger few, between paucal and plural."},
        {"value": "Grpl", "display": false, "sequence_position": 6.0, "example": "greater plural form", "title": "Greater plural", "description": "Refers to an especially large group."},
        {"value": "Inv", "display": false, "sequence_position": 6.0, "example": "inverse number form", "title": "Inverse number", "description": "Marks the less expected number for a noun class."},
      ],
    },
    {
      "feature": "number[psor]",
      "feature_title": "Possessor number",
      "values": [
        {"value": "Sing", "display": true, "sequence_position": 2.5, "example": "*my* book", "title": "Singular possessor", "description": "The owner is one person or thing, like 'my' or 'his'."},
        {"value": "Plur", "display": true, "sequence_position": 2.5, "example": "*our* book", "title": "Plural possessor", "description": "The owners are more than one, like 'our' or 'their'."},
        {"value": "Dual", "display": false, "sequence_position": 5.5, "example": "dual possessor form", "title": "Dual possessor", "description": "Exactly two owners, used in some languages."},
      ],
    },
    {
      "feature": "person",
      "feature_title": "Person",
      "values": [
        {"value": "0", "display": false, "sequence_position": 5.5, "example": "*one* says", "title": "Zero person", "description": "An impersonal or generic subject, like 'one says'."},
        {"value": "1", "display": true, "sequence_position": 1.5, "example": "*I*, *we*", "title": "First person", "description": "Refers to the speaker, like 'I' or 'we'."},
        {"value": "2", "display": true, "sequence_position": 1.5, "example": "*you*", "title": "Second person", "description": "Refers to the listener, like 'you'."},
        {"value": "3", "display": true, "sequence_position": 1.5, "example": "*he*, *she*, *they*", "title": "Third person", "description": "Refers to someone or something else, like 'he', 'she', or 'they'."},
        {"value": "4", "display": false, "sequence_position": 6.0, "example": "fourth-person form", "title": "Fourth person", "description": "A separate third-person referent used in some languages."},
      ],
    },
    {
      "feature": "polarity",
      "feature_title": "Polarity",
      "values": [
        {"value": "Pos", "display": true, "sequence_position": 1.5, "example": "she *is* tall", "title": "Positive", "description": "An affirmative form, like 'is' or 'do'."},
        {"value": "Neg", "display": true, "sequence_position": 1.5, "example": "she *isn't* tall", "title": "Negative", "description": "A negated form, like 'isn't' or 'don't'."},
      ],
    },
    {
      "feature": "polite",
      "feature_title": "Politeness",
      "values": [
        {"value": "Infm", "display": false, "sequence_position": 3.5, "example": "informal form", "title": "Informal", "description": "A casual form used with friends or family."},
        {"value": "Form", "display": false, "sequence_position": 3.5, "example": "formal form", "title": "Formal", "description": "A polite form used to show respect."},
        {"value": "Elev", "display": false, "sequence_position": 5.5, "example": "elevated form", "title": "Elevated", "description": "An especially respectful form for the listener."},
        {"value": "Humb", "display": false, "sequence_position": 5.5, "example": "humble form", "title": "Humble", "description": "A form humbling the speaker in deference."},
      ],
    },
    {
      "feature": "poss",
      "feature_title": "Possessive",
      "values": [
        {"value": "Yes", "display": true, "sequence_position": 2.5, "example": "*my*, *their*", "title": "Possessive", "description": "Indicates ownership, like 'my' or 'their'."},
      ],
    },
    {
      "feature": "prepcase",
      "feature_title": "Prepositional case",
      "values": [
        {"value": "Npr", "display": false, "sequence_position": 5.5, "example": "non-prepositional form", "title": "Non-prepositional", "description": "A form not used with a preposition."},
      ],
    },
    {
      "feature": "prontype",
      "feature_title": "Pronoun type",
      "values": [
        {"value": "Prs", "display": true, "sequence_position": 1.5, "example": "*I*, *she*", "title": "Personal", "description": "Refers to a person, like 'I' or 'she'."},
        {"value": "Int", "display": true, "sequence_position": 2.5, "example": "*who*, *what*", "title": "Interrogative", "description": "Asks a question, like 'who' or 'what'."},
        {"value": "Rel", "display": true, "sequence_position": 3.5, "example": "the man *who* left", "title": "Relative", "description": "Introduces a relative clause, like 'who' or 'that'."},
        {"value": "Dem", "display": true, "sequence_position": 1.5, "example": "*this*, *that*", "title": "Demonstrative", "description": "Points to something, like 'this' or 'that'."},
        {"value": "Tot", "display": true, "sequence_position": 2.5, "example": "*all*, *every*", "title": "Total", "description": "Refers to everyone or everything, like 'all' or 'every'."},
        {"value": "Neg", "display": true, "sequence_position": 2.5, "example": "*nobody*, *nothing*", "title": "Negative", "description": "Refers to no one or nothing, like 'nobody' or 'nothing'."},
        {"value": "Art", "display": false, "sequence_position": 1.5, "example": "*the*, *a*", "title": "Article", "description": "Functions like 'a' or 'the' in some languages."},
        {"value": "Emp", "display": true, "sequence_position": 3.5, "example": "*myself*", "title": "Emphatic", "description": "Adds emphasis, like 'himself' or 'myself'."},
        {"value": "Exc", "display": false, "sequence_position": 4.5, "example": "*what* a day!", "title": "Exclamative", "description": "Used in exclamations, like 'what a day!'"},
        {"value": "Ind", "display": true, "sequence_position": 2.5, "example": "*someone*, *anything*", "title": "Indefinite", "description": "Refers to something unspecified, like 'someone' or 'anything'."},
        {"value": "Rcp", "display": true, "sequence_position": 3.5, "example": "*each other*", "title": "Reciprocal", "description": "Refers to each other, like 'each other'."},
        {"value": "Int,Rel", "display": false, "sequence_position": 4.5, "example": "*who*", "title": "Interrogative/Relative", "description": "A pronoun that can be either question or relative, like 'who'."},
      ],
    },
    {
      "feature": "punctside",
      "feature_title": "Punctuation side",
      "values": [
        {"value": "Ini", "display": false, "sequence_position": 1.5, "example": "*(* *[*", "title": "Initial", "description": "An opening punctuation mark, like '(' or '['."},
        {"value": "Fin", "display": false, "sequence_position": 1.5, "example": "*)* *]*", "title": "Final", "description": "A closing punctuation mark, like ')' or ']'."},
      ],
    },
    {
      "feature": "puncttype",
      "feature_title": "Punctuation type",
      "values": [
        {"value": "Brck", "display": false, "sequence_position": 1.5, "example": "*(* *[*", "title": "Bracket", "description": "A bracket-like mark, such as '(' or '['."},
        {"value": "Dash", "display": false, "sequence_position": 1.5, "example": "*-* *—*", "title": "Dash", "description": "A dash or hyphen, like '-' or '—'."},
        {"value": "Excl", "display": false, "sequence_position": 1.5, "example": "*!*", "title": "Exclamation", "description": "An exclamation mark, '!'."},
        {"value": "Peri", "display": false, "sequence_position": 1.5, "example": "*.*", "title": "Period", "description": "A period or full stop, '.'."},
        {"value": "Qest", "display": false, "sequence_position": 1.5, "example": "*?*", "title": "Question", "description": "A question mark, '?'."},
        {"value": "Quot", "display": false, "sequence_position": 1.5, "example": "*\"*", "title": "Quotation", "description": "A quotation mark, like '\"'."},
        {"value": "Semi", "display": false, "sequence_position": 1.5, "example": "*;*", "title": "Semicolon", "description": "A semicolon, ';'."},
        {"value": "Colo", "display": false, "sequence_position": 1.5, "example": "*:*", "title": "Colon", "description": "A colon, ':'."},
        {"value": "Comm", "display": false, "sequence_position": 1.5, "example": "*,*", "title": "Comma", "description": "A comma, ','."},
      ],
    },
    {
      "feature": "reflex",
      "feature_title": "Reflexive",
      "values": [
        {"value": "Yes", "display": true, "sequence_position": 3.5, "example": "*myself*, *herself*", "title": "Reflexive", "description": "Refers back to the subject, like 'myself' or 'herself'."},
      ],
    },
    {
      "feature": "tense",
      "feature_title": "Tense",
      "values": [
        {"value": "Pres", "display": true, "sequence_position": 1.5, "example": "she *walks*", "title": "Present", "description": "Something happening now, like 'walks'."},
        {"value": "Past", "display": true, "sequence_position": 1.5, "example": "she *walked*", "title": "Past", "description": "Something that already happened, like 'walked'."},
        {"value": "Fut", "display": true, "sequence_position": 2.5, "example": "she *will walk*", "title": "Future", "description": "Something that will happen, like 'will walk'."},
        {"value": "Imp", "display": false, "sequence_position": 3.5, "example": "she *was walking*", "title": "Imperfect", "description": "An ongoing or habitual past action, like 'was walking'."},
        {"value": "Pqp", "display": true, "sequence_position": 4.5, "example": "she *had walked*", "title": "Pluperfect", "description": "An action completed before another past action, like 'had walked'."},
        {"value": "Aor", "display": false, "sequence_position": 5.5, "example": "aorist form", "title": "Aorist", "description": "A simple past action viewed as a whole, common in Greek and Slavic."},
        {"value": "Eps", "display": false, "sequence_position": 6.0, "example": "episodic past form", "title": "Episodic past", "description": "A specific past episode, used in some languages."},
        {"value": "Prosp", "display": false, "sequence_position": 4.5, "example": "she *is going to walk*", "title": "Prospective", "description": "An action about to happen, like 'is going to walk'."},
      ],
    },
    {
      "feature": "verbform",
      "feature_title": "Verb form",
      "values": [
        {"value": "Fin", "display": true, "sequence_position": 1.5, "example": "she *runs*", "title": "Finite", "description": "A conjugated verb that agrees with its subject, like 'runs'."},
        {"value": "Inf", "display": true, "sequence_position": 1.5, "example": "*to run*", "title": "Infinitive", "description": "The base form of a verb, like 'to run'."},
        {"value": "Sup", "display": false, "sequence_position": 6.0, "example": "supine form", "title": "Supine", "description": "A verb form used for purpose, common in Latin and Swedish."},
        {"value": "Part", "display": true, "sequence_position": 3.5, "example": "*running*, *broken*", "title": "Participle", "description": "A verb form used as an adjective, like 'running' or 'broken'."},
        {"value": "Conv", "display": false, "sequence_position": 6.0, "example": "converb form", "title": "Converb", "description": "A non-finite verb form that links clauses adverbially."},
        {"value": "Vnoun", "display": false, "sequence_position": 5.5, "example": "verbal noun form", "title": "Verbal noun", "description": "A noun form derived from a verb, like 'running' as a noun."},
        {"value": "Ger", "display": true, "sequence_position": 3.5, "example": "*running* is fun", "title": "Gerund", "description": "An '-ing' verb form used as a noun, like 'running is fun'."},
        {"value": "Adn", "display": false, "sequence_position": 6.0, "example": "adnominal form", "title": "Adnominal", "description": "A verb form modifying a noun, like Korean adnominal endings."},
        {"value": "Lng", "display": false, "sequence_position": 6.0, "example": "long verb form", "title": "Long form", "description": "A longer or fuller form of a verb, used in some languages."},
      ],
    },
    {
      "feature": "verbtype",
      "feature_title": "Verb type",
      "values": [
        {"value": "Mod", "display": true, "sequence_position": 2.5, "example": "*can*, *must*", "title": "Modal", "description": "Expresses possibility, necessity, or permission, like 'can' or 'must'."},
        {"value": "Caus", "display": false, "sequence_position": 4.5, "example": "*made* him run", "title": "Causative", "description": "Indicates causing an action, like 'make someone do' something."},
      ],
    },
    {
      "feature": "voice",
      "feature_title": "Voice",
      "values": [
        {"value": "Act", "display": true, "sequence_position": 1.5, "example": "she *wrote* a book", "title": "Active", "description": "The subject does the action, like 'she wrote a book'."},
        {"value": "Mid", "display": false, "sequence_position": 5.5, "example": "middle voice form", "title": "Middle", "description": "The subject acts on or for itself, between active and passive."},
        {"value": "Pass", "display": true, "sequence_position": 3.5, "example": "the book *was written*", "title": "Passive", "description": "The subject receives the action, like 'the book was written'."},
        {"value": "Antip", "display": false, "sequence_position": 6.0, "example": "antipassive form", "title": "Antipassive", "description": "In ergative languages, demotes the object so the agent surfaces as subject."},
        {"value": "Cau", "display": false, "sequence_position": 5.5, "example": "causative voice form", "title": "Causative", "description": "Marks a verb whose subject causes the action."},
        {"value": "Dir", "display": false, "sequence_position": 6.0, "example": "direct voice form", "title": "Direct", "description": "A direct voice form, used in some inverse-marking systems."},
        {"value": "Inv", "display": false, "sequence_position": 6.0, "example": "inverse voice form", "title": "Inverse", "description": "An inverse voice form, used in some inverse-marking systems."},
        {"value": "Rcp", "display": false, "sequence_position": 4.5, "example": "they *hugged each other*", "title": "Reciprocal", "description": "The participants act on each other, like 'they hugged each other'."},
        {"value": "Caus", "display": false, "sequence_position": 5.5, "example": "*made* him run", "title": "Causative", "description": "Indicates causing an action, like 'made him run'."},
      ],
    },
    {
      "feature": "x",
      "feature_title": "Other",
      "values": [
        {"value": "X", "display": false, "sequence_position": 1.5, "example": "unclassified", "title": "Other", "description": "A value that doesn't fit a standard category."},
      ],
    },
  ],
};
