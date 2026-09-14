---
applyTo: "lib/features/user/**, lib/routes/new_private_chat/**, lib/routes/chat/chat_details/invite/**"
description: "Finding a person by name — the two sources every user-search surface offers, which directory the search uses, and how a rate-limited search must fail."
---

# Finding People

Two surfaces let a learner find a person by name: the **New Direct Message** panel, to start a chat, and the **invite page**, to add someone to a chat, course or activity session. Both answer a typed name through the same shared search, so a name that finds someone on one finds them on the other.

## The two sources

| Source | Where it comes from | Cost |
|---|---|---|
| **My contacts** | the people the learner already has a direct chat with | local; answers every keystroke |
| **Public** | the homeserver's user directory | a network request, rate-limited |

Contacts comes first and is what the New Direct Message panel opens on, because the person a learner wants is usually someone they have already spoken to, and that list costs nothing to search. The invite page offers the same two, plus its room-scoped filters — in this space, participants, invited, knocking, banned — which only mean anything against a room.

## Who is findable under Public

The directory returns someone only if they have allowed their profile to be found in search, or if they already share a room with the searcher. That rule is the server's; [limit-user-directory.instructions.md](../../../synapse-pangea-chat/.github/instructions/limit-user-directory.instructions.md) in `synapse-pangea-chat` owns it. So when a Public search comes back empty, the surface says the person may need to allow their profile to be found — that is the usual cause, not a misspelling.

A search matches the start of any word in a display name or Matrix ID, so part of a name is enough. A full Matrix ID works too, and on the invite page an ID the directory does not return is still offered, so a known person can be invited by hand.

## Which directory, and why it matters

Public search goes to Pangea's own directory endpoint rather than the stock Matrix one. The stock endpoint takes a fixed batch of candidates from the database and only then hides the ones the searcher may not see, so a search whose best matches are all private comes back empty. The Pangea endpoint applies that visibility rule inside the query, so what it returns is what the searcher can actually use.

## Failing without lying

The server allows only a small number of searches per minute per person, and search-as-you-type can reach that limit. A refused search must never look like an answer:

- A failed search **keeps the results already on screen** and shows the error. Blanking the list would read as "nobody by that name".
- Re-typing a term already shown does not spend a request.
- A response that arrives after the learner has typed something newer is discarded, so the list never shows results for a term they have moved off.
