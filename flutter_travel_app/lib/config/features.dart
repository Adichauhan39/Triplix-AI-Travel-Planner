/// Switches for features that are built but not offered yet.
///
/// A switch rather than a deletion: the code stays tested and in step with
/// everything around it, and turning a feature back on is one line instead of
/// digging it out of history and fixing whatever moved underneath it.
library;

/// Paying people back from the settlement -- the UPI button, "settle up",
/// and saving your own UPI id.
///
/// Off for now by decision, not because it is broken. Payments already
/// recorded still count towards who owes whom, and still show under "Already
/// paid back", so turning this off never makes a settled debt reappear.
const bool kPaymentsEnabled = false;
