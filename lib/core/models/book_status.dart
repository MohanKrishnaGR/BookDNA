enum BookStatus {
  unread,
  reading,
  read;

  String get label => switch (this) {
        BookStatus.unread => 'Unread',
        BookStatus.reading => 'Reading',
        BookStatus.read => 'Finished',
      };
}
