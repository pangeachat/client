---
applyTo: "lib/routes/chat/chat_details/space_details_content.dart,lib/routes/chat/chat_details/course_overview/course_overview.dart,lib/routes/chat/chat_details/course_overview/course_section_*.dart,lib/routes/chat/chat_details/course_overview/course_chats_preview.dart"
description: "The course page's sections and their shared header (the title, See all, section shortcuts, and how the header fits a narrow screen), plus the Chats section and its New course chat button."
---

# Course Page

The course page is the course card's main view. It is a column of sections, divided by full-width dividers: **Activities**, **Chats**, **Leaderboard** and **More**. The Activities row is in [quests.instructions.md](quests.instructions.md#the-activities-row-on-the-course-page) and the Leaderboard is in [course-leaderboard.instructions.md](course-leaderboard.instructions.md).

## The section header

Every section starts with the same header ([`CourseSectionHeader`](../../lib/routes/chat/chat_details/course_overview/course_section_header.dart)): the section's icon, its title, and the section's actions.

- **See all** ([`CourseSectionButton`](../../lib/routes/chat/chat_details/course_overview/course_section_button.dart)) opens the section's full subpage inside the card. It shows only when the subpage holds more than the section does. Its visible label is always "See all". Its accessible name adds the section title, so a screen reader can tell the sections' buttons apart.
- **A shortcut** ([`CourseSectionShortcut`](../../lib/routes/chat/chat_details/course_overview/course_section_shortcut.dart)) is the one action a section offers besides See all, placed before it. By default it is an icon, and its name is in the tooltip and accessible name. A shortcut that people miss as an icon also shows its name as a visible label beside the icon.
- **Fit.** The title and actions share one line when they fit. When they don't, which usually means a narrow phone with a labeled shortcut and See all, the actions move to a second line under the title, aligned to the end. Nothing is cut or shortened to keep everything on one line.

## The Chats section

The section ([`CourseChatsPreview`](../../lib/routes/chat/chat_details/course_overview/course_chats_preview.dart)) shows the course chats the viewer has joined, then chats they can join, two at most. For a course admin, suggestions to create the Introductions and Announcements chats appear above them. See all opens the full list. A student who has nothing to show sees no Chats section at all.

A course admin who can add chats to the course gets a **New course chat** button in the header, with a visible label ([client#9492](https://github.com/pangeachat/client/issues/9492)). As an icon-only shortcut it went unnoticed: teachers in a pilot did not find it and made no group chats. Students never see it. It opens the same chat creation as **Create group chat** in the More section.
