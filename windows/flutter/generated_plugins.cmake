#
# Generated file, do not edit.
#

list(APPEND FLUTTER_PLUGIN_LIST
  app_links
  audioplayers_windows
  dynamic_color
  emoji_picker_flutter
  file_selector_windows
  firebase_core
  flutter_secure_storage_windows
  flutter_tts
  flutter_webrtc
  geolocator_windows
  pasteboard
  permission_handler_windows
  record_windows
  rive_common
  sentry_flutter
  share_plus
  sqlcipher_flutter_libs
  url_launcher_windows
  window_to_front
)

list(APPEND FLUTTER_FFI_PLUGIN_LIST
  flutter_vodozemac
)

set(PLUGIN_BUNDLED_LIBRARIES)

foreach(plugin ${FLUTTER_PLUGIN_LIST})
  add_subdirectory(flutter/ephemeral/.plugin_symlinks/${plugin}/windows plugins/${plugin})
  target_link_libraries(${BINARY_NAME} PRIVATE ${plugin}_plugin)
  list(APPEND PLUGIN_BUNDLED_LIBRARIES $<TARGET_FILE:${plugin}_plugin>)
  list(APPEND PLUGIN_BUNDLED_LIBRARIES ${${plugin}_bundled_libraries})
endforeach(plugin)

foreach(ffi_plugin ${FLUTTER_FFI_PLUGIN_LIST})
  add_subdirectory(flutter/ephemeral/.plugin_symlinks/${ffi_plugin}/windows plugins/${ffi_plugin})
  list(APPEND PLUGIN_BUNDLED_LIBRARIES ${${ffi_plugin}_bundled_libraries})
endforeach(ffi_plugin)
