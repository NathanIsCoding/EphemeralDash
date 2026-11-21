import ddf.minim.spi.AudioRecordingStream;

// Editor timeline: a bar along the bottom of the editor showing the level's whole song
// as a loudness waveform. The run speed is constant, so a moment in the song is a
// distance from the spawn (as in startAttempt), and the bar lines the song up with the level:
//   - the goal line, with the song after it dimmed (the level is over by then)
//   - an outline around the part of the level that is on screen
//   - while the song is previewed, a playhead showing where it is
// Click or drag on the waveform to move the view to that moment. The play button
// previews the song from the moment at the centre of the screen, and with follow on
// (the button beside it) the view slides along the level with the preview.
//
// A level longer than its song carries on past the song's end: the music loops, so
// the waveform does too.

final float TL_H = 76;            // bar height, pixels
final float TL_GAP = 8;           // space kept between the bar and panels above it
final float TL_LABEL_H = 18;      // the row of text above the waveform
final float TL_COLUMN = 3;        // pixels per waveform column
final float TL_BUCKET = 0.05;     // seconds of song per loudness value
final int TL_READ_FRAMES = 4096;  // sample frames decoded at a time

// The loudness of a track over time. Reading means decoding the whole file, which
// takes a moment, so it happens once per track on a background thread.
class SongEnvelope {
  final String track;
  volatile float[] levels;  // 0..1 (1 = the loudest moment) per TL_BUCKET seconds; null until read
  volatile boolean failed;
  float seconds;            // the track's length

  SongEnvelope(String track) {
    this.track = track;
  }

  boolean ready() {
    return levels != null;
  }

  // Loudness over [t0, t1) seconds: the loudest bucket in it, or the one at t0.
  // Past the end the song loops, so times wrap round.
  float levelAt(float t0, float t1) {
    float[] l = levels;
    if (l.length == 0) return 0;
    int a = floor(t0 / TL_BUCKET), b = max(a + 1, ceil(t1 / TL_BUCKET));
    float best = 0;
    for (int i = a; i < b; i++) best = max(best, l[((i % l.length) + l.length) % l.length]);
    return best;
  }

  void read() {
    AudioRecordingStream s = null;
    try {
      s = quietStream(MUSIC_DIR + "/" + track);
      if (s == null) {
        failed = true;
        return;
      }
      float rate = s.getFormat().getSampleRate();
      int channels = s.getFormat().getChannels();
      int perBucket = max(1, round(rate * TL_BUCKET));
      MultiChannelBuffer buf = new MultiChannelBuffer(TL_READ_FRAMES, channels);
      FloatList out = new FloatList();
      double sum = 0;
      int n = 0;
      long frames = 0, cap = (long) (rate * 3600);  // an hour, in case the end is never reported

      // A stream only hands out samples while it plays. It is not connected to the
      // speakers, so this is silent, and it pauses itself at the end of the file.
      s.play();
      while (s.isPlaying() && frames < cap) {
        s.read(buf);
        // loudness of the mix: the channels averaged, then root-mean-square per bucket
        float[][] ch = new float[channels][];
        for (int c = 0; c < channels; c++) ch[c] = buf.getChannel(c);
        for (int f = 0; f < TL_READ_FRAMES; f++) {
          float v = 0;
          for (int c = 0; c < channels; c++) v += ch[c][f];
          v /= channels;
          sum += v * v;
          if (++n == perBucket) {
            out.append((float) Math.sqrt(sum / n));
            sum = 0;
            n = 0;
          }
        }
        frames += TL_READ_FRAMES;
      }

      float[] l = out.array();
      float peak = 0;
      for (float v : l) peak = max(peak, v);
      if (peak > 0) for (int i = 0; i < l.length; i++) l[i] /= peak;
      seconds = l.length * TL_BUCKET;
      levels = l;  // last, so the drawing thread never sees a half-made envelope
    } catch (Exception e) {
      println("Could not read " + track + " for the timeline: " + e);
      failed = true;
    } finally {
      if (s != null) s.close();
    }
  }
}

// Whether the view follows a preview. Kept here rather than in the Timeline so it
// stays as it was set when another level is opened in the editor.
boolean timelineFollow = true;

HashMap<String, SongEnvelope> songEnvelopes = new HashMap<String, SongEnvelope>();

// The envelope for a track, starting to read it the first time it is asked for
SongEnvelope envelopeFor(String track) {
  SongEnvelope s = songEnvelopes.get(track);
  if (s != null) return s;
  final SongEnvelope made = new SongEnvelope(track);
  songEnvelopes.put(track, made);
  Thread t = new Thread(new Runnable() {
    public void run() {
      made.read();
    }
  }, "read-song-envelope");
  t.setDaemon(true);
  t.start();
  return made;
}

// Opens a track for decoding, with Minim's harmless ID3 tag errors dropped (see Music.quietLoad)
AudioRecordingStream quietStream(String path) {
  synchronized (quietLock) {
    java.io.PrintStream out = System.out;
    System.setOut(new java.io.PrintStream(new java.io.OutputStream() {
      public void write(int b) {}
    }));
    try {
      return minim.loadFileStream(path, TL_READ_FRAMES, false);
    } finally {
      System.setOut(out);
    }
  }
}

// m:ss
String clockTime(float seconds) {
  int s = max(0, floor(seconds));
  return (s / 60) + ":" + nf(s % 60, 2);
}

class Timeline {
  boolean scrubbing;  // the waveform is being dragged along

  // Where the follow view is in the song. Minim's position only moves on in steps of
  // its audio buffer, which would make the view judder, so this runs on the frame
  // clock and is eased toward the real position instead.
  float followT;
  boolean following;  // followT is running (a preview is playing)

  // A paused preview: where it stopped, and where the view was then. Playing again
  // carries on from there unless the view has been moved since.
  boolean paused;
  float pausedT, pausedCamX;
  String pausedTrack;

  // layout

  float x() { return TB_X; }
  float y() { return height - TB_Y - TL_H; }
  float w() { return width - 2 * TB_X; }
  float playX() { return x() + TB_PAD; }
  float playY() { return y() + (TL_H - TB_BUTTON) / 2; }
  float followX() { return playX() + TB_BUTTON + TB_GAP; }
  float waveX() { return followX() + TB_BUTTON + TB_PAD * 2; }
  float waveW() { return x() + w() - TB_PAD * 2 - waveX(); }
  float waveTop() { return y() + TB_PAD + TL_LABEL_H; }
  float waveBottom() { return y() + TL_H - TB_PAD; }

  boolean over(float mx, float my) {
    return mx >= x() && mx < x() + w() && my >= y() && my < y() + TL_H;
  }

  boolean overPlay(float mx, float my) {
    return mx >= playX() && mx < playX() + TB_BUTTON && my >= playY() && my < playY() + TB_BUTTON;
  }

  boolean overFollow(float mx, float my) {
    return mx >= followX() && mx < followX() + TB_BUTTON && my >= playY() && my < playY() + TB_BUTTON;
  }

  boolean overWave(float mx, float my) {
    return mx >= waveX() && mx < waveX() + waveW() && my >= y() && my < y() + TL_H;
  }

  // The bar spans the song, or the whole level if that runs on longer
  float duration(Editor e, SongEnvelope s) {
    return max(s.seconds, e.timeAt(e.goal.x));
  }

  // screen x on the waveform for a time, and back
  float timeX(float t, float dur) {
    return waveX() + constrain(t / dur, 0, 1) * waveW();
  }

  float xTime(float sx, float dur) {
    return constrain((sx - waveX()) / waveW(), 0, 1) * dur;
  }

  boolean previewing(Editor e) {
    return e.track != null && music.playing() && e.track.equals(music.track);
  }

  // how far into the song the preview is, in seconds
  float playhead() {
    return music.player.position() / 1000.0;
  }

  // input

  // Called every frame: with follow on, keeps the preview's moment at the centre of the
  // screen. Only the view's x changes, so panning up and down still works.
  void update(Editor e, float dt) {
    if (!previewing(e)) {
      following = false;
      return;
    }
    paused = false;  // playing again, possibly started from the music panel
    float p = playhead();
    if (!following || abs(followT - p) > 0.15) followT = p;  // just started, jumped, or looped
    else followT = lerp(followT + dt, p, min(1, dt * 4));
    following = true;
    if (timelineFollow && !scrubbing) e.centreOnTime(followT);
  }

  void pressed(Editor e) {
    if (overFollow(mouseX, mouseY)) {
      timelineFollow = !timelineFollow;
      return;
    }
    if (overPlay(mouseX, mouseY)) {
      togglePlay(e);
    } else if (e.track != null && overWave(mouseX, mouseY)) {
      scrubbing = true;
      scrubTo(e, mouseX);
    }
  }

  // Play / pause the preview (the play button, or Space)
  void togglePlay(Editor e) {
    if (e.track == null) return;
    if (previewing(e)) {
      paused = true;
      pausedT = playhead();
      pausedCamX = e.cam.x;
      pausedTrack = e.track;
      music.pause();
      return;
    }
    // Restarted at the paused time rather than resumed, so a stop elsewhere in the
    // meantime (which rewinds the track) cannot put it back at the start
    boolean resume = pausedHere(e) && abs(e.cam.x - pausedCamX) < 0.001;
    paused = false;
    music.start(e.track, resume ? pausedT : max(0, e.centreTime()));
  }

  boolean pausedHere(Editor e) {
    return paused && e.track != null && e.track.equals(pausedTrack);
  }

  // The scan band in the level: shown while the preview plays, and where it was paused
  boolean showBand(Editor e) {
    return following || pausedHere(e);
  }

  float bandTime() {
    return following ? followT : pausedT;
  }

  void scrubTo(Editor e, float mx) {
    SongEnvelope s = envelopeFor(e.track);
    if (s.ready()) e.centreOnTime(xTime(mx, duration(e, s)));
  }

  // A preview jumps to where the drag let go (not during it, which would stutter)
  void released(Editor e) {
    scrubbing = false;
    if (previewing(e)) music.start(e.track, max(0, e.centreTime()));
  }

  // drawing

  // A toggle, lit like an active toolbar tool while on. Its icon is a ">>" (onward,
  // with the song), drawn here as there is no image for it.
  void drawFollowButton() {
    float bx = followX(), by = playY(), cx = bx + TB_BUTTON / 2, cy = by + TB_BUTTON / 2;
    boolean on = timelineFollow, hover = overFollow(mouseX, mouseY);
    noStroke();
    fill(on ? color(255, 200, 60, 70) : hover ? color(255, 40) : color(255, 12));
    rect(bx, by, TB_BUTTON, TB_BUTTON, 6);
    if (on) {
      noFill();
      stroke(255, 200, 60);
      strokeWeight(2);
      rect(bx, by, TB_BUTTON, TB_BUTTON, 6);
    }
    noFill();
    stroke(#E3E3E3);  // the icon images' colour
    strokeWeight(2);
    for (float dx = -5; dx <= 3; dx += 8) {
      beginShape();
      vertex(cx + dx - 3, cy - 6);
      vertex(cx + dx + 3, cy);
      vertex(cx + dx - 3, cy + 6);
      endShape();
    }
  }

  // Two bars, in a ring like the play_circle icon it stands in for (there is no pause image)
  void drawPauseIcon(float cx, float cy) {
    noFill();
    stroke(#E3E3E3);
    strokeWeight(2);
    circle(cx, cy, 20);
    line(cx - 3, cy - 4, cx - 3, cy + 4);
    line(cx + 3, cy - 4, cx + 3, cy + 4);
  }

  void display(Editor e) {
    noStroke();
    fill(0, 160);
    rect(x(), y(), w(), TL_H, 8);

    boolean hasTrack = e.track != null;
    boolean playing = previewing(e);
    float top = waveTop(), bot = waveBottom();
    float wx = waveX(), ww = waveW(), wmid = wx + ww / 2;

    // play / stop, styled like the toolbar's buttons
    noStroke();
    boolean hover = hasTrack && overPlay(mouseX, mouseY);
    fill(playing ? color(255, 200, 60, 70) : hover ? color(255, 40) : color(255, 12));
    rect(playX(), playY(), TB_BUTTON, TB_BUTTON, 6);
    if (playing) {
      noFill();
      stroke(255, 200, 60);
      strokeWeight(2);
      rect(playX(), playY(), TB_BUTTON, TB_BUTTON, 6);
    }
    if (playing) drawPauseIcon(playX() + TB_BUTTON / 2, playY() + TB_BUTTON / 2);
    else e.drawIcon("play", playX() + TB_BUTTON / 2, playY() + TB_BUTTON / 2);
    if (!hasTrack) {  // greyed out
      noStroke();
      fill(0, 150);
      rect(playX(), playY(), TB_BUTTON, TB_BUTTON, 6);
    }
    drawFollowButton();
    // tooltips, above the bar as it sits at the bottom of the screen
    if (overPlay(mouseX, mouseY)) {
      String tip = !hasTrack ? "No music to preview"
          : playing ? "Pause the preview  [Space]"
          : pausedHere(e) && abs(e.cam.x - pausedCamX) < 0.001 ? "Carry on with the preview  [Space]"
          : "Preview the song from the view  [Space]";
      e.drawTooltip(tip, playX(), y() - 32);
    } else if (overFollow(mouseX, mouseY)) {
      e.drawTooltip("Follow the preview: " + (timelineFollow ? "on" : "off"), followX(), y() - 32);
    }

    textSize(12);
    textAlign(CENTER, CENTER);
    fill(150);
    if (!hasTrack) {
      text("No music: choose a track with the music button to see it here", wmid, (y() + y() + TL_H) / 2);
      return;
    }
    SongEnvelope s = envelopeFor(e.track);
    if (s.failed) {
      text("Could not read " + e.track, wmid, (top + bot) / 2);
      return;
    }
    if (!s.ready()) {
      text("Reading " + e.track + "...", wmid, (top + bot) / 2);
      return;
    }

    float dur = duration(e, s);
    float goalT = e.timeAt(e.goal.x);

    // labels: the track and level length on the left, the time on the right
    float ly = y() + TB_PAD + TL_LABEL_H / 2 - 2;
    textAlign(LEFT, CENTER);
    fill(220);
    String name = e.track.replaceAll("[.][^.]+$", "");
    text(name, wx, ly);
    fill(150);
    text("   level " + clockTime(goalT) + (goalT > s.seconds ? " (longer than the song, which loops)" : ""), wx + textWidth(name), ly);
    textAlign(RIGHT, CENTER);
    fill(playing ? color(255, 200, 60) : color(220));
    text(clockTime(playing ? playhead() : max(0, e.centreTime())) + " / " + clockTime(s.seconds), wx + ww, ly);

    // the waveform: a bar per column, up and down from the middle, coloured by loudness
    float mid = (top + bot) / 2, half = (bot - top) / 2;
    strokeWeight(2);
    beginShape(LINES);
    for (float px = 0; px < ww; px += TL_COLUMN) {
      float lv = s.levelAt(px / ww * dur, (px + TL_COLUMN) / ww * dur);
      float h = max(1, lv * half);
      stroke(visColor(lv));
      vertex(wx + px + 1, mid - h);
      vertex(wx + px + 1, mid + h);
    }
    endShape();

    // past the goal the level is over
    float gx = timeX(goalT, dur);
    noStroke();
    fill(0, 150);
    if (gx < wx + ww) rect(gx, top - 2, wx + ww - gx, bot - top + 4);
    stroke(GOAL_COLOR);
    strokeWeight(2);
    line(gx, top - 2, gx, bot + 2);

    // where a song shorter than the level starts over
    if (dur > s.seconds) {
      float ex = timeX(s.seconds, dur);
      stroke(255, 90);
      strokeWeight(1);
      line(ex, top, ex, bot);
    }

    // the part of the level on screen
    float tA = e.timeAt(e.visibleX(0)), tB = e.timeAt(e.visibleX(width));
    float a = min(tA, tB), b = max(tA, tB);
    if (b > 0 && a < dur) {
      float ax = timeX(a, dur), bx = timeX(b, dur);
      noFill();
      stroke(255, 170);
      strokeWeight(1.5);
      rect(ax, top - 3, max(2, bx - ax), bot - top + 6, 3);
    }

    // the mouse, with the time under it
    if (overWave(mouseX, mouseY) || scrubbing) {
      float mx = constrain(mouseX, wx, wx + ww);
      stroke(255, 130);
      strokeWeight(1);
      line(mx, top, mx, bot);
    }

    if (playing) {
      float p = playhead();
      // a level longer than the song plays it again; the playhead stays within the song
      float px = timeX(p, dur);
      stroke(255, 200, 60);
      strokeWeight(2);
      line(px, top - 4, px, bot + 4);
    }
  }
}
