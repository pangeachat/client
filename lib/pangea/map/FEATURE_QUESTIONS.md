# Map Navigation Feature - Questions & Specifications

## Feature Overview

The map navigation feature will use flutter_map to create a navigatable/zoomable map with markers. The markers are pulled from the server's topic location list, and clicking on a marker opens a bottom sheet with topic information (image, title, description).

## Outstanding Questions

### 1. Data Source & API Integration

**Q:** Should the map feature integrate with the existing `CourseLocationRepo` and `CourseTopicModel` systems, or will it use a different data source?

- Existing system fetches from CMS API via `CmsCoursePlanTopicLocation`
- Coordinates are stored as `[longitude, latitude]` arrays
- Media is handled through `CourseLocationMediaRepo`

It should use the CourseLocationRepo and the locations found there. If long/lat are not present, it should generate random values.

**Q:** Should we use the same coordinate format `[longitude, latitude]` as the existing system?

yes

### 2. Navigation & Routing

**Q:** Where should the map feature be accessible from?

- Option A: New route (e.g., `/map`)
- Option B: Integrated into existing course/space detail pages
- Option C: Part of the navigation rail/menu system
- Option D: Multiple access points

Go with A for now. We'll integrate later.

**Q:** Should the map be course-specific (showing only locations for a particular course) or global (showing all available locations)?

It will show all location and highlight those in a specific course.

### 3. Bottom Sheet Content

**Q:** What specific information should be displayed in the bottom sheet beyond image, title, and description?

- Course topic details?
- Activity information?
- Progress indicators?
- User completion status?

numbers of activities, and number of activities completed

**Q:** Should the bottom sheet include action buttons?

- "Go to Topic"
- "Start Activity"
- "View Course Details"
- "Save/Bookmark Location"

Just "Go"

**Q:** Should the bottom sheet allow navigation to related course content or activities?

- there should be a vertical side nav bar with 1. user avatar (linking to user analytics), 2. any courses they're in 3. a new course button

### 4. Map Functionality

**Q:** What should be the default zoom level and center point?

- Global view showing all locations?
- Regional focus?
- User's current location (if permissions allow)?

Global

**Q:** Should the map support clustering when there are many markers close together?

Yes

**Q:** Do you want search/filter functionality?

- Search by topic location name (the city)
- Filter by course
- Filter by completion status
- Filter by difficulty level

search by topic location name

**Q:** Should users be able to bookmark or save favorite locations?

no

### 5. User Context & Personalization

**Q:** Should the map show different markers or information based on the user's progress?

- Different colors for completed vs. uncompleted topics
- Locked/unlocked indicators
- Progress percentages

locked/unlocked indicators

**Q:** Should it highlight the user's current topic or recommended next steps?

**Q:** Do you want to show user location or allow location-based features?

- GPS integration
- "Near me" functionality
- Distance calculations

not at the moment. possibly later

### 6. Integration with Existing Features

**Q:** Should we reuse/extend the existing `MapBubble` component or create something new?

make something different

- Current `MapBubble` is used for location messages in chat
- Located at `/lib/pages/chat/events/map_bubble.dart`

**Q:** Should the map feature integrate with existing analytics/progress tracking?

- Track map interactions
- Monitor location visits
- Integration with `ActivitySummariesProvider`

seeing complete activities, yes

### 7. Permissions & Access Control

**Q:** Should the map be available to all users or only those enrolled in courses with location-based content?

all

**Q:** Are there specific permissions needed for viewing certain locations?

- Course enrollment requirements
- Subscription level restrictions
- Geographic restrictions

no

### 8. Technical Architecture

**Q:** Should the map controller follow the existing pattern with separate state/controller file (`map.dart`) and view file (`map_view.dart`)?

yes

**Q:** How should we handle offline functionality?

- Cache map tiles
- Store location data locally
- Graceful degradation when offline

cache some map tiles

**Q:** Performance considerations for large numbers of markers?

- Pagination
- Lazy loading
- Viewport-based loading

lazy loading if possible

### 9. UI/UX Considerations

**Q:** Should the map have a consistent theme with the rest of the app?

- Custom map styling
- Marker design consistency
- Bottom sheet styling

yes

**Q:** Mobile responsiveness requirements?

- Touch gestures
- Different layouts for phone vs. tablet
- Integration with existing responsive patterns

not yet

**Q:** Accessibility considerations?

- Screen reader support
- Keyboard navigation
- High contrast mode support

if possible, yes

## Next Steps

Once these questions are answered, we can proceed with:

1. Detailed technical specification
2. Implementation plan
3. Testing strategy
4. Integration with existing codebase
