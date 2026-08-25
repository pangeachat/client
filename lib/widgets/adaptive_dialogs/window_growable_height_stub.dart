/// Non-web builds have no browser window to measure, and the screen-size
/// warning never runs there (`MatrixState._checkScreenSize` is `kIsWeb`-gated).
double windowGrowableHeight() =>
    throw UnsupportedError('windowGrowableHeight can only be measured on web');
