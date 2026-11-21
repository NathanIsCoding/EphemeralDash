import ddf.minim.analysis.*;

// Audio visualizer for the main menu: a row of dots across the middle of the screen
// that stretch into bars, up and down from the centre line, as the menu track plays.
//
// How tall the bars are overall follows how loud the music is right now, so the whole
// row pumps with the beat. Each bar also follows its own slice of the pitch range
// (bass, mids, treble), so neighbours move differently. The slices are scattered
// along the row in a fixed order, so it reads as one shape rather than a spectrum.
// Each bar's colour runs from cool to warm with its height.

final int VIS_POINTS = 80; // dots along the line
final float VIS_Y = 0.5; // centre line, as a fraction of the window height
final float VIS_HEIGHT = 0.4; // tallest bar's reach above (and below) the line, as a fraction of the height
final float VIS_GAIN = 3.0; // scales the loudness up: music rarely reaches full scale
final float VIS_MARGIN = 40; // pixels kept clear at each side
final float VIS_WEIGHT = 5; // dot diameter and bar width in pixels
final float VIS_SPEED = 25; // how quickly the bars rise to the music (higher is snappier)
final float VIS_FALL_SPEED = 8; // how quickly they drop back, a little slower so beats linger
// How much each bar follows its own pitch slice (1) versus the overall loudness alone (0)
final float VIS_DETAIL = 0.7;

final float VIS_LOW_HZ = 40, VIS_HIGH_HZ = 12000; // pitch range shared out between the bars

float[] visLevels = new float[VIS_POINTS]; // smoothed level per bar, 0..1
int[] visBand;  // which pitch slice each bar follows, scattered (made on first use)
int visLastMillis = -1;
FFT visFft;

// Colour stops from quiet to loud
final color[] VIS_COLORS = { #3CC8DC, #2ECC71, #F1C40F, #FF8C1A, #FF3B2F };

// Draws the visualizer across the screen between left and right (pixels)
void drawVisualizer(float left, float right) {
  AudioPlayer p = menuMusic.player;
  if (visBand == null) visBand = scatteredOrder(VIS_POINTS);

  // per-bar strength of its pitch slice, relative to the strongest slice this frame
  float[] detail = new float[VIS_POINTS];
  float loudness = 0;
  if (p != null && p.isPlaying()) {
    if (visFft == null || visFft.timeSize() != p.bufferSize()) {
      visFft = new FFT(p.bufferSize(), p.sampleRate());
      visFft.window(FFT.HAMMING);
    }
    visFft.forward(p.mix);
    float strongest = 0;
    for (int b = 0; b < VIS_POINTS; b++) {
      detail[b] = bandLevel(b);
      strongest = max(strongest, detail[b]);
    }
    if (strongest > 0) for (int b = 0; b < VIS_POINTS; b++) detail[b] /= strongest;
    loudness = constrain(p.mix.level() * VIS_GAIN, 0, 1);
  }

  // Each bar eases toward its new level by a share that depends on the frame time,
  // so the motion is equally smooth at any frame rate. A long gap (the menu was not
  // showing) counts as one ordinary frame instead of a jump.
  int now = millis();
  float dt = visLastMillis < 0 ? 1 / 60.0 : min((now - visLastMillis) / 1000.0, 0.05);
  visLastMillis = now;
  float rise = 1 - exp(-dt * VIS_SPEED);
  float fall = 1 - exp(-dt * VIS_FALL_SPEED);

  float x0 = left + VIS_MARGIN, x1 = right - VIS_MARGIN;
  float cy = height * VIS_Y, reach = height * VIS_HEIGHT;
  float w = VIS_WEIGHT;
  noStroke();
  for (int i = 0; i < VIS_POINTS; i++) {
    float t = i / (float) (VIS_POINTS - 1);
    float shape = lerp(1, detail[visBand[i]], VIS_DETAIL);
    // ease both ends down to plain dots, so the bars rise out of a flat line
    // (the square root keeps most of the row near full height, tapering only near the ends)
    // (sin(PI) comes out a hair below 0, and its square root would be NaN)
    float target = loudness * shape * sqrt(max(0, sin(PI * t)));
    visLevels[i] = lerp(visLevels[i], target, target > visLevels[i] ? rise : fall);
    float level = visLevels[i];
    float h = level * reach;
    float x = lerp(x0, x1, t);
    fill(visColor(level));
    // a bar from cy - h to cy + h with rounded ends; at h = 0 the ends meet as a dot.
    // Drawn as a rect and two circles: a rounded rect goes through OpenGL's polygon
    // tessellator, which is slower and can crash on bad coordinates.
    if (h > 0) rect(x - w / 2, cy - h, w, 2 * h);
    circle(x, cy - h, w);
    circle(x, cy + h, w);
  }
}

// Strength of pitch slice b of VIS_POINTS, spaced by octaves like a piano. The higher
// slices are lifted, as music has far less energy in the treble than in the bass.
float bandLevel(int b) {
  float ratio = VIS_HIGH_HZ / VIS_LOW_HZ;
  float lo = VIS_LOW_HZ * pow(ratio, b / (float) VIS_POINTS);
  float hi = VIS_LOW_HZ * pow(ratio, (b + 1) / (float) VIS_POINTS);
  return visFft.calcAvg(lo, hi) * sqrt(sqrt(lo * hi) / VIS_LOW_HZ);
}

// 0..n-1 in a shuffled order that is the same every run
int[] scatteredOrder(int n) {
  int[] order = new int[n];
  for (int i = 0; i < n; i++) order[i] = i;
  java.util.Random rng = new java.util.Random(7);
  for (int i = n - 1; i > 0; i--) {
    int j = rng.nextInt(i + 1);
    int tmp = order[i];
    order[i] = order[j];
    order[j] = tmp;
  }
  return order;
}

// Colour for a level of 0..1, blended between the neighbouring stops
color visColor(float level) {
  float f = constrain(level, 0, 1) * (VIS_COLORS.length - 1);
  int i = min(floor(f), VIS_COLORS.length - 2);
  return lerpColor(VIS_COLORS[i], VIS_COLORS[i + 1], f - i);
}
