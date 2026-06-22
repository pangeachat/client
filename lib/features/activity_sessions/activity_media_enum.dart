enum MediaEnum { images, videos, voiceMessages, nan }

extension MediaEnumExtension on MediaEnum {
  MediaEnum fromString(String value) {
    switch (value) {
      case 'images':
        return MediaEnum.images;
      case 'videos':
        return MediaEnum.videos;
      case 'voice_messages':
        return MediaEnum.voiceMessages;
      case 'nan':
        return MediaEnum.nan;
      default:
        return MediaEnum.nan;
    }
  }

  String get string {
    switch (this) {
      case MediaEnum.images:
        return 'images';
      case MediaEnum.videos:
        return 'videos';
      case MediaEnum.voiceMessages:
        return 'voice_messages';
      case MediaEnum.nan:
        return 'nan';
    }
  }
}
