package com.splitflap

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.provider.Settings
import android.text.TextPaint
import android.os.SystemClock
import android.util.Log
import android.util.TypedValue
import android.view.Choreographer
import android.view.View
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.uimanager.PixelUtil
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.views.text.ReactTypefaceUtils
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * The Android player. ios/SplitflapView.mm is the reference: the same plan, the same curves, the
 * same four renderers. What differs is the machinery — iOS bakes each plan into Core Animation
 * keyframes; here every frame evaluates each cell as a pure function of time, and an
 * interruption reads the old plan at the current time instead of presentation layers.
 *
 * Glyphs are placed by the widths the shared C++ shadow node measured, so a settled board draws
 * every glyph where the <Text> it hands over to draws it.
 *
 * Props and state only mark the view dirty; [commit] applies a whole mount batch at once, as the
 * iOS view's finalizeUpdates does — a lone state update must not undo a batch half-applied.
 */
class SplitflapView(context: Context) : View(context), Choreographer.FrameCallback {
  var text: String = ""
    set(value) {
      if (field != value) planDirty = true
      field = value
    }
  var plan: String = ""
    set(value) {
      if (field != value) planDirty = true
      field = value
    }
  /** The `glyphs` prop: the text split into cells by the planner; it arrives with the text. */
  var cells: List<String> = emptyList()
  var fontFamily: String? by font(null)
  /** As given in JS, before font scaling; 0 or less means the default. */
  var fontSize: Float by font(0f)
  var fontWeight: String? by font(null)
  var fontStyle: String? by font(null)
  /** As a <Text>'s fontVariant; `tabular-nums` gives every digit one width. */
  var fontVariant: List<String> by font(emptyList())
  var color: Int? by font(null)
  var allowFontScaling: Boolean by font(true)
  var maxFontSizeMultiplier: Float by font(0f)
  var surfaceColor: Int? by font(null)
  var reduceMotion: String = "system"
  /**
   * `stable` holds the widest glyph on a cell's way while it turns; `uniform` does too, on cells the
   * shadow node made one width, with each glyph centred; `tiered` centres each glyph in its tier's
   * width and holds only the wider end; `natural` reflows.
   */
  var cellWidth: String = "natural"

  private var cellWidths = FloatArray(0)
  private var ascent = 0f
  private var lineHeight = 0f
  private var visibleCount = -1

  private val paint = TextPaint(Paint.ANTI_ALIAS_FLAG)
  private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
  private val maskPaint = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN) }
  private val maskShaders = arrayOfNulls<LinearGradient>(MASK_LEVELS + 1)
  private var maskHeight = 0f
  private var textGlyphs: List<String> = emptyList()
  private var commitPending = false
  private var fontDirty = true
  private var planDirty = false
  private var stateDirty = false

  /** Transition of the last plan read: the settled look of `flip` (tiles) outlives its plan. */
  private var styleTransition = "roll"
  /** Where each cell settled last, so the next plan widens or narrows it from there. */
  private var modelWidths = FloatArray(0)
  private var playback: Playback? = null
  private var generation = 0
  private var inFlightText: String? = null
  private var frameNanos = 0L
  private var frameScheduled = false

  /** What the shadow node measured, in dp; kept in px. */
  fun setMeasured(state: ReadableMap) {
    val widths = state.getArray("cellWidths")
    cellWidths = FloatArray(widths?.size() ?: 0) { i ->
      PixelUtil.toPixelFromDIP(widths!!.getDouble(i).toFloat())
    }
    ascent = PixelUtil.toPixelFromDIP(state.getDouble("ascent").toFloat())
    lineHeight = PixelUtil.toPixelFromDIP(state.getDouble("lineHeight").toFloat())
    visibleCount = if (state.hasKey("visibleCount")) state.getInt("visibleCount") else -1
    stateDirty = true
  }

  fun commit() {
    if (commitPending) return
    commitPending = true
    postOnAnimation {
      commitPending = false
      finalizeUpdates()
    }
  }

  /** FlashList and friends reuse the view for another item: nothing of the last one may leak. */
  fun prepareToRecycle() {
    generation++
    stopFrames()
    playback = null
    inFlightText = null
    modelWidths = FloatArray(0)
    styleTransition = "roll"
    cellWidths = FloatArray(0)
    textGlyphs = emptyList()
    cells = emptyList()
    fontDirty = true
    planDirty = false
    stateDirty = false
  }

  private fun finalizeUpdates() {
    if (fontDirty || stateDirty) resolveFont()
    // The cells JS split the text into (planner splitGlyphs: a flag or an emoji family is one cell);
    // by code point only when the prop is absent or belongs to another text.
    textGlyphs = if (cells.isNotEmpty() && cells.joinToString("") == text) cells else splitflapGlyphs(text)
    if (planDirty) {
      val decoded = SplitflapPlan.decode(plan)
      if (decoded != null) styleTransition = decoded.transition
      if (decoded == null || decoded.version > 1 || decoded.cells.size < textGlyphs.size) {
        showTextInstantly()
      } else {
        playPlan(decoded)
      }
    } else if (fontDirty || stateDirty) {
      showTextInstantly()
    }
    fontDirty = false
    planDirty = false
    stateDirty = false
  }

  // Font

  private fun resolveFont() {
    paint.typeface = ReactTypefaceUtils.applyStyles(
      Typeface.DEFAULT,
      ReactTypefaceUtils.parseFontStyle(fontStyle),
      ReactTypefaceUtils.parseFontWeight(fontWeight),
      fontFamily,
      context.assets,
    )
    paint.textSize = resolvedFontSize()
    // The OpenType features React Native's own text sets for the same fontVariant names.
    paint.fontFeatureSettings = fontVariant.mapNotNull {
      when (it) {
        "small-caps" -> "'smcp'"
        "oldstyle-nums" -> "'onum'"
        "lining-nums" -> "'lnum'"
        "tabular-nums" -> "'tnum'"
        "proportional-nums" -> "'pnum'"
        else -> null
      }
    }.joinToString(", ").ifEmpty { null }
    paint.color = color ?: Color.BLACK
    if (lineHeight <= 0) lineHeight = ceil(paint.fontSpacing)
    if (Log.isLoggable(TAG, Log.DEBUG)) logMeasure()
  }

  /** RN's own rule (TextAttributeProps.setFontSize), so the paint matches what was measured. */
  private fun resolvedFontSize(): Float {
    val size = if (fontSize > 0) fontSize else DEFAULT_FONT_SIZE
    val px =
      if (allowFontScaling) {
        PixelUtil.toPixelFromSP(size, if (maxFontSizeMultiplier >= 1) maxFontSizeMultiplier else Float.NaN)
      } else {
        PixelUtil.toPixelFromDIP(size)
      }
    return ceil(px)
  }

  private fun logMeasure() {
    // The whole line, as a <Text> lays it out: the widths must add up to it.
    Log.d(
      TAG,
      "measure text=$text sumState=${PixelUtil.toDIPFromPixel(cellWidths.sum())} " +
        "linePaint=${PixelUtil.toDIPFromPixel(paint.measureText(text))} textSizePx=${paint.textSize}",
    )
  }

  /** The colour under the board: what a flap paints so the half it covers never shows through. */
  private fun surfaceColor(): Int {
    surfaceColor?.let { return it }
    val background = (background as? ColorDrawable)?.color
    if (background != null && Color.alpha(background) == 255) return background
    val value = TypedValue()
    return if (context.theme.resolveAttribute(android.R.attr.colorBackground, value, true)) value.data else Color.WHITE
  }

  // Settled layout

  /** How many glyphs of the text fit before "…", or -1 when all do; trusted only for this text. */
  private fun visibleGlyphCount(): Int =
    if (visibleCount < 0 || cellWidths.size != textGlyphs.size || visibleCount >= textGlyphs.size) -1
    else visibleCount

  /** What the board shows at rest: the text, or the part that fits and "…". */
  private fun settledGlyphs(): List<String> {
    val visible = visibleGlyphCount()
    return if (visible >= 0) textGlyphs.subList(0, visible) + ELLIPSIS else textGlyphs
  }

  /**
   * Left edges of the settled glyphs plus the right edge of the last: the measured widths for the
   * text, and for "…" the place the <Text> puts it, kerned against the last kept glyph.
   */
  private fun settledEdges(glyphs: List<String>): FloatArray {
    val edges = FloatArray(glyphs.size + 1)
    val visible = visibleGlyphCount()
    for (i in glyphs.indices) {
      edges[i + 1] =
        if (visible >= 0 && i == visible) {
          edges[i] = ellipsisX(visible)
          edges[i] + paint.measureText(ELLIPSIS)
        } else {
          edges[i] + widthOfTextGlyph(glyphs[i], i)
        }
    }
    return edges
  }

  // Where the <Text> puts "…": after the kept glyphs, kerned against the last of them. The cell
  // edge there is kerned against the glyph that was cut instead — 3 px off after "la madr".
  private fun ellipsisX(shown: Int): Float {
    val kept = textGlyphs.subList(0, shown).joinToString("")
    return paint.measureText(kept + ELLIPSIS) - paint.measureText(ELLIPSIS)
  }

  /**
   * Yoga's width for this cell when it is a glyph of the measured text; a loading word or a glyph
   * that is leaving takes its own advance, which the same paint produced.
   */
  private fun widthOfTextGlyph(glyph: String, index: Int): Float {
    if (glyph.isEmpty()) return 0f
    if (index < textGlyphs.size && textGlyphs[index] == glyph && index < cellWidths.size) {
      return cellWidths[index]
    }
    return paint.measureText(glyph)
  }

  private fun settledWidthOfGlyph(glyph: String, index: Int, settled: List<String>, edges: FloatArray): Float =
    if (index < settled.size && settled[index] == glyph) edges[index + 1] - edges[index]
    else if (glyph.isEmpty()) 0f
    else paint.measureText(glyph)

  // Playback

  private enum class Renderer { DRUM, SCRAMBLE, FLIP }

  private fun rendererFor(transition: String) =
    when (transition) {
      "scramble" -> Renderer.SCRAMBLE
      "flip" -> Renderer.FLIP
      else -> Renderer.DRUM
    }

  /** What an interrupted cell showed when the next plan arrived, per renderer. */
  private class Presented(val width: Float) {
    /** drum: y of each glyph on a layer. */
    val glyphYs = HashMap<String, Float>()
    /** flip: the flap mid-fold, its glyph and angle. */
    var topGlyph: String? = null
    var topAngle = Double.NaN
    var bottomGlyph: String? = null
    var bottomAngle = Double.NaN
    /** scramble: the cell was flickering. */
    var dimmed = false
  }

  private inner class Playback(
    val plan: SplitflapPlan,
    val text: String,
    val renderer: Renderer,
    /** Length of one run in ms; 0 plays nothing (Reduce Motion). */
    val window: Double,
    val startWidths: FloatArray,
    val targetWidths: FloatArray,
    /** `stable` only: the widest glyph on each cell's way; null reflows naturally. */
    val holdWidths: FloatArray?,
    val presented: List<Presented?>,
    /** Scramble: the flicker glyph of every step, per cell. */
    val flicker: List<List<String>>,
    val surface: Int,
  ) {
    var startNanos = -1L

    /** How the frame moved for this text (onLayout), or null: the word is then drawn from 0. */
    var move: FrameMove? = null
    val startContent = startWidths.sum()

    /**
     * Where the word's left edge is drawn at `t`, against the new frame: where the old word stood,
     * moving to 0 as the content takes the new width, around the parent's anchor.
     */
    fun offsetAt(t: Double): Float {
      val m = move ?: return 0f
      var content = 0f
      for (i in plan.cells.indices) content += widthAt(i, t)
      return m.shift - m.anchor * (content - startContent)
    }

    fun time(nanos: Long): Double {
      if (startNanos < 0) return 0.0
      val elapsed = (nanos - startNanos) / 1e6
      return if (plan.loop && window > 0) elapsed % window else min(elapsed, window)
    }

    fun widthAt(i: Int, t: Double): Float {
      val cell = plan.cells[i]
      if (holdWidths != null) {
        // Opens to the hold width in the first sixth of the turn, holds while the glyphs move,
        // and narrows to the landed glyph in the tail after they stop.
        val start = cell.delayMs
        val open = cell.durationMs / 6
        val land = start + cell.durationMs
        val close = land + cell.durationMs * (WIDTH_WINDOW - 1)
        if (t <= start || cell.durationMs <= 0) return if (t <= start) startWidths[i] else targetWidths[i]
        if (t < start + open) {
          val p = SplitflapEasing.IN_OUT.ease((t - start) / open).toFloat()
          return startWidths[i] + (holdWidths[i] - startWidths[i]) * p
        }
        if (t < land) return holdWidths[i]
        if (t >= close) return targetWidths[i]
        val p = SplitflapEasing.IN_OUT.ease((t - land) / (close - land)).toFloat()
        return holdWidths[i] + (targetWidths[i] - holdWidths[i]) * p
      }
      val span = cell.durationMs * WIDTH_WINDOW
      if (t < cell.delayMs) return startWidths[i]
      if (span <= 0 || t >= cell.delayMs + span) return targetWidths[i]
      val p = SplitflapEasing.IN_OUT.ease((t - cell.delayMs) / span).toFloat()
      return startWidths[i] + (targetWidths[i] - startWidths[i]) * p
    }

    fun moving(cell: SplitflapCellPlan) = window > 0 && cell.land > 0 && cell.durationMs > 0
  }

  private fun reduceMotionEnabled(): Boolean =
    when (reduceMotion) {
      "always" -> true
      "never" -> false
      else -> {
        // What RN's AccessibilityInfo.isReduceMotionEnabled reads, plus the animator switch.
        val resolver = context.contentResolver
        Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f ||
          Settings.Global.getFloat(resolver, Settings.Global.TRANSITION_ANIMATION_SCALE, 1f) == 0f
      }
    }

  /** The final text with no motion: an unreadable plan, Reduce Motion, or a font change. */
  private fun showTextInstantly() {
    interruptIfInFlight()
    stopFrames()
    playback = null
    val settled = settledGlyphs()
    val edges = settledEdges(settled)
    modelWidths = FloatArray(settled.size) { edges[it + 1] - edges[it] }
    invalidate()
    finishInstantly(text)
  }

  private fun playPlan(decoded: SplitflapPlan) {
    val renderer = rendererFor(decoded.transition)
    val previous = playback
    val presented = if (previous != null && inFlightText != null) capturePresented(previous, renderer) else emptyList()
    interruptIfInFlight()
    generation++

    val visible = visibleGlyphCount()
    val plan = if (visible >= 0) decoded.truncatedTo(visible + 1, ELLIPSIS) else decoded
    val settled = settledGlyphs()
    val edges = settledEdges(settled)
    val count = plan.cells.size

    var window = if (reduceMotionEnabled()) 0.0 else plan.totalMs
    if (window > 0) {
      for (cell in plan.cells) window = max(window, cell.delayMs + cell.durationMs * WIDTH_WINDOW)
    }
    val startWidths = FloatArray(count) { i ->
      presented.getOrNull(i)?.width ?: modelWidths.getOrElse(i) { 0f }
    }
    val targetWidths = FloatArray(count) { i ->
      settledWidthOfGlyph(plan.cells[i].let { it.glyphAt(it.land) }, i, settled, edges)
    }
    // A scramble cell's way is the letters it flickers through, which the path does not list.
    // `tiered` holds only the wider of its two ends: a roll through «m» would otherwise widen a
    // narrow cell on every turn, and the cell clips what passes.
    val holdWidths = if (cellWidth == "tiered") {
      FloatArray(count) { i -> max(startWidths[i], targetWidths[i]) }
    } else if (cellWidth == "stable" || cellWidth == "uniform") {
      FloatArray(count) { i ->
        val cell = plan.cells[i]
        val way = if (renderer == Renderer.SCRAMBLE) cell.path + cell.letters else cell.path
        way.fold(max(startWidths[i], targetWidths[i])) { widest, glyph ->
          max(widest, if (glyph.isEmpty()) 0f else paint.measureText(glyph))
        }
      }
    } else null
    val flicker = plan.cells.mapIndexed { i, cell ->
      if (renderer == Renderer.SCRAMBLE) flickerOf(cell, i) else emptyList()
    }

    stopFrames()
    modelWidths = targetWidths
    val move = pendingMove?.takeIf { SystemClock.uptimeMillis() - it.atMillis < MOVE_WINDOW_MS }
    pendingMove = null
    val next = Playback(
      plan, text, renderer, window, startWidths, targetWidths, holdWidths,
      List(count) { presented.getOrNull(it) }, flicker,
      if (renderer == Renderer.FLIP) surfaceColor() else 0,
    )
    next.move = move
    if (window > 0) {
      playback = next
      inFlightText = text
      startFrames()
      emitTransitionStart(text)
    } else {
      playback = null
      finishInstantly(text)
    }
    invalidate()
  }

  /** Scramble letters, one per step: an LCG seeded by the cell's place, as the iOS player draws. */
  private fun flickerOf(cell: SplitflapCellPlan, index: Int): List<String> {
    val to = cell.glyphAt(cell.land)
    if (to.isEmpty() || cell.land == 0 || cell.durationMs <= 0) return emptyList()
    val letters = cell.letters.ifEmpty { listOf(to) }
    val steps = min(SCRAMBLE_MAX_STEPS, ceil((cell.delayMs + cell.durationMs) / cell.stepMs).toInt() + 1)
    var state = (0x9E3779B9L xor ((index + 1).toLong() * 0x85EBCA6BL)) and 0xFFFFFFFFL
    return List(steps) {
      state = (state * 1664525L + 1013904223L) and 0xFFFFFFFFL
      letters[((state ushr 8) % letters.size).toInt()]
    }
  }

  // Frames

  private fun startFrames() {
    if (!frameScheduled && isAttachedToWindow) {
      frameScheduled = true
      Choreographer.getInstance().postFrameCallback(this)
    }
  }

  private fun stopFrames() {
    if (frameScheduled) {
      frameScheduled = false
      Choreographer.getInstance().removeFrameCallback(this)
      if (Log.isLoggable(TAG, Log.DEBUG)) Log.d(TAG, "frames stopped text=$text")
    }
  }

  override fun doFrame(nanos: Long) {
    frameScheduled = false
    val current = playback ?: return
    if (current.startNanos < 0) current.startNanos = nanos
    frameNanos = nanos
    invalidate()
    val elapsed = (nanos - current.startNanos) / 1e6
    if (current.plan.loop || elapsed < current.window) {
      frameScheduled = true
      Choreographer.getInstance().postFrameCallback(this)
    } else {
      finishPlayback(current)
    }
  }

  private fun finishPlayback(finished: Playback) {
    playback = null
    if (Log.isLoggable(TAG, Log.DEBUG)) {
      Log.d(
        TAG,
        "end text=${finished.text} elapsedMs=${(frameNanos - finished.startNanos) / 1_000_000} " +
          "totalMs=${finished.plan.totalMs} windowMs=${finished.window}",
      )
    }
    if (inFlightText != null) {
      inFlightText = null
      emitTransitionEnd(finished.text, false)
    }
  }

  override fun onAttachedToWindow() {
    super.onAttachedToWindow()
    if (playback != null) startFrames()
  }

  override fun onDetachedFromWindow() {
    stopFrames()
    super.onDetachedFromWindow()
  }

  // Events

  private fun emitTransitionStart(text: String) {
    val reactContext = context as? ReactContext ?: return
    UIManagerHelper.getEventDispatcherForReactTag(reactContext, id)
      ?.dispatchEvent(TransitionStartEvent(UIManagerHelper.getSurfaceId(this), id, text))
  }

  private fun emitTransitionEnd(text: String, interrupted: Boolean) {
    if (Log.isLoggable(TAG, Log.DEBUG)) Log.d(TAG, "event text=$text interrupted=$interrupted")
    val reactContext = context as? ReactContext ?: return
    UIManagerHelper.getEventDispatcherForReactTag(reactContext, id)
      ?.dispatchEvent(TransitionEndEvent(UIManagerHelper.getSurfaceId(this), id, text, interrupted))
  }

  private fun finishInstantly(text: String) {
    val expected = ++generation
    inFlightText = null
    post { if (generation == expected) emitTransitionEnd(text, false) }
  }

  private fun interruptIfInFlight() {
    val text = inFlightText ?: return
    inFlightText = null
    emitTransitionEnd(text, true)
  }

  // Drawing

  /** A frame move: the left edge shifted by `shift` as the width changed, the parent anchoring at `anchor`. */
  class FrameMove(val shift: Float, val anchor: Float, val atMillis: Long)

  private var lastLeft = Float.NaN
  private var lastWidth = 0f
  private var pendingMove: FrameMove? = null

  // A new text resizes the frame at once, and a parent that centres it (or aligns it to the end)
  // moves its left edge with it: drawn from the new edge, the old word would hop sideways before a
  // single cell turned. The anchor is read off the move itself, so any alignment is kept. The layout
  // may land before or after the plan of the same commit.
  override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
    super.onLayout(changed, left, top, right, bottom)
    val x = left.toFloat()
    val w = (right - left).toFloat()
    if (!lastLeft.isNaN() && lastWidth > 0) {
      val grown = w - lastWidth
      val shift = lastLeft - x
      if (abs(grown) > 0.5f && abs(shift) > 0.01f) {
        val anchor = shift / grown
        if (anchor > -0.05f && anchor < 1.05f) {
          val move = FrameMove(shift, anchor.coerceIn(0f, 1f), SystemClock.uptimeMillis())
          val current = playback
          if (current != null && current.move == null && current.startNanos < 0) {
            current.move = move
          } else {
            pendingMove = move
          }
        }
      }
    }
    lastLeft = x
    lastWidth = w
  }

  override fun onDraw(canvas: Canvas) {
    super.onDraw(canvas)
    // No clip to the frame: a word in flight is drawn where the old one stood, and a leaving word
    // can be wider than the new frame for a moment. React Native's views do not clip their
    // children; each cell still clips its own glyphs.
    val current = playback
    if (current == null) drawSettled(canvas) else drawPlayback(canvas, current, current.time(frameNanos))
  }

  private fun drawSettled(canvas: Canvas) {
    val glyphs = settledGlyphs()
    val edges = settledEdges(glyphs)
    val flip = rendererFor(styleTransition) == Renderer.FLIP
    val surface = if (flip) surfaceColor() else 0
    for (i in glyphs.indices) {
      if (flip) drawFlipBackground(canvas, edges[i], edges[i + 1] - edges[i], surface)
      drawGlyph(canvas, glyphs[i], edges[i], 0f, 255, edges[i + 1] - edges[i])
    }
  }

  private fun drawPlayback(canvas: Canvas, p: Playback, t: Double) {
    val h = cellHeight()
    // One offscreen layer for the whole board, not one per cell: each cell's mask then fades only
    // its own rect, and a board of twenty looping cells costs one layer a frame.
    val masked = p.renderer == Renderer.DRUM
    val offset = p.offsetAt(t)
    var content = 0f
    for (i in p.plan.cells.indices) content += p.widthAt(i, t)
    if (masked) canvas.saveLayer(min(0f, offset), 0f, max(width.toFloat(), offset + content), height.toFloat(), null)
    var x = offset
    for (i in p.plan.cells.indices) {
      val cell = p.plan.cells[i]
      val w = p.widthAt(i, t)
      if (!p.moving(cell) || t >= cell.delayMs + cell.durationMs && !p.plan.loop) {
        if (p.renderer == Renderer.FLIP) drawFlipBackground(canvas, x, w, p.surface)
        drawGlyph(canvas, cell.glyphAt(cell.land), x, 0f, 255, w)
      } else {
        canvas.save()
        canvas.clipRect(x, 0f, x + w, h)
        when (p.renderer) {
          Renderer.DRUM -> drawDrumCell(canvas, cell, x, w, t, h, p.presented[i])
          Renderer.SCRAMBLE -> drawScrambleCell(canvas, cell, x, w, t, p.flicker[i], p.presented[i])
          Renderer.FLIP -> drawFlipCell(canvas, cell, x, w, t, h, p, p.presented[i])
        }
        canvas.restore()
      }
      x += w
    }
    if (masked) canvas.restore()
  }

  private fun cellHeight() = if (lineHeight > 0) lineHeight else height.toFloat()

  /** `w`: the cell's width now; a `uniform` or `tiered` board centres the glyph in it. */
  private fun drawGlyph(canvas: Canvas, glyph: String, x: Float, dy: Float, alpha: Int, w: Float) {
    if (glyph.isEmpty() || alpha <= 0) return
    val base = paint.color
    paint.alpha = Color.alpha(base) * alpha / 255
    val inset = if (cellWidth == "uniform" || cellWidth == "tiered") (w - paint.measureText(glyph)) / 2 else 0f
    canvas.drawText(glyph, x + inset, ascent + dy, paint)
    paint.color = base
  }

  /**
   * The drum's fade at the top and bottom of a cell, so a glyph rolls in and out softly. It is as
   * strong as the cell is far from rest (0 when a glyph sits exactly in place), so a settled board
   * looks exactly like its <Text> and neither the start nor the end of a roll pops.
   */
  private fun drawMask(canvas: Canvas, x: Float, w: Float, h: Float, strength: Float) {
    val level = (strength.coerceIn(0f, 1f) * MASK_LEVELS).toInt()
    if (level == 0) return
    if (maskHeight != h) {
      maskHeight = h
      maskShaders.fill(null)
    }
    maskPaint.shader = maskShaders[level] ?: run {
      val clear = Color.argb(((1f - level.toFloat() / MASK_LEVELS) * 255).toInt(), 0, 0, 0)
      LinearGradient(
        0f, 0f, 0f, h,
        intArrayOf(clear, Color.BLACK, Color.BLACK, clear),
        floatArrayOf(0f, MASK_FADE, 1f - MASK_FADE, 1f),
        Shader.TileMode.CLAMP,
      ).also { maskShaders[level] = it }
    }
    canvas.drawRect(x, 0f, x + w, h, maskPaint)
  }

  // Drum: glyph layers A and B alternate along the path, even glyphs on A, odd on B.


  /** The two layers' glyph index and y offset at time t (ios trackForCell, evaluated directly). */
  private fun drumLayers(cell: SplitflapCellPlan, t: Double, h: Float, resume: Float): Array<Pair<Int, Float>> {
    val steps = cell.land
    val s = SplitflapTimeline.progress(cell, t)
    val k = min(floor(s).toInt(), steps - 1)
    val blend = if (k == 0) resume * (1 - min(1.0, s)).toFloat() else 0f
    fun layer(isA: Boolean): Pair<Int, Float> {
      val even = k % 2 == 0
      val g = if (isA == even) k else k + 1
      return g to (cell.dir * (g - s) * h).toFloat() + blend
    }
    return arrayOf(layer(true), layer(false))
  }

  private fun resumeOffset(cell: SplitflapCellPlan, presented: Presented?, h: Float): Float {
    val y = presented?.glyphYs?.get(cell.glyphAt(0)) ?: return 0f
    return if (abs(y) < h) y else 0f
  }

  private fun drawDrumCell(
    canvas: Canvas, cell: SplitflapCellPlan, x: Float, w: Float, t: Double, h: Float, presented: Presented?,
  ) {
    val layers = drumLayers(cell, t, h, resumeOffset(cell, presented, h))
    val rest = layers.minOf { abs(it.second) } / h
    for ((g, y) in layers) drawGlyph(canvas, cell.glyphAt(g), x, y, 255, w)
    drawMask(canvas, x, w, h, min(1f, rest * MASK_RAMP))
  }

  // Scramble: one glyph flickers through the target's letters every stepMs, dimmed, and locks on
  // the landing glyph at delay + duration. An empty target fades out instead.

  private fun drawScrambleCell(
    canvas: Canvas, cell: SplitflapCellPlan, x: Float, w: Float, t: Double, flicker: List<String>, presented: Presented?,
  ) {
    val from = cell.glyphAt(0)
    val to = cell.glyphAt(cell.land)
    val lock = cell.delayMs + cell.durationMs
    if (to.isEmpty()) {
      val alpha = if (t <= cell.delayMs) 1.0 else max(0.0, 1 - (t - cell.delayMs) / (lock - cell.delayMs))
      if (t < lock) drawGlyph(canvas, from, x, 0f, (alpha * 255).toInt(), w)
      return
    }
    val start = if (presented?.dimmed == true) 0.0 else cell.delayMs
    when {
      t >= lock -> drawGlyph(canvas, to, x, 0f, 255, w)
      t < start -> drawGlyph(canvas, from, x, 0f, 255, w)
      else -> {
        val step = floor((t - start) / cell.stepMs).toInt()
        drawGlyph(canvas, flicker.getOrElse(step) { to }, x, 0f, (SCRAMBLE_DIM * 255).toInt(), w)
      }
    }
  }

  // Flip: per step, A shows the next glyph's top half and B the current glyph's bottom half; the
  // top flap C (current, top half) folds 0 → 90° about the hinge in the first half of the step,
  // then the bottom flap D (next, bottom half) drops 90° → 0 in the second half.

  private class FlipPose(
    val top: Int, val bottom: Int,
    val flapTop: Int, val flapTopAngle: Double, val flapTopVisible: Boolean,
    val flapBottom: Int, val flapBottomAngle: Double, val flapBottomVisible: Boolean,
  )

  private fun flipPose(cell: SplitflapCellPlan, t: Double, presented: Presented?): FlipPose {
    val steps = cell.land
    val folded = FLAP_FOLD * Math.PI / 2
    val raised = -FLAP_FOLD * Math.PI / 2
    val path0 = cell.glyphAt(0)
    val resumeTop = presented != null && !presented.topAngle.isNaN() && presented.topGlyph == path0 &&
      presented.topAngle * FLAP_FOLD > 0 && abs(presented.topAngle) < Math.PI / 2
    val resumeBottom = presented != null && !resumeTop && !presented.bottomAngle.isNaN() &&
      presented.bottomGlyph == path0 && presented.bottomAngle * FLAP_FOLD < 0 &&
      abs(presented.bottomAngle) < Math.PI / 2

    fun edge(k: Int) = cell.delayMs + cell.durationMs * cell.easing.inverse(k.toDouble() / steps)
    if (t < edge(0)) {
      return FlipPose(
        if (resumeTop) 1 else 0, 0,
        0, if (resumeTop) presented!!.topAngle else 0.0, resumeTop,
        0, if (resumeBottom) presented!!.bottomAngle else raised, resumeBottom,
      )
    }
    if (t >= cell.delayMs + cell.durationMs) return FlipPose(steps, steps, 0, 0.0, false, 0, 0.0, false)
    var k = 0
    while (k < steps - 1 && t >= edge(k + 1)) k++
    val from = edge(k)
    val to = edge(k + 1)
    val mid = (from + to) / 2
    val topStart = if (k == 0 && resumeTop) presented!!.topAngle else 0.0
    return if (t < mid) {
      val f = (t - from) / (mid - from)
      if (k == 0 && resumeBottom) {
        val a = presented!!.bottomAngle
        FlipPose(k + 1, k, k, topStart + (folded - topStart) * f, true, 0, a + (0 - a) * f, true)
      } else {
        FlipPose(k + 1, k, k, topStart + (folded - topStart) * f, true, k + 1, raised, false)
      }
    } else {
      val f = (t - mid) / (to - mid)
      FlipPose(k + 1, k, k, 0.0, false, k + 1, raised + (0 - raised) * f, true)
    }
  }

  private fun drawFlipCell(
    canvas: Canvas, cell: SplitflapCellPlan, x: Float, w: Float, t: Double, h: Float, p: Playback, presented: Presented?,
  ) {
    val pose = flipPose(cell, t, presented)
    val half = h / 2
    drawHalf(canvas, cell.glyphAt(pose.top), x, w, 0f, half, p.surface, null)
    drawHalf(canvas, cell.glyphAt(pose.bottom), x, w, half, h, p.surface, null)
    if (pose.flapTopVisible) {
      drawHalf(canvas, cell.glyphAt(pose.flapTop), x, w, 0f, half, p.surface, hingeMatrix(w, h, 0f, half, pose.flapTopAngle))
    }
    if (pose.flapBottomVisible) {
      drawHalf(canvas, cell.glyphAt(pose.flapBottom), x, w, half, h, p.surface, hingeMatrix(w, h, half, h, pose.flapBottomAngle))
    }
  }

  // The halves take the surface colour, so the half a flap covers never shows through and no card
  // is drawn: a tinted card read as a highlighted block of text.
  private fun drawFlipBackground(canvas: Canvas, x: Float, w: Float, surface: Int) {
    fill.color = surface
    canvas.drawRect(x, 0f, x + w, cellHeight(), fill)
  }

  /** One half of a flip cell, on the surface colour, optionally turned about the hinge. */
  private fun drawHalf(
    canvas: Canvas, glyph: String, x: Float, w: Float, top: Float, bottom: Float, surface: Int, turn: Matrix?,
  ) {
    canvas.save()
    canvas.translate(x, 0f)
    if (turn != null) canvas.concat(turn)
    canvas.clipRect(0f, top, w, bottom)
    fill.color = surface
    canvas.drawRect(0f, top, w, bottom, fill)
    drawGlyph(canvas, glyph, 0f, 0f, 255, w)
    canvas.restore()
  }

  /** A flip flap's plane, rotated about the hinge line, in the prototype's 220 pt perspective. */
  private fun hingeMatrix(w: Float, h: Float, top: Float, bottom: Float, angle: Double): Matrix {
    val hinge = h / 2
    return projectPlane(w, h, top, bottom, FLIP_PERSPECTIVE) { y ->
      // Point y on the flap, relative to the hinge, rotated about X: CATransform3DRotate's convention.
      val r = y - hinge
      Pair(hinge + (r * cos(angle)).toFloat(), (r * sin(angle)).toFloat())
    }
  }

  /**
   * The projective map of a cell's horizontal band [top, bottom] after a rotation about X, seen
   * with perspective `distance` (pt) from the cell's centre — CSS and Core Animation's m34. `turn`
   * takes a y on the band and returns its rotated y and depth (toward the viewer is positive).
   */
  private fun projectPlane(
    w: Float, h: Float, top: Float, bottom: Float, distance: Float, turn: (Float) -> Pair<Float, Float>,
  ): Matrix {
    val d = PixelUtil.toPixelFromDIP(distance)
    val cx = w / 2
    val cy = h / 2
    fun project(x: Float, y: Float): Pair<Float, Float> {
      val (ry, z) = turn(y)
      val scale = d / (d - z)
      return Pair(cx + (x - cx) * scale, cy + (ry - cy) * scale)
    }
    val (x0, y0) = project(0f, top)
    val (x1, y1) = project(w, top)
    val (x2, y2) = project(w, bottom)
    val (x3, y3) = project(0f, bottom)
    return Matrix().apply {
      setPolyToPoly(
        floatArrayOf(0f, top, w, top, w, bottom, 0f, bottom), 0,
        floatArrayOf(x0, y0, x1, y1, x2, y2, x3, y3), 0, 4,
      )
    }
  }

  // Interruption: the old plan read at this instant, as iOS reads presentation layers.

  private fun capturePresented(old: Playback, renderer: Renderer): List<Presented> {
    val t = old.time(System.nanoTime().coerceAtLeast(frameNanos))
    val h = cellHeight()
    val same = old.renderer == renderer
    return old.plan.cells.mapIndexed { i, cell ->
      val state = Presented(old.widthAt(i, t))
      if (same && old.moving(cell)) {
        when (renderer) {
          Renderer.DRUM -> for ((g, y) in drumLayers(cell, t, h, resumeOffset(cell, old.presented[i], h))) {
            state.glyphYs.putIfAbsent(cell.glyphAt(g), y)
          }
          Renderer.FLIP -> {
            val pose = flipPose(cell, t, old.presented[i])
            if (pose.flapTopVisible) {
              state.topGlyph = cell.glyphAt(pose.flapTop)
              state.topAngle = pose.flapTopAngle
            }
            if (pose.flapBottomVisible) {
              state.bottomGlyph = cell.glyphAt(pose.flapBottom)
              state.bottomAngle = pose.flapBottomAngle
            }
          }
          Renderer.SCRAMBLE -> {
            val start = if (old.presented[i]?.dimmed == true) 0.0 else cell.delayMs
            state.dimmed = t >= start && t < cell.delayMs + cell.durationMs
          }
        }
      }
      state
    }
  }

  private fun <T> font(initial: T) = object : kotlin.properties.ReadWriteProperty<Any?, T> {
    private var value = initial
    override fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>) = value
    override fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: T) {
      if (this.value != value) fontDirty = true
      this.value = value
    }
  }

  companion object {
    const val TAG = "Splitflap"
    private const val DEFAULT_FONT_SIZE = 14f
    private const val ELLIPSIS = "…"
    // Values from the approved prototype, as ios/SplitflapView.mm keeps them.
    private const val MASK_FADE = 0.16f
    private const val MASK_RAMP = 6f
    private const val MASK_LEVELS = 32
    private const val WIDTH_WINDOW = 1.15

    /** A frame move counts for a plan only within this long of it: a later one is another layout. */
    private const val MOVE_WINDOW_MS = 250L
    private const val FLIP_PERSPECTIVE = 220f
    // The top flap folds toward the viewer; flip once here if a device shows it folding away.
    private const val FLAP_FOLD = -1.0
    private const val SCRAMBLE_DIM = 0.55
    private const val SCRAMBLE_MAX_STEPS = 2000
  }
}
