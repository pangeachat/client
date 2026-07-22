/// No-op off web — GA app streams report screens natively via
/// firebase_screen; only the web layer needs the page_title override.
/// Web implementation: ga_page_title_web.dart.
void setGaPageTitle(String name) {}
