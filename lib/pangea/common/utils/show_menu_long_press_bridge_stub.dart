/// Native platforms publish long-press and custom semantics actions to the
/// screen reader directly; only web needs the `contextmenu` bridge.
class ShowMenuLongPressBridge {
  static void install() =>
      throw UnsupportedError('ShowMenuLongPressBridge is only needed on web');
}
