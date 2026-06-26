/// Which "side" of the dual-mode shell a given install is locked into.
///
/// • [undecided] — first launch, the beacon has not yet weighed in
/// • [portal]    — paid/attributed user, shows the portal stage (WebView)
/// • [arcade]    — organic user, shows the native arcade gameplay
///
/// Once the beacon has answered, the chosen branch is sticky — even if
/// the user later gets a network connection on a previously-arcade
/// install, we never re-ask. That decision is made server-side.
enum ShellMode {
  undecided,
  portal,
  arcade;

  static const _slugUndecided = 'undecided';
  static const _slugPortal = 'portal';
  static const _slugArcade = 'arcade';

  /// Reads back the persisted enum value. Unknown / missing → [undecided].
  static ShellMode parse(String? slug) {
    switch (slug) {
      case _slugPortal:
        return ShellMode.portal;
      case _slugArcade:
        return ShellMode.arcade;
      default:
        return ShellMode.undecided;
    }
  }

  /// Serialised form for SharedPreferences. Plain strings — small enough
  /// that storing the enum index would not buy anything readable.
  String get slug => switch (this) {
        ShellMode.portal => _slugPortal,
        ShellMode.arcade => _slugArcade,
        ShellMode.undecided => _slugUndecided,
      };
}
