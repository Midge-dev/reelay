import 'dart:math';

/// The line of personality under a wait — the loading screen's, and the
/// last step of setup's. One is picked at random each time; add more in the
/// same shape: sentence case, short enough for one line, ending in "…".
const loadingLines = [
  'Buttering the popcorn…',
  'Untangling the film reel…',
  'Dimming the house lights…',
  'Rewinding to the good part…',
  'Waking up the projectionist…',
  'Finding your seat…',
  'Polishing the popcorn bucket…',
  'Cueing up the trailers…',
  'Sweet-talking the server…',
  'Chasing down the end credits…',
  'Shushing the back row…',
  'Refilling the soda machine…',
  'Threading the projector…',
  'Counting down from ten…',
  'Focusing the lens…',
  'Splicing the reels together…',
  'Warming up the projector bulb…',
  'Rolling out the red carpet…',
  'Saving you the aisle seat…',
  'Turning phones to silent…',
  'Sneaking in the snacks…',
  'Settling the snack debate…',
  'Checking for spoilers…',
  'Tuning the surround sound…',
  'Adjusting the tracking…',
  'Finding the remote in the couch…',
  'Dusting off the director’s cut…',
  'Lining up the opening credits…',
];

String pickLoadingLine([Random? random]) => loadingLines[(random ?? Random()).nextInt(loadingLines.length)];
